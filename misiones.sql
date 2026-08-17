-- ================================================================
--  MISIONES DIARIAS Y SEMANALES  ·  Tanda 3 de la gamificacion
-- ----------------------------------------------------------------
--  Objetivo: darle a los chicos una razon para VOLVER cada dia.
--  Cada dia hay 3 misiones cortas y cada semana 1 mision grande.
--  Al cumplirlas, se reclama una recompensa en estrellas.
--
--  Todo se calcula y valida en el servidor (nadie puede inventar
--  progreso desde el navegador). El frontend solo pide y muestra.
--
--  ORDEN DE EJECUCION: correr DESPUES de estrellas.sql.
--  Se puede correr varias veces sin romper nada (es idempotente).
-- ================================================================


-- ----------------------------------------------------------------
-- TABLA 1: misiones_def  (el CATALOGO de misiones posibles)
-- ----------------------------------------------------------------
-- Aca definis QUE misiones existen. Para agregar una nueva, sumas
-- una fila mas abajo en el INSERT. La app las toma solas.
--   periodo = 'diaria' (se renueva cada dia) o 'semanal'
--   metrica = que se mide. Tiene que ser una de estas cuatro:
--       partidas  -> cuantas partidas jugo
--       niveles   -> cuantos niveles supero
--       estrellas -> cuantas estrellas gano
--       jefes     -> cuantos jefes vencio
--   meta   = el numero a alcanzar (ej: 3 partidas)
--   premio = estrellas de recompensa al cumplirla
-- ----------------------------------------------------------------
create table if not exists misiones_def (
  clave   text primary key,                 -- identificador corto (ej: 'd_partidas')
  periodo text not null check (periodo in ('diaria','semanal')),
  titulo  text not null,                    -- lo que ve el chico
  icono   text not null default '🎯',
  metrica text not null check (metrica in ('partidas','niveles','estrellas','jefes')),
  meta    integer not null check (meta > 0),
  premio  integer not null default 0,
  orden   integer not null default 0,       -- para ordenarlas en pantalla
  activa  boolean not null default true      -- apagar una sin borrarla
);

-- Sembrado inicial. El "on conflict" hace que si ya existen, se
-- actualicen con estos valores (asi podes editar y volver a correr).
insert into misiones_def (clave, periodo, titulo, icono, metrica, meta, premio, orden) values
  ('d_partidas',  'diaria',  'Jugá 3 partidas',    '🎮', 'partidas',    3,  30, 1),
  ('d_niveles',   'diaria',  'Superá 5 niveles',   '🚀', 'niveles',     5,  40, 2),
  ('d_estrellas', 'diaria',  'Ganá 150 estrellas', '⭐', 'estrellas', 150,  50, 3),
  ('s_jefes',     'semanal', 'Vencé 5 jefes',      '👾', 'jefes',       5, 200, 1)
on conflict (clave) do update set
  periodo = excluded.periodo, titulo = excluded.titulo, icono = excluded.icono,
  metrica = excluded.metrica, meta   = excluded.meta,   premio = excluded.premio,
  orden   = excluded.orden,   activa = excluded.activa;


-- ----------------------------------------------------------------
-- TABLA 2: misiones_jugador  (el PROGRESO de cada chico)
-- ----------------------------------------------------------------
-- Una fila por jugador + mision + periodo. El "periodo_id" es lo
-- que hace que cada dia (o semana) sea una tanda nueva:
--   diaria  -> '2026-08-17'   (la fecha)
--   semanal -> '2026W33'      (año + numero de semana ISO)
-- Cuando cambia el dia, cambia el periodo_id, y arrancan de cero
-- SIN necesidad de ningun proceso que borre nada. Elegante y barato.
-- ----------------------------------------------------------------
create table if not exists misiones_jugador (
  jugador_id  uuid    not null references jugadores(id)     on delete cascade,
  clave       text    not null references misiones_def(clave) on delete cascade,
  periodo_id  text    not null,
  progreso    integer not null default 0,
  completada  boolean not null default false,
  reclamada   boolean not null default false,
  actualizado timestamptz default now(),
  primary key (jugador_id, clave, periodo_id)
);

create index if not exists idx_misjug on misiones_jugador(jugador_id, periodo_id);

-- Se lee para mostrar el progreso, pero SOLO se escribe por las
-- funciones de abajo (RPC). Cerramos el acceso directo.
alter table misiones_def     enable row level security;
alter table misiones_jugador enable row level security;


-- ----------------------------------------------------------------
-- HELPERS: devuelven el periodo_id actual segun horario argentino
-- ----------------------------------------------------------------
-- Usamos la hora de Argentina (Cordoba) para que el "dia nuevo"
-- arranque a la medianoche de aca, no a la de UTC.
create or replace function _periodo_diario() returns text
language sql stable as $$
  select to_char((now() at time zone 'America/Argentina/Cordoba')::date, 'YYYY-MM-DD');
$$;

create or replace function _periodo_semanal() returns text
language sql stable as $$
  select to_char((now() at time zone 'America/Argentina/Cordoba'), 'IYYY"W"IW');
$$;


-- ----------------------------------------------------------------
-- FUNCION INTERNA: _progresar_misiones
-- ----------------------------------------------------------------
-- La llama sumar_estrellas despues de cada nivel superado. Recibe
-- cuanto sumar de cada metrica en ESTA partida y actualiza todas
-- las misiones activas del jugador para el periodo actual.
-- Devuelve un json con las misiones que RECIEN se completaron
-- (para que la app muestre el cartelito "¡Misión cumplida!").
-- ----------------------------------------------------------------
create or replace function _progresar_misiones(
  p_jugador   uuid,
  p_partidas  integer,
  p_niveles   integer,
  p_estrellas integer,
  p_jefes     integer
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  m           record;
  v_delta     integer;
  v_periodo   text;
  v_yacomp    boolean;
  v_nuevo     integer;
  v_recien    json[] := '{}';
begin
  -- Recorremos cada mision activa del catalogo
  for m in select * from misiones_def where activa order by periodo, orden loop

    -- Cuanto suma esta partida a ESTA mision, segun su metrica
    v_delta := case m.metrica
                 when 'partidas'  then p_partidas
                 when 'niveles'   then p_niveles
                 when 'estrellas' then p_estrellas
                 when 'jefes'     then p_jefes
                 else 0 end;
    if v_delta <= 0 then continue; end if;

    -- Periodo al que pertenece (dia o semana actual)
    v_periodo := case m.periodo when 'semanal' then _periodo_semanal()
                                else _periodo_diario() end;

    -- ¿Ya estaba completada antes de esta partida?
    select completada into v_yacomp
      from misiones_jugador
     where jugador_id = p_jugador and clave = m.clave and periodo_id = v_periodo;

    -- Upsert: crea la fila del periodo si no existe, o le suma el delta
    insert into misiones_jugador (jugador_id, clave, periodo_id, progreso, completada)
    values (p_jugador, m.clave, v_periodo, v_delta, v_delta >= m.meta)
    on conflict (jugador_id, clave, periodo_id) do update
      set progreso    = misiones_jugador.progreso + v_delta,
          completada  = (misiones_jugador.progreso + v_delta) >= m.meta,
          actualizado = now()
    returning progreso into v_nuevo;

    -- Si ANTES no estaba completa y AHORA si -> es un "recien cumplida"
    if coalesce(v_yacomp,false) = false and v_nuevo >= m.meta then
      v_recien := v_recien || json_build_object(
        'clave', m.clave, 'titulo', m.titulo, 'icono', m.icono, 'premio', m.premio);
    end if;
  end loop;

  return array_to_json(v_recien);
end;
$$;


-- ----------------------------------------------------------------
-- REDEFINIMOS sumar_estrellas para ENGANCHAR las misiones
-- ----------------------------------------------------------------
-- Es la misma funcion que ya tenias (misma logica de estrellas),
-- pero al final llama a _progresar_misiones y agrega al resultado
-- la lista de misiones recien cumplidas. Correr esto la reemplaza.
-- ----------------------------------------------------------------
create or replace function sumar_estrellas(
  p_token uuid,
  p_juego text,
  p_nivel integer,
  p_jefe  boolean default false
) returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_jugador uuid;
  v_fiesta  uuid;
  v_gana    integer;
  v_total   bigint;
  v_mis     json;
begin
  select id, fiesta_id into v_jugador, v_fiesta
    from jugadores where token = p_token;
  if v_jugador is null then raise exception 'token invalido'; end if;

  -- Tope de seguridad: nadie salta a un nivel imposible de una
  if p_nivel < 1 or p_nivel > 200 then raise exception 'nivel invalido'; end if;

  v_gana := p_nivel * 10;
  if p_jefe then v_gana := v_gana + p_nivel * 5; end if;

  insert into estrellas (jugador_id, fiesta_id, total, nivel_max, jefes, partidas)
  values (v_jugador, v_fiesta, v_gana, p_nivel, case when p_jefe then 1 else 0 end, 1)
  on conflict (jugador_id) do update
    set total       = estrellas.total + v_gana,
        nivel_max   = greatest(estrellas.nivel_max, p_nivel),
        jefes       = estrellas.jefes + case when p_jefe then 1 else 0 end,
        partidas    = estrellas.partidas + 1,
        actualizado = now()
  returning total into v_total;

  -- NUEVO: actualizamos las misiones con lo de esta partida.
  --   1 partida, 1 nivel superado, v_gana estrellas, 1 jefe si corresponde.
  v_mis := _progresar_misiones(
             v_jugador, 1, 1, v_gana, case when p_jefe then 1 else 0 end);

  return json_build_object('ganadas', v_gana, 'total', v_total, 'misiones', v_mis);
end;
$$;


-- ----------------------------------------------------------------
-- FUNCION: mis_misiones  (para pintar la pestaña Progreso)
-- ----------------------------------------------------------------
-- Devuelve las misiones del jugador para el periodo actual, con su
-- progreso. Si todavia no tiene fila para hoy/esta semana, la crea
-- en cero (asi siempre aparecen las 3 diarias + la semanal).
-- ----------------------------------------------------------------
create or replace function mis_misiones(p_token uuid)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_jugador uuid;
  v_dia     text := _periodo_diario();
  v_sem     text := _periodo_semanal();
begin
  select id into v_jugador from jugadores where token = p_token;
  if v_jugador is null then raise exception 'token invalido'; end if;

  -- Aseguramos que existan las filas del periodo actual (en cero).
  insert into misiones_jugador (jugador_id, clave, periodo_id)
  select v_jugador, d.clave,
         case when d.periodo = 'semanal' then v_sem else v_dia end
    from misiones_def d
   where d.activa
  on conflict (jugador_id, clave, periodo_id) do nothing;

  -- Devolvemos la lista lista para mostrar, ordenada.
  return coalesce((
    select json_agg(x order by x.es_semanal, x.orden)
      from (
        select d.clave, d.periodo, d.titulo, d.icono, d.meta, d.premio, d.orden,
               (d.periodo = 'semanal') as es_semanal,
               least(mj.progreso, d.meta) as progreso,
               mj.completada, mj.reclamada
          from misiones_def d
          join misiones_jugador mj
            on mj.clave = d.clave and mj.jugador_id = v_jugador
           and mj.periodo_id = case when d.periodo='semanal' then v_sem else v_dia end
         where d.activa
      ) x
  ), '[]'::json);
end;
$$;


-- ----------------------------------------------------------------
-- FUNCION: reclamar_mision  (cobrar la recompensa)
-- ----------------------------------------------------------------
-- Si la mision esta completa y no fue reclamada, suma el premio a
-- las estrellas del jugador y la marca como reclamada. Devuelve el
-- premio y el nuevo total. Todo verificado en el servidor.
-- ----------------------------------------------------------------
create or replace function reclamar_mision(p_token uuid, p_clave text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_jugador uuid;
  v_fiesta  uuid;
  v_periodo text;
  v_premio  integer;
  v_total   bigint;
  v_ok      boolean := false;
begin
  select id, fiesta_id into v_jugador, v_fiesta
    from jugadores where token = p_token;
  if v_jugador is null then raise exception 'token invalido'; end if;

  -- Que exista y este activa, y sacamos su periodo y premio
  select case when periodo='semanal' then _periodo_semanal() else _periodo_diario() end,
         premio
    into v_periodo, v_premio
    from misiones_def where clave = p_clave and activa;
  if v_periodo is null then raise exception 'mision inexistente'; end if;

  -- Marcamos reclamada SOLO si esta completa y todavia no se cobro.
  -- El "where" hace que sea a prueba de doble-clic o token repetido.
  update misiones_jugador
     set reclamada = true, actualizado = now()
   where jugador_id = v_jugador and clave = p_clave and periodo_id = v_periodo
     and completada = true and reclamada = false;

  if found then
    v_ok := true;
    -- Acreditamos el premio en las estrellas del jugador
    insert into estrellas (jugador_id, fiesta_id, total)
    values (v_jugador, v_fiesta, v_premio)
    on conflict (jugador_id) do update
      set total = estrellas.total + v_premio, actualizado = now()
    returning total into v_total;
  else
    select total into v_total from estrellas where jugador_id = v_jugador;
  end if;

  return json_build_object('ok', v_ok, 'premio', case when v_ok then v_premio else 0 end,
                           'total', coalesce(v_total,0));
end;
$$;


-- ----------------------------------------------------------------
-- PERMISOS: que la app (rol anon) pueda LLAMAR estas funciones,
-- pero NO tocar las tablas directamente.
-- ----------------------------------------------------------------
grant execute on function mis_misiones(uuid)          to anon;
grant execute on function reclamar_mision(uuid, text) to anon;
-- _progresar_misiones y los helpers los llama solo el servidor.

-- ================================================================
--  FIN misiones.sql
-- ================================================================
