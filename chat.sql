-- ============================================================
--  CIBER GAME · CHAT EN VIVO
-- ============================================================
--  COMO USARLO
--  Supabase -> SQL Editor -> New query -> pegar todo -> Run
--
--  QUE CREA
--   1) mensajes  : lo que se escribe en el chat
--   2) presencia : quien esta conectado ahora mismo
--   3) Una funcion que BORRA los mensajes cuando se va la
--      ultima persona de la sala (como pediste).
-- ============================================================


-- ------------------------------------------------------------
-- TABLA 1: mensajes del chat
-- Solo texto. No hay fotos, audios ni archivos.
-- ------------------------------------------------------------
create table if not exists mensajes (
  id         uuid primary key default gen_random_uuid(),
  fiesta_id  uuid not null references fiestas(id) on delete cascade,
  jugador_id uuid references jugadores(id) on delete cascade,
  apodo      text not null,
  avatar     text not null default '🙂',
  texto      text not null,
  creado_el  timestamptz default now()
);

create index if not exists idx_mensajes_fiesta on mensajes(fiesta_id, creado_el desc);


-- ------------------------------------------------------------
-- TABLA 2: presencia (quien esta conectado)
-- Cada jugador "avisa que sigue vivo" cada pocos segundos.
-- Si deja de avisar por mas de 30 segundos, se lo considera
-- desconectado.
-- ------------------------------------------------------------
create table if not exists presencia (
  jugador_id uuid primary key references jugadores(id) on delete cascade,
  fiesta_id  uuid not null references fiestas(id) on delete cascade,
  apodo      text not null,
  avatar     text not null default '🙂',
  visto_el   timestamptz default now()
);

create index if not exists idx_presencia_fiesta on presencia(fiesta_id, visto_el desc);


-- ------------------------------------------------------------
-- FUNCION: limpiar la sala si ya no queda nadie
-- ------------------------------------------------------------
-- Se llama desde la app cuando alguien se va. Revisa si queda
-- alguien activo (visto en los ultimos 30 segundos). Si no
-- queda nadie, borra todos los mensajes de esa fiesta.
create or replace function limpiar_chat_si_vacio(p_fiesta uuid)
returns void
language plpgsql
security definer
as $$
declare
  activos int;
begin
  -- Primero sacamos a los que hace rato no dan senales de vida
  delete from presencia
   where fiesta_id = p_fiesta
     and visto_el < now() - interval '30 seconds';

  -- Contamos cuantos quedan conectados
  select count(*) into activos
    from presencia
   where fiesta_id = p_fiesta;

  -- Si no queda nadie, se borra la conversacion
  if activos = 0 then
    delete from mensajes where fiesta_id = p_fiesta;
  end if;
end;
$$;


-- ============================================================
--  SEGURIDAD (RLS)
-- ============================================================
alter table mensajes  enable row level security;
alter table presencia enable row level security;

-- MENSAJES: se pueden leer y escribir, pero NO borrar ni editar.
-- Asi nadie puede borrar el mensaje de otro. El borrado lo hace
-- solo la funcion de arriba cuando la sala queda vacia.
drop policy if exists "leer mensajes" on mensajes;
create policy "leer mensajes" on mensajes
  for select using (true);

drop policy if exists "escribir mensaje" on mensajes;
create policy "escribir mensaje" on mensajes
  for insert with check (
    length(texto) between 1 and 200        -- mensajes cortos
    and length(apodo) between 1 and 20
    and exists (
      select 1 from fiestas f
      where f.id = fiesta_id
        and f.activa = true
        and (f.expira_el is null or f.expira_el > now())
    )
  );

-- PRESENCIA: cada uno puede anunciarse y actualizar su estado
drop policy if exists "leer presencia" on presencia;
create policy "leer presencia" on presencia
  for select using (true);

drop policy if exists "crear presencia" on presencia;
create policy "crear presencia" on presencia
  for insert with check (true);

drop policy if exists "actualizar presencia" on presencia;
create policy "actualizar presencia" on presencia
  for update using (true) with check (true);

drop policy if exists "borrar presencia" on presencia;
create policy "borrar presencia" on presencia
  for delete using (true);


-- ============================================================
--  LISTO
--  El chat ya funciona. Recorda que:
--   - Solo se escribe texto (sin fotos ni audios).
--   - Al irse el ultimo participante, se borra la charla.
-- ============================================================
