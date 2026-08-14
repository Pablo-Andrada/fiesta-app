-- ============================================================
--  CIBER GAME · ADMINISTRADORES CON ROLES (SUPER / NORMAL)
-- ============================================================
--  IDEA
--   - SUPER ADMIN (vos): ve y administra TODAS las fiestas,
--     crea fiestas nuevas y crea las cuentas de los padres.
--   - ADMIN NORMAL (el padre/cliente): entra con su usuario y
--     clave, y SOLO ve y administra SU fiesta. No ve ninguna otra.
--
--  SEGURIDAD
--   Las contraseñas se guardan CIFRADAS y se verifican en el
--   servidor. Un admin normal nunca recibe datos de otras fiestas:
--   el propio servidor le devuelve unicamente la suya.
--
--  COMO USARLO
--   Supabase -> SQL Editor -> New query -> pegar TODO -> Run.
--   Se puede correr varias veces sin romper nada (idempotente).
-- ============================================================


-- 1) pgcrypto: para cifrar y comparar contraseñas.
create extension if not exists pgcrypto;


-- 2) Tabla de administradores.
--    rol       -> 'super' o 'normal'
--    fiesta_id -> a que fiesta pertenece un admin normal
--                 (queda NULL en el super, que las ve todas)
create table if not exists admins (
  id         bigint generated always as identity primary key,
  usuario    text unique not null,
  clave_hash text not null,
  rol        text not null default 'normal',
  fiesta_id  uuid references fiestas(id) on delete cascade,
  creado_el  timestamptz default now()
);

-- Por si la tabla ya existia de antes SIN estas columnas:
alter table admins add column if not exists rol       text not null default 'normal';
alter table admins add column if not exists fiesta_id uuid references fiestas(id) on delete cascade;

-- La tabla queda cerrada: nadie la lee desde la app (RLS sin politicas).
alter table admins enable row level security;


-- ------------------------------------------------------------
-- 3) Verifica usuario + clave. Devuelve true / false.
-- ------------------------------------------------------------
create or replace function login_admin(p_usuario text, p_clave text)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
declare ok boolean;
begin
  select (clave_hash = crypt(p_clave, clave_hash)) into ok
    from admins where usuario = lower(trim(p_usuario));
  return coalesce(ok, false);
end;
$$;


-- ------------------------------------------------------------
-- 4) Crea / actualiza el SUPER ADMIN (lo corres vos a mano).
-- ------------------------------------------------------------
create or replace function set_super_admin(p_usuario text, p_clave text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  insert into admins (usuario, clave_hash, rol, fiesta_id)
  values (lower(trim(p_usuario)), crypt(p_clave, gen_salt('bf')), 'super', null)
  on conflict (usuario) do update
    set clave_hash = excluded.clave_hash, rol = 'super', fiesta_id = null;
end;
$$;


-- ------------------------------------------------------------
-- 5) LOGIN DEL PANEL
--    Verifica el login y devuelve el rol + las fiestas que la
--    persona puede administrar:
--      super  -> todas
--      normal -> solo la suya
--    Formato: { "rol": "...", "fiestas": [ {...}, ... ] }
-- ------------------------------------------------------------
create or replace function admin_entrar_maestro(p_usuario text, p_clave text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_rol     text;
  v_fiesta  uuid;
  v_fiestas json;
begin
  if not login_admin(p_usuario, p_clave) then
    raise exception 'no-autorizado';
  end if;

  select rol, fiesta_id into v_rol, v_fiesta
    from admins where usuario = lower(trim(p_usuario));

  if v_rol = 'super' then
    select coalesce(json_agg(x), '[]'::json) into v_fiestas
      from (select id, codigo, nombre, festejado, activa, clave_admin
              from fiestas order by creada_el desc) x;
  else
    select coalesce(json_agg(x), '[]'::json) into v_fiestas
      from (select id, codigo, nombre, festejado, activa, clave_admin
              from fiestas where id = v_fiesta) x;
  end if;

  return json_build_object('rol', v_rol, 'fiestas', v_fiestas);
end;
$$;


-- ------------------------------------------------------------
-- 6) SUPER · Crear una fiesta nueva.
--    Le pone una clave interna ALEATORIA (el padre no la necesita:
--    el entra con su usuario y clave, no con la clave de fiesta).
--    Devuelve { id, codigo, clave_admin }.
-- ------------------------------------------------------------
create or replace function super_crear_fiesta(
  p_usuario   text, p_clave text,
  p_codigo    text, p_nombre text,
  p_festejado text, p_dias  int default 30
) returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_rol   text;
  v_id    uuid;
  v_clave text;
begin
  if not login_admin(p_usuario, p_clave) then raise exception 'no-autorizado'; end if;
  select rol into v_rol from admins where usuario = lower(trim(p_usuario));
  if v_rol <> 'super' then raise exception 'solo-super'; end if;

  v_clave := encode(gen_random_bytes(9), 'hex');   -- clave interna aleatoria

  begin
    insert into fiestas (codigo, nombre, festejado, clave_admin, activa, expira_el)
    values (upper(trim(p_codigo)), p_nombre, nullif(trim(p_festejado), ''),
            v_clave, true, now() + (p_dias || ' days')::interval)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'codigo-repetido';
  end;

  return json_build_object('id', v_id, 'codigo', upper(trim(p_codigo)), 'clave_admin', v_clave);
end;
$$;


-- ------------------------------------------------------------
-- 7) SUPER · Crear (o actualizar) la cuenta de un admin normal
--    para una fiesta. Estos son los datos que le pasas al padre.
-- ------------------------------------------------------------
create or replace function super_crear_admin(
  p_usuario       text, p_clave text,
  p_nuevo_usuario text, p_nueva_clave text,
  p_fiesta        uuid
) returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_rol text;
begin
  if not login_admin(p_usuario, p_clave) then raise exception 'no-autorizado'; end if;
  select rol into v_rol from admins where usuario = lower(trim(p_usuario));
  if v_rol <> 'super' then raise exception 'solo-super'; end if;

  insert into admins (usuario, clave_hash, rol, fiesta_id)
  values (lower(trim(p_nuevo_usuario)), crypt(p_nueva_clave, gen_salt('bf')), 'normal', p_fiesta)
  on conflict (usuario) do update
    set clave_hash = excluded.clave_hash, rol = 'normal', fiesta_id = excluded.fiesta_id;

  return json_build_object('ok', true, 'usuario', lower(trim(p_nuevo_usuario)));
end;
$$;


-- ------------------------------------------------------------
-- 8) SUPER · Listar los admins (sin exponer las claves).
-- ------------------------------------------------------------
create or replace function super_listar_admins(p_usuario text, p_clave text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_rol text; v_lista json;
begin
  if not login_admin(p_usuario, p_clave) then raise exception 'no-autorizado'; end if;
  select rol into v_rol from admins where usuario = lower(trim(p_usuario));
  if v_rol <> 'super' then raise exception 'solo-super'; end if;

  select coalesce(json_agg(json_build_object(
           'id', a.id, 'usuario', a.usuario, 'rol', a.rol,
           'fiesta_codigo', f.codigo, 'fiesta_nombre', f.nombre)
         order by a.creado_el desc), '[]'::json)
    into v_lista
    from admins a
    left join fiestas f on f.id = a.fiesta_id;

  return v_lista;
end;
$$;


-- ------------------------------------------------------------
-- 9) SUPER · Borrar la cuenta de un admin (nunca a un super).
-- ------------------------------------------------------------
create or replace function super_borrar_admin(p_usuario text, p_clave text, p_id bigint)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_rol text;
begin
  if not login_admin(p_usuario, p_clave) then raise exception 'no-autorizado'; end if;
  select rol into v_rol from admins where usuario = lower(trim(p_usuario));
  if v_rol <> 'super' then raise exception 'solo-super'; end if;

  delete from admins where id = p_id and rol <> 'super';
  return json_build_object('ok', true);
end;
$$;


-- ------------------------------------------------------------
-- 10) Permisos: la app (rol anon) solo puede LLAMAR a estas
--     funciones. Nunca lee la tabla de claves directamente.
-- ------------------------------------------------------------
drop function if exists admin_maestro_fiestas(text, text);   -- version vieja (insegura para roles)

grant execute on function login_admin(text, text)                                  to anon;
grant execute on function admin_entrar_maestro(text, text)                         to anon;
grant execute on function super_crear_fiesta(text, text, text, text, text, int)    to anon;
grant execute on function super_crear_admin(text, text, text, text, uuid)          to anon;
grant execute on function super_listar_admins(text, text)                          to anon;
grant execute on function super_borrar_admin(text, text, bigint)                   to anon;


-- ============================================================
--  CREA TU SUPER ADMIN
--  ------------------------------------------------------------
--  Cambia 'pablo' y 'ELEGI_UNA_CLAVE' por los tuyos y corre esta
--  linea. Para cambiar la clave, la volves a correr con otra.
-- ============================================================
select set_super_admin('pablo', 'ELEGI_UNA_CLAVE');
