-- ============================================================
--  CIBER GAME · PANEL DE ADMIN (funciones base)
-- ============================================================
--  Estas funciones ya estan corriendo en tu Supabase (se
--  crearon en la V6). Este archivo las deja guardadas en el
--  repo para que la base se pueda RECONSTRUIR desde cero.
--
--  IMPORTANTE
--  No hace falta correrlo en tu Supabase actual: ahi ya existen.
--  Sirve solo para reproducir la base en un proyecto nuevo.
--
--  ORDEN de reconstruccion (proyecto nuevo):
--   1) schema.sql   2) chat.sql   3) seguridad.sql
--   4) admin_panel.sql (este)     5) admin_login.sql
--   6) home_fiesta.sql  7) moderacion_chat.sql  8) chat_v10.sql
-- ============================================================


-- Clave de admin por fiesta (cada fiesta tiene la suya).
alter table fiestas add column if not exists clave_admin text;


-- ------------------------------------------------------------
-- es_admin: ¿esta clave es la de admin de esta fiesta?
-- La usan casi todas las funciones de abajo para autorizar.
-- ------------------------------------------------------------
create or replace function es_admin(p_fiesta uuid, p_clave text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from fiestas
     where id = p_fiesta
       and clave_admin is not null
       and clave_admin = p_clave
  );
$$;


-- ------------------------------------------------------------
-- admin_entrar: valida codigo + clave y devuelve los datos de
-- la fiesta (nombre y contadores) para el panel.
-- ------------------------------------------------------------
create or replace function admin_entrar(p_codigo text, p_clave text)
returns table (fiesta_id uuid, nombre text, jugadores bigint, mensajes bigint)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid;
  v_nombre text;
begin
  select f.id, f.nombre into v_id, v_nombre
    from fiestas f where f.codigo = upper(trim(p_codigo));
  if v_id is null or not es_admin(v_id, p_clave) then
    raise exception 'codigo o clave incorrectos';
  end if;

  return query
    select v_id, v_nombre,
      (select count(*) from jugadores j where j.fiesta_id = v_id),
      (select count(*) from mensajes  m where m.fiesta_id = v_id);
end;
$$;


-- ------------------------------------------------------------
-- admin_jugadores: lista de jugadores con sus datos para moderar
-- (mensajes escritos, puntos totales y si esta conectado).
-- ------------------------------------------------------------
create or replace function admin_jugadores(p_fiesta uuid, p_clave text)
returns table (id uuid, apodo text, avatar text,
               mensajes bigint, puntos bigint, conectado boolean)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;

  return query
    select j.id, j.apodo, j.avatar,
      (select count(*) from mensajes m where m.jugador_id = j.id),
      coalesce((select sum(p.puntos) from puntajes p where p.jugador_id = j.id), 0)::bigint,
      exists (select 1 from presencia pr
               where pr.jugador_id = j.id
                 and pr.visto_el > now() - interval '30 seconds')
    from jugadores j
    where j.fiesta_id = p_fiesta
    order by j.creado_el asc;
end;
$$;


-- ------------------------------------------------------------
-- admin_borrar_jugador: saca a un jugador (y en cascada sus
-- mensajes y puntajes).
-- ------------------------------------------------------------
create or replace function admin_borrar_jugador(p_fiesta uuid, p_clave text, p_jugador uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;
  delete from jugadores where id = p_jugador and fiesta_id = p_fiesta;
end;
$$;


-- ------------------------------------------------------------
-- admin_limpiar_chat: borra todos los mensajes de la fiesta.
-- ------------------------------------------------------------
create or replace function admin_limpiar_chat(p_fiesta uuid, p_clave text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;
  delete from mensajes where fiesta_id = p_fiesta;
end;
$$;


-- ------------------------------------------------------------
-- admin_resetear_puntajes: pone el ranking en cero.
-- ------------------------------------------------------------
create or replace function admin_resetear_puntajes(p_fiesta uuid, p_clave text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;
  delete from puntajes where fiesta_id = p_fiesta;
end;
$$;


-- ------------------------------------------------------------
-- admin_activar_fiesta: abre (true) o cierra (false) la fiesta.
-- ------------------------------------------------------------
create or replace function admin_activar_fiesta(p_fiesta uuid, p_clave text, p_activa boolean)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;
  update fiestas set activa = p_activa where id = p_fiesta;
end;
$$;


-- ------------------------------------------------------------
-- admin_crear_fiesta: crea una fiesta nueva. Autoriza con la
-- clave de admin de una fiesta ya existente (p_clave_maestra).
-- (Version original; el flujo nuevo usa super_crear_fiesta.)
-- ------------------------------------------------------------
create or replace function admin_crear_fiesta(
  p_clave_maestra text,
  p_codigo        text,
  p_nombre        text,
  p_festejado     text,
  p_clave_admin   text,
  p_dias          int default 30
) returns table (id uuid, codigo text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  -- Autoriza: la clave maestra debe ser la de admin de alguna fiesta.
  if not exists (select 1 from fiestas where clave_admin = p_clave_maestra) then
    raise exception 'no autorizado';
  end if;

  begin
    insert into fiestas (codigo, nombre, festejado, clave_admin, activa, expira_el)
    values (upper(trim(p_codigo)), p_nombre, nullif(trim(p_festejado), ''),
            p_clave_admin, true, now() + (p_dias || ' days')::interval)
    returning fiestas.id into v_id;
  exception when unique_violation then
    raise exception 'codigo-repetido';
  end;

  return query select v_id, upper(trim(p_codigo));
end;
$$;


-- ------------------------------------------------------------
-- Permisos: la app (rol anon) solo puede LLAMAR a estas
-- funciones. La verificacion de clave la hace es_admin adentro.
-- ------------------------------------------------------------
grant execute on function es_admin(uuid, text)                                  to anon;
grant execute on function admin_entrar(text, text)                              to anon;
grant execute on function admin_jugadores(uuid, text)                           to anon;
grant execute on function admin_borrar_jugador(uuid, text, uuid)                to anon;
grant execute on function admin_limpiar_chat(uuid, text)                        to anon;
grant execute on function admin_resetear_puntajes(uuid, text)                   to anon;
grant execute on function admin_activar_fiesta(uuid, text, boolean)             to anon;
grant execute on function admin_crear_fiesta(text, text, text, text, text, int) to anon;
