-- ============================================================
--  CIBER GAME · MODERACIÓN DE CHAT (para admins)
-- ============================================================
--  Permite que un admin (super o el de la fiesta) pueda:
--   - LEER el chat de su fiesta sin que se borre solo, aunque
--     no haya nadie conectado (la lectura normal limpia la sala
--     vacía; esta no, para poder moderar tranquilo).
--   - BORRAR un mensaje puntual.
--
--  Ambas verifican la clave de la fiesta con es_admin(), la
--  misma que ya usan las demas funciones de admin.
--
--  USO: Supabase -> SQL Editor -> pegar -> Run. (Idempotente.)
-- ============================================================


-- Borramos versiones viejas (si existen) para poder recrearlas.
-- Postgres no deja cambiar el tipo de retorno con CREATE OR REPLACE,
-- por eso primero se hace DROP. El "if exists" evita errores si no
-- existian. Perder estas funciones un instante no afecta nada.
drop function if exists admin_mensajes(uuid, text);
drop function if exists admin_borrar_mensaje(uuid, text, uuid);


-- ------------------------------------------------------------
-- Leer los mensajes de una fiesta (para moderar). NO limpia.
-- ------------------------------------------------------------
create or replace function admin_mensajes(p_fiesta uuid, p_clave text)
returns table (id uuid, apodo text, avatar text, texto text, creado_el timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;

  return query
    select m.id, m.apodo, m.avatar, m.texto, m.creado_el
      from mensajes m
     where m.fiesta_id = p_fiesta
     order by m.creado_el asc
     limit 200;
end;
$$;


-- ------------------------------------------------------------
-- Borrar un mensaje puntual de la fiesta.
-- ------------------------------------------------------------
create or replace function admin_borrar_mensaje(p_fiesta uuid, p_clave text, p_id uuid)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not es_admin(p_fiesta, p_clave) then
    raise exception 'clave incorrecta';
  end if;

  delete from mensajes where id = p_id and fiesta_id = p_fiesta;
  return json_build_object('ok', true);
end;
$$;


-- La app (rol anon) solo puede LLAMAR a estas funciones.
grant execute on function admin_mensajes(uuid, text)              to anon;
grant execute on function admin_borrar_mensaje(uuid, text, uuid)  to anon;
