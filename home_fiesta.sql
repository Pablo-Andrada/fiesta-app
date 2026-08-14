-- ============================================================
--  CIBER GAME · HOME por fiesta (titulo, subtitulo, imagen)
-- ============================================================
--  Agrega a cada fiesta los datos de su pantalla de BIENVENIDA:
--    - nombre     -> titulo grande en neon (ya existia)
--    - subtitulo  -> segunda linea en neon (ej: "Mis 10 años!!")
--    - imagen_url -> foto del home (nombre del archivo o URL)
--
--  Asi el HOME es distinto para cada cliente, no queda fijo.
--
--  USO: Supabase -> SQL Editor -> pegar -> Run. (Idempotente.)
-- ============================================================


-- 1) Campos nuevos (no rompe nada si ya existen).
alter table fiestas add column if not exists subtitulo  text;
alter table fiestas add column if not exists imagen_url text;


-- 2) Dejar el HOME de la fiesta de León tal cual lo aprobamos.
--    La imagen se referencia por su NOMBRE de archivo: subila al
--    repo (raiz) por GitHub y Vercel la sirve al lado del index.
update fiestas
   set nombre     = 'Cumple de Leon Andrada',
       subtitulo  = 'Mis 10 años!!',
       imagen_url = 'Cumple_Leon_2026.jpg'
 where codigo = 'LEON2026';


-- 3) Recrear super_crear_fiesta para que el SUPER pueda cargar
--    subtitulo e imagen al crear una fiesta nueva.
--    (Se hace DROP porque cambia la firma; el "if exists" evita
--     errores si no estaba.)
drop function if exists super_crear_fiesta(text, text, text, text, text, int);

create or replace function super_crear_fiesta(
  p_usuario   text, p_clave text,
  p_codigo    text, p_nombre text, p_festejado text,
  p_subtitulo text default null,
  p_imagen    text default null,
  p_dias      int  default 30
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

  v_clave := encode(gen_random_bytes(9), 'hex');

  begin
    insert into fiestas (codigo, nombre, festejado, subtitulo, imagen_url,
                         clave_admin, activa, expira_el)
    values (upper(trim(p_codigo)), p_nombre, nullif(trim(p_festejado), ''),
            nullif(trim(p_subtitulo), ''), nullif(trim(p_imagen), ''),
            v_clave, true, now() + (p_dias || ' days')::interval)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'codigo-repetido';
  end;

  return json_build_object('id', v_id, 'codigo', upper(trim(p_codigo)), 'clave_admin', v_clave);
end;
$$;

grant execute on function super_crear_fiesta(text, text, text, text, text, text, text, int) to anon;
