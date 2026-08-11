-- ============================================================
--  FIESTA APP · Esquema de base de datos (Supabase / PostgreSQL)
-- ============================================================
--  COMO USARLO:
--  1) Entra a supabase.com y crea un proyecto (gratis).
--  2) Menu izquierdo -> "SQL Editor" -> "New query".
--  3) Pega TODO este archivo y dale "Run".
--  4) Anda a Settings -> API y copia:
--       - Project URL
--       - anon public key
--     Esos dos valores van en el index.html (config de arriba).
--
--  NOTA SOBRE LA "anon key":
--  Es publica a proposito, esta pensada para vivir en el navegador.
--  Lo que protege los datos NO es esconderla, sino las politicas
--  RLS (Row Level Security) que estan mas abajo: definen que se
--  puede leer y escribir. Sin RLS, cualquiera podria borrar todo.
-- ============================================================


-- ------------------------------------------------------------
-- TABLA 1: fiestas
-- Cada cumpleanos es una fila. El "codigo" es lo que el chico
-- escribe al entrar (ej: LEON2026) y viene impreso en la tarjeta.
-- ------------------------------------------------------------
create table if not exists fiestas (
  id          uuid primary key default gen_random_uuid(),
  codigo      text unique not null,          -- LEON2026
  nombre      text not null,                 -- "Cumple de Leon"
  festejado   text,                          -- "Leon"
  color_tema  text default '#b14bff',
  activa      boolean default true,          -- se puede apagar
  expira_el   timestamptz,                   -- fecha de vencimiento
  creada_el   timestamptz default now()
);

-- Busquedas por codigo (es lo que mas se consulta)
create index if not exists idx_fiestas_codigo on fiestas(codigo);


-- ------------------------------------------------------------
-- TABLA 2: jugadores
-- Un jugador por chico, por fiesta. Sin datos personales:
-- solo un apodo y un emoji que el elige.
-- ------------------------------------------------------------
create table if not exists jugadores (
  id         uuid primary key default gen_random_uuid(),
  fiesta_id  uuid not null references fiestas(id) on delete cascade,
  apodo      text not null,
  avatar     text not null default '🙂',
  creado_el  timestamptz default now(),
  -- No puede haber dos apodos iguales en la misma fiesta
  unique (fiesta_id, apodo)
);

create index if not exists idx_jugadores_fiesta on jugadores(fiesta_id);


-- ------------------------------------------------------------
-- TABLA 3: puntajes
-- Un registro por jugador y por juego, con su mejor marca.
-- ------------------------------------------------------------
create table if not exists puntajes (
  id           uuid primary key default gen_random_uuid(),
  fiesta_id    uuid not null references fiestas(id) on delete cascade,
  jugador_id   uuid not null references jugadores(id) on delete cascade,
  juego        text not null,                -- 'memoria', 'nave', etc.
  puntos       integer not null default 0,
  nivel        integer not null default 0,
  actualizado  timestamptz default now(),
  -- Un solo registro por jugador+juego (se va actualizando)
  unique (jugador_id, juego)
);

create index if not exists idx_puntajes_fiesta on puntajes(fiesta_id);
create index if not exists idx_puntajes_juego  on puntajes(fiesta_id, juego, puntos desc);


-- ============================================================
--  SEGURIDAD (RLS)
--  Sin esto, cualquiera con la anon key podria borrar la base.
-- ============================================================
alter table fiestas   enable row level security;
alter table jugadores enable row level security;
alter table puntajes  enable row level security;

-- FIESTAS: solo se pueden LEER las activas y no vencidas.
-- Nadie puede crear ni borrar fiestas desde el navegador
-- (eso se hace desde el panel de Supabase o el panel de admin).
drop policy if exists "leer fiestas activas" on fiestas;
create policy "leer fiestas activas" on fiestas
  for select using (
    activa = true
    and (expira_el is null or expira_el > now())
  );

-- JUGADORES: se pueden leer y crear, pero NO borrar ni editar.
-- Asi nadie puede borrar a otro chico del ranking.
drop policy if exists "leer jugadores" on jugadores;
create policy "leer jugadores" on jugadores
  for select using (true);

drop policy if exists "crear jugador" on jugadores;
create policy "crear jugador" on jugadores
  for insert with check (
    length(apodo) between 1 and 20
    and exists (
      select 1 from fiestas f
      where f.id = fiesta_id
        and f.activa = true
        and (f.expira_el is null or f.expira_el > now())
    )
  );

-- PUNTAJES: se pueden leer, crear y actualizar, pero NO borrar.
-- El tope de puntos evita el clasico "999999" desde la consola.
drop policy if exists "leer puntajes" on puntajes;
create policy "leer puntajes" on puntajes
  for select using (true);

drop policy if exists "crear puntaje" on puntajes;
create policy "crear puntaje" on puntajes
  for insert with check (
    puntos >= 0 and puntos <= 100000
    and nivel  >= 0 and nivel  <= 5
  );

drop policy if exists "actualizar puntaje" on puntajes;
create policy "actualizar puntaje" on puntajes
  for update using (true)
  with check (
    puntos >= 0 and puntos <= 100000
    and nivel  >= 0 and nivel  <= 5
  );


-- ============================================================
--  VISTA: ranking global
--  Suma los puntos de todos los juegos de cada jugador.
--  Se consulta desde la app con una sola llamada.
-- ============================================================
create or replace view ranking_global as
select
  j.fiesta_id,
  j.id            as jugador_id,
  j.apodo,
  j.avatar,
  coalesce(sum(p.puntos), 0) as puntos_totales,
  coalesce(sum(p.nivel), 0)  as niveles_totales,
  count(p.id)                as juegos_jugados
from jugadores j
left join puntajes p on p.jugador_id = j.id
group by j.fiesta_id, j.id, j.apodo, j.avatar;


-- ============================================================
--  FIESTA DE PRUEBA (borrala cuando ya no la necesites)
-- ============================================================
insert into fiestas (codigo, nombre, festejado, expira_el)
values ('LEON2026', 'Cumple de Leon', 'Leon', now() + interval '90 days')
on conflict (codigo) do nothing;
