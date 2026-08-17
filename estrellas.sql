-- ============================================================
--  CIBER GAME · ESTRELLAS ⭐ (ranking que nunca baja)
-- ============================================================
--  QUE ES
--  Un segundo ranking, aparte del de Campeones (mejor puntaje).
--  Las estrellas se ACUMULAN y nunca bajan: se ganan jugando,
--  superando niveles y venciendo jefes. Premian la constancia,
--  asi la app sigue viva durante todo el mes de la fiesta.
--
--  POR QUE HACE FALTA
--  El ranking de Campeones guarda solo tu MEJOR marca. Si ya
--  hiciste tu récord, volver a jugar no suma nada. Las estrellas
--  arreglan eso: cada partida suma algo.
--
--  USO: Supabase -> SQL Editor -> pegar -> Run. (Idempotente.)
-- ============================================================


-- ------------------------------------------------------------
-- 1) Estrellas acumuladas por jugador.
-- ------------------------------------------------------------
create table if not exists estrellas (
  jugador_id  uuid primary key references jugadores(id) on delete cascade,
  fiesta_id   uuid not null references fiestas(id) on delete cascade,
  total       bigint not null default 0,
  nivel_max   integer not null default 0,   -- nivel mas alto alcanzado (modo infinito)
  jefes       integer not null default 0,   -- jefes vencidos
  partidas    integer not null default 0,   -- partidas jugadas
  actualizado timestamptz default now()
);

create index if not exists idx_estrellas_fiesta on estrellas(fiesta_id, total desc);

-- La tabla se lee para el ranking, pero solo se escribe por RPC.
alter table estrellas enable row level security;

drop policy if exists "estrellas lectura" on estrellas;
create policy "estrellas lectura" on estrellas for select using (true);


-- ------------------------------------------------------------
-- 2) Sumar estrellas (se llama al terminar un nivel).
--    El SERVIDOR calcula cuantas corresponden: asi nadie puede
--    mandar un numero inventado desde el navegador.
--
--    Formula: nivel superado -> 10 x nivel estrellas
--             jefe vencido   -> 5 x nivel extra
--    Ejemplo: nivel 3 con jefe = 30 + 15 = 45 estrellas
-- ------------------------------------------------------------
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

  return json_build_object('ganadas', v_gana, 'total', v_total);
end;
$$;


-- ------------------------------------------------------------
-- 3) Ranking de Estrellas de una fiesta.
--    Devuelve tambien el TITULO, que sale del total de estrellas.
-- ------------------------------------------------------------
create or replace function ranking_estrellas(p_fiesta uuid)
returns table (
  apodo text, avatar text, total bigint,
  nivel_max integer, jefes integer, titulo text
)
language sql
security definer
set search_path = public, extensions
as $$
  select j.apodo, j.avatar, e.total, e.nivel_max, e.jefes,
    case
      when e.total >= 8000 then 'leyenda'
      when e.total >= 5000 then 'maestro'
      when e.total >= 3000 then 'experto'
      when e.total >= 1500 then 'veloz'
      when e.total >=  500 then 'jugador'
      else 'novato'
    end as titulo
  from estrellas e
  join jugadores j on j.id = e.jugador_id
  where e.fiesta_id = p_fiesta
  order by e.total desc
  limit 50;
$$;


-- ------------------------------------------------------------
-- 4) Mis estrellas (para la pantalla de progreso).
-- ------------------------------------------------------------
create or replace function mis_estrellas(p_token uuid)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_jugador uuid;
  v_row     record;
begin
  select id into v_jugador from jugadores where token = p_token;
  if v_jugador is null then raise exception 'token invalido'; end if;

  select coalesce(total,0) as total, coalesce(nivel_max,0) as nivel_max,
         coalesce(jefes,0) as jefes, coalesce(partidas,0) as partidas
    into v_row
    from estrellas where jugador_id = v_jugador;

  if not found then
    return json_build_object('total',0,'nivel_max',0,'jefes',0,'partidas',0,'titulo','novato');
  end if;

  return json_build_object(
    'total', v_row.total, 'nivel_max', v_row.nivel_max,
    'jefes', v_row.jefes, 'partidas', v_row.partidas,
    'titulo', case
      when v_row.total >= 8000 then 'leyenda'
      when v_row.total >= 5000 then 'maestro'
      when v_row.total >= 3000 then 'experto'
      when v_row.total >= 1500 then 'veloz'
      when v_row.total >=  500 then 'jugador'
      else 'novato' end
  );
end;
$$;


-- ------------------------------------------------------------
-- 5) Permisos: la app solo puede LLAMAR a estas funciones.
-- ------------------------------------------------------------
grant execute on function sumar_estrellas(uuid, text, integer, boolean) to anon;
grant execute on function ranking_estrellas(uuid)                       to anon;
grant execute on function mis_estrellas(uuid)                           to anon;
