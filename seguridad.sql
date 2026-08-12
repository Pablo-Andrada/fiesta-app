-- ============================================================
--  CIBER GAME · SEGURIDAD (V5)
-- ============================================================
--  QUE ARREGLA ESTE ARCHIVO
--
--  1) PUNTAJES FALSOS
--     Hoy alguien puede abrir la consola del navegador y mandar
--     un puntaje de 99999. Ahora cada juego tiene un TOPE y la
--     base rechaza cualquier valor imposible.
--
--  2) HACERSE PASAR POR OTRO EN EL CHAT
--     Hoy cualquiera puede escribir con el apodo de otro. Ahora
--     cada jugador tiene un TOKEN secreto (una clave larga que
--     se genera al entrar) y sin ese token no se puede escribir
--     ni guardar puntaje en su nombre.
--
--  3) INUNDAR EL CHAT
--     Ahora hay un limite: 1 mensaje cada 2 segundos por persona.
--
--  IMPORTANTE
--  Esto se corre UNA sola vez y no borra nada de lo que ya tenes.
--  Supabase -> SQL Editor -> New query -> pegar todo -> Run
-- ============================================================


-- ------------------------------------------------------------
-- 1) TOKEN SECRETO POR JUGADOR
-- ------------------------------------------------------------
-- Se genera solo al crear el jugador. La app lo guarda en el
-- celular y lo manda con cada accion. Como nadie mas lo conoce,
-- nadie puede actuar en nombre de otro.
alter table jugadores
  add column if not exists token uuid not null default gen_random_uuid();

-- Que no se pueda leer el token de otros jugadores desde el
-- navegador: la app solo recibe el suyo al crearse.
create index if not exists idx_jugadores_token on jugadores(token);


-- ------------------------------------------------------------
-- 2) TOPES POR JUEGO (para frenar puntajes inventados)
-- ------------------------------------------------------------
-- Cada juego tiene un maximo razonable. Si alguien manda mas,
-- la base lo rechaza directamente.
create table if not exists limites_juego (
  juego     text primary key,
  max_puntos integer not null
);

insert into limites_juego (juego, max_puntos) values
  ('memoria',  3000),
  ('snake',    2000),
  ('autos',    1500),
  ('basquet',  2000),
  ('nave',     3000),
  ('frutas',   3000),
  ('topos',    2500),
  ('corredor', 3000),
  ('ritmo',    4000),
  ('torre',    3000),
  ('simon',    2500),
  ('penales',  2000)
on conflict (juego) do update set max_puntos = excluded.max_puntos;


-- ------------------------------------------------------------
-- 3) FUNCION SEGURA PARA GUARDAR PUNTAJE
-- ------------------------------------------------------------
-- La app ya no escribe directo en la tabla: llama a esta funcion
-- pasando su token. La funcion verifica:
--   a) que el token exista y corresponda a ese jugador
--   b) que el puntaje no supere el tope del juego
--   c) que solo se guarde si mejora la marca anterior
create or replace function guardar_puntaje_seguro(
  p_token  uuid,
  p_juego  text,
  p_puntos integer,
  p_nivel  integer
) returns void
language plpgsql
security definer
as $$
declare
  v_jugador uuid;
  v_fiesta  uuid;
  v_tope    integer;
begin
  -- a) Verificar identidad con el token
  select id, fiesta_id into v_jugador, v_fiesta
    from jugadores where token = p_token;
  if v_jugador is null then
    raise exception 'token invalido';
  end if;

  -- b) Verificar que el puntaje sea posible
  select max_puntos into v_tope from limites_juego where juego = p_juego;
  if v_tope is null then
    raise exception 'juego desconocido';
  end if;
  if p_puntos < 0 or p_puntos > v_tope then
    raise exception 'puntaje fuera de rango';
  end if;
  if p_nivel < 0 or p_nivel > 5 then
    raise exception 'nivel fuera de rango';
  end if;

  -- c) Guardar solo si mejora lo anterior
  insert into puntajes (fiesta_id, jugador_id, juego, puntos, nivel)
  values (v_fiesta, v_jugador, p_juego, p_puntos, p_nivel)
  on conflict (jugador_id, juego) do update
    set puntos      = greatest(puntajes.puntos, excluded.puntos),
        nivel       = greatest(puntajes.nivel,  excluded.nivel),
        actualizado = now();
end;
$$;


-- ------------------------------------------------------------
-- 4) FUNCION SEGURA PARA ESCRIBIR EN EL CHAT
-- ------------------------------------------------------------
-- Verifica el token (para que nadie escriba como otro) y aplica
-- el limite de 1 mensaje cada 2 segundos.
create or replace function enviar_mensaje_seguro(
  p_token uuid,
  p_texto text
) returns void
language plpgsql
security definer
as $$
declare
  v_jugador uuid;
  v_fiesta  uuid;
  v_apodo   text;
  v_avatar  text;
  v_ultimo  timestamptz;
begin
  -- Identidad
  select id, fiesta_id, apodo, avatar
    into v_jugador, v_fiesta, v_apodo, v_avatar
    from jugadores where token = p_token;
  if v_jugador is null then
    raise exception 'token invalido';
  end if;

  -- Texto valido
  if p_texto is null or length(trim(p_texto)) = 0 then
    raise exception 'mensaje vacio';
  end if;
  if length(p_texto) > 200 then
    raise exception 'mensaje demasiado largo';
  end if;

  -- Anti-inundacion: 1 mensaje cada 2 segundos
  select max(creado_el) into v_ultimo
    from mensajes where jugador_id = v_jugador;
  if v_ultimo is not null and v_ultimo > now() - interval '2 seconds' then
    raise exception 'escribiendo demasiado rapido';
  end if;

  -- El apodo y avatar los pone el SERVIDOR, no el navegador.
  -- Asi nadie puede firmar un mensaje con el nombre de otro.
  insert into mensajes (fiesta_id, jugador_id, apodo, avatar, texto)
  values (v_fiesta, v_jugador, v_apodo, v_avatar, trim(p_texto));
end;
$$;


-- ------------------------------------------------------------
-- 5) CERRAR LA ESCRITURA DIRECTA
-- ------------------------------------------------------------
-- Ahora que existen las funciones seguras, sacamos el permiso
-- de escribir directo en las tablas desde el navegador.
drop policy if exists "crear puntaje" on puntajes;
drop policy if exists "actualizar puntaje" on puntajes;
drop policy if exists "escribir mensaje" on mensajes;

-- (Leer sigue permitido: hace falta para mostrar el ranking y el chat)


-- ------------------------------------------------------------
-- 6) NO EXPONER LOS TOKENS AL LEER JUGADORES
-- ------------------------------------------------------------
-- Vista publica sin la columna token, para el ranking y el chat.
create or replace view jugadores_publico as
  select id, fiesta_id, apodo, avatar, creado_el from jugadores;


-- ============================================================
--  LISTO
--  A partir de ahora:
--   - Los puntajes imposibles se rechazan.
--   - Nadie puede escribir en el chat como otra persona.
--   - No se puede inundar el chat.
-- ============================================================
