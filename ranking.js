/* ============================================================
   RANKING · Conexion con la base de datos (Supabase)
   ------------------------------------------------------------
   Este archivo es el unico que habla con el servidor. El resto
   de la app le pide cosas a traves de la variable global  Fiesta.

   IMPORTANTE — MODO SIN CONEXION:
   Si no hay credenciales cargadas, o si internet falla, la app
   NO se rompe: sigue funcionando y guarda todo en el celular
   (localStorage). El ranking muestra solo al jugador local.
   Esto es clave en un cumple: el wifi puede andar mal y los
   chicos igual tienen que poder jugar.
   ============================================================ */

const Fiesta = (() => {

  /* ---------- CONFIGURACION (completar con tus datos) -------- */
  const SUPABASE_URL  = 'https://jqmaedynhvkhhtoehbpd.supabase.co';   // ej: https://abcdefgh.supabase.co
  const SUPABASE_KEY  = 'sb_publishable_cG8nJktS49STqlraQCuHRQ_kcxWs5GZ';   // la "anon public key"
  /* ----------------------------------------------------------- */

  const hayServidor = () => SUPABASE_URL !== '' && SUPABASE_KEY !== '';

  let estado = {
    online:    false,   // si logramos hablar con el servidor
    fiestaId:  null,
    fiesta:    null,
    jugadorId: null,
    apodo:     null,
    avatar:    null,
  };

  /* ---------- Ayudante para llamar a la API de Supabase ------ */
  async function api(ruta, opciones = {}) {
    if (!hayServidor()) throw new Error('sin-servidor');
    const res = await fetch(SUPABASE_URL + '/rest/v1/' + ruta, {
      ...opciones,
      headers: {
        'apikey':        SUPABASE_KEY,
        'Authorization': 'Bearer ' + SUPABASE_KEY,
        'Content-Type':  'application/json',
        'Prefer':        opciones.prefer || 'return=representation',
        ...(opciones.headers || {}),
      },
    });
    if (!res.ok) throw new Error('error-api-' + res.status);
    const texto = await res.text();
    return texto ? JSON.parse(texto) : null;
  }

  /* ---------- Guardado local (respaldo y sesion) ------------- */
  const local = {
    leer(clave, porDefecto) {
      try { const v = localStorage.getItem('fiesta_' + clave);
            return v ? JSON.parse(v) : porDefecto; }
      catch { return porDefecto; }
    },
    guardar(clave, valor) {
      try { localStorage.setItem('fiesta_' + clave, JSON.stringify(valor)); }
      catch {}
    },
  };

  return {
    estado,

    /* Busca la fiesta por su codigo (ej: LEON2026).
       Devuelve la fiesta, o null si no existe / vencio. */
    async buscarFiesta(codigo) {
      const cod = (codigo || '').trim().toUpperCase();
      if (!cod) return null;

      if (!hayServidor()) {
        // Sin servidor: aceptamos cualquier codigo y jugamos local
        estado.online = false;
        estado.fiesta = { codigo: cod, nombre: 'Fiesta', festejado: '' };
        return estado.fiesta;
      }
      try {
        const filas = await api('fiestas?codigo=eq.' + encodeURIComponent(cod) + '&select=*');
        if (!filas || !filas.length) return null;
        estado.online   = true;
        estado.fiesta   = filas[0];
        estado.fiestaId = filas[0].id;
        return filas[0];
      } catch (e) {
        // Falla de red: seguimos igual en modo local
        console.warn('Sin conexion, modo local:', e.message);
        estado.online = false;
        estado.fiesta = { codigo: cod, nombre: 'Fiesta', festejado: '' };
        return estado.fiesta;
      }
    },

    /* Registra al jugador (apodo + avatar) en la fiesta. */
    async entrar(apodo, avatar) {
      estado.apodo  = apodo;
      estado.avatar = avatar;
      local.guardar('sesion', { apodo, avatar, codigo: estado.fiesta?.codigo });

      if (!estado.online) { estado.jugadorId = 'local'; return true; }
      try {
        // Si ya existe ese apodo en la fiesta, lo reutilizamos
        const ya = await api('jugadores?fiesta_id=eq.' + estado.fiestaId +
                             '&apodo=eq.' + encodeURIComponent(apodo) + '&select=*');
        if (ya && ya.length) { estado.jugadorId = ya[0].id; return true; }

        const nuevo = await api('jugadores', {
          method: 'POST',
          body: JSON.stringify({ fiesta_id: estado.fiestaId, apodo, avatar }),
        });
        estado.jugadorId = nuevo[0].id;
        local.guardar('jugadorId', estado.jugadorId);
        return true;
      } catch (e) {
        console.warn('No se pudo registrar online:', e.message);
        estado.online = false; estado.jugadorId = 'local';
        return true;
      }
    },

    /* Guarda el mejor puntaje de un juego.
       Siempre guarda local; si hay servidor, tambien lo sube. */
    async guardarPuntaje(juego, puntos, nivel) {
      const locales = local.leer('puntajes', {});
      const previo  = locales[juego] || { puntos: 0, nivel: 0 };
      locales[juego] = {
        puntos: Math.max(previo.puntos, puntos),
        nivel:  Math.max(previo.nivel,  nivel),
      };
      local.guardar('puntajes', locales);

      if (!estado.online || !estado.jugadorId || estado.jugadorId === 'local') return;
      try {
        await api('puntajes?on_conflict=jugador_id,juego', {
          method: 'POST',
          prefer: 'resolution=merge-duplicates,return=minimal',
          body: JSON.stringify({
            fiesta_id:  estado.fiestaId,
            jugador_id: estado.jugadorId,
            juego,
            puntos: locales[juego].puntos,
            nivel:  locales[juego].nivel,
          }),
        });
      } catch (e) { console.warn('No se pudo subir el puntaje:', e.message); }
    },

    /* Trae el ranking general (suma de todos los juegos). */
    async rankingGlobal() {
      if (!estado.online) return this._rankingLocal();
      try {
        const filas = await api('ranking_global?fiesta_id=eq.' + estado.fiestaId +
                                '&select=*&order=puntos_totales.desc&limit=50');
        return filas || [];
      } catch { return this._rankingLocal(); }
    },

    /* Trae el ranking de UN juego puntual. */
    async rankingJuego(juego) {
      if (!estado.online) return this._rankingLocal(juego);
      try {
        const filas = await api('puntajes?fiesta_id=eq.' + estado.fiestaId +
                                '&juego=eq.' + juego +
                                '&select=puntos,nivel,jugadores(apodo,avatar)' +
                                '&order=puntos.desc&limit=50');
        return (filas || []).map(f => ({
          apodo:  f.jugadores?.apodo  || '?',
          avatar: f.jugadores?.avatar || '🙂',
          puntos_totales: f.puntos,
          niveles_totales: f.nivel,
        }));
      } catch { return this._rankingLocal(juego); }
    },

    /* Ranking de emergencia: solo el jugador de este celular. */
    _rankingLocal(juego) {
      const p = local.leer('puntajes', {});
      const total = juego
        ? (p[juego]?.puntos || 0)
        : Object.values(p).reduce((a, b) => a + b.puntos, 0);
      const niv = juego
        ? (p[juego]?.nivel || 0)
        : Object.values(p).reduce((a, b) => a + b.nivel, 0);
      return [{
        apodo:  estado.apodo  || 'Vos',
        avatar: estado.avatar || '🙂',
        puntos_totales: total,
        niveles_totales: niv,
        soloLocal: true,
      }];
    },

    sesionGuardada() { return local.leer('sesion', null); },
    puntajesLocales() { return local.leer('puntajes', {}); },
  };
})();
