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
  const SUPABASE_URL  = 'https://jqmaedynhvkhhtoehbpd.supabase.co';   // tu Project URL
  const SUPABASE_KEY  = 'sb_publishable_cG8nJktS49STqlraQCuHRQ_kcxWs5GZ';   // tu anon public key
  /* ----------------------------------------------------------- */

  const hayServidor = () => SUPABASE_URL !== '' && SUPABASE_KEY !== '';

  let estado = {
    online:    false,   // si logramos hablar con el servidor
    fiestaId:  null,
    fiesta:    null,
    jugadorId: null,
    apodo:     null,
    avatar:    null,
    token:     null,    // clave secreta: prueba que somos nosotros
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

  /* Llama a una FUNCION del servidor (no a una tabla).
     Las funciones seguras validan identidad y limites. */
  async function rpc(nombre, parametros) {
    if (!hayServidor()) throw new Error('sin-servidor');
    const res = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + nombre, {
      method: 'POST',
      headers: {
        'apikey':        SUPABASE_KEY,
        'Authorization': 'Bearer ' + SUPABASE_KEY,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify(parametros),
    });
    if (!res.ok) {
      // Intentamos leer el motivo que manda el servidor
      let motivo='';
      try { const j=await res.json(); motivo=j.message||''; } catch(e){}
      const err=new Error('error-rpc-' + res.status);
      err.motivo=motivo;
      throw err;
    }
    const texto = await res.text();
    return texto ? JSON.parse(texto) : true;
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

    /* Registra al jugador (apodo + avatar) en la fiesta.
       Guarda el TOKEN que devuelve el servidor: es la prueba de
       identidad que despues se usa para puntajes y chat. */
    async entrar(apodo, avatar) {
      estado.apodo  = apodo;
      estado.avatar = avatar;

      if (!estado.online) {
        estado.jugadorId = 'local';
        local.guardar('sesion', { apodo, avatar, codigo: estado.fiesta?.codigo });
        return true;
      }
      try {
        // Usamos la funcion del servidor: valida los datos y nos
        // devuelve el token de forma confiable.
        const r = await rpc('crear_jugador', {
          p_codigo: estado.fiesta.codigo,
          p_apodo:  apodo,
          p_avatar: avatar,
        });
        const nuevo = Array.isArray(r) ? r[0] : r;
        if (!nuevo || !nuevo.token) throw new Error('sin-token');
        estado.jugadorId = nuevo.id;
        estado.token     = nuevo.token;
        // Guardamos la sesion COMPLETA para reconocerlo la proxima vez
        local.guardar('sesion', {
          apodo, avatar,
          codigo:    estado.fiesta?.codigo,
          fiestaId:  estado.fiestaId,
          jugadorId: estado.jugadorId,
          token:     estado.token,
        });
        return true;
      } catch (e) {
        // Si el apodo ya existe en esta fiesta, avisamos
        const motivo = (e.motivo||'') + ' ' + (e.message||'');
        if (motivo.indexOf('ocupado') >= 0 || motivo.indexOf('409') >= 0) {
          return { ok:false, error:'Ese apodo ya está usado. Probá con otro.' };
        }
        if (motivo.indexOf('corto') >= 0) {
          return { ok:false, error:'El apodo es muy corto' };
        }
        console.warn('No se pudo registrar online:', e.message);
        estado.online = false; estado.jugadorId = 'local';
        local.guardar('sesion', { apodo, avatar, codigo: estado.fiesta?.codigo });
        return true;
      }
    },

    /* Intenta retomar la sesion guardada en ESTE navegador.
       Asi el chico no tiene que elegir apodo y avatar cada vez,
       y ademas queda siempre con la misma identidad. */
    async retomarSesion() {
      const ses = local.leer('sesion', null);
      // Con que tengamos apodo y codigo alcanza para reconocerlo.
      // El token solo existe si en su momento hubo servidor.
      if (!ses || !ses.apodo || !ses.codigo) return false;

      // Buscamos la fiesta del codigo guardado
      const fiesta = await this.buscarFiesta(ses.codigo);
      if (!fiesta) return false;

      if (!estado.online) {
        // Sin conexion: igual lo reconocemos con lo guardado
        estado.apodo = ses.apodo; estado.avatar = ses.avatar; estado.jugadorId = 'local';
        return true;
      }
      // Habia servidor pero no hay token guardado (sesion vieja):
      // lo damos de alta de nuevo con el mismo apodo y avatar.
      if (!ses.token) {
        const r = await this.entrar(ses.apodo, ses.avatar);
        return r === true;
      }
      try {
        // Le preguntamos al servidor a quien corresponde este token
        const r = await rpc('recuperar_jugador', { p_token: ses.token });
        const j = Array.isArray(r) ? r[0] : r;
        if (!j || !j.id) return false;
        if (j.fiesta_id !== estado.fiestaId) return false;   // es de otra fiesta
        estado.jugadorId = j.id;
        estado.apodo     = j.apodo;
        estado.avatar    = j.avatar;
        estado.token     = ses.token;
        return true;
      } catch (e) { return false; }
    },

    /* Permite cambiar de jugador (borra la sesion de este navegador) */
    olvidarSesion() {
      try { localStorage.removeItem('fiesta_sesion'); } catch (e) {}
      estado.jugadorId = null; estado.token = null; estado.apodo = null;
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

      if (!estado.online || !estado.token) return;
      try {
        // Ya no escribimos directo en la tabla: llamamos a una
        // funcion del servidor que verifica identidad y topes.
        await rpc('guardar_puntaje_seguro', {
          p_token:  estado.token,
          p_juego:  juego,
          p_puntos: locales[juego].puntos,
          p_nivel:  locales[juego].nivel,
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

    /* ============================================================
       CHAT EN VIVO
       ------------------------------------------------------------
       Solo texto. Cuando se va la ultima persona de la sala, los
       mensajes se borran solos (lo hace la funcion del servidor
       limpiar_chat_si_vacio).
       ============================================================ */

    /* Trae los mensajes mas nuevos.
       Usa una funcion del servidor que ADEMAS limpia la sala si
       ya no queda nadie. Asi el chat se borra solo aunque el
       ultimo celular no alcance a avisar que se fue. */
    async mensajes(desde) {
      if (!estado.online || !estado.fiestaId) return [];
      try {
        const r = await rpc('mensajes_de_fiesta', {
          p_fiesta: estado.fiestaId,
          p_desde:  desde || null,
        });
        return Array.isArray(r) ? r : [];
      } catch (e) { return []; }
    },

    /* Manda un mensaje al chat */
    async enviarMensaje(texto) {
      if (!estado.online || !estado.token) return false;
      const limpio = (texto || '').trim().slice(0, 200);
      if (!limpio) return false;
      try {
        // El servidor pone el apodo y el avatar segun el token,
        // asi nadie puede firmar un mensaje como otra persona.
        await rpc('enviar_mensaje_seguro', { p_token: estado.token, p_texto: limpio });
        return true;
      } catch (e) {
        // Si escribio muy rapido, avisamos con un valor especial
        if (String(e.message).indexOf('429') >= 0 || String(e.message).indexOf('400') >= 0) return 'lento';
        return false;
      }
    },

    /* Avisa "sigo conectado". Se llama cada pocos segundos. */
    async latido() {
      if (!estado.online || !estado.jugadorId || estado.jugadorId === 'local') return;
      try {
        await api('presencia?on_conflict=jugador_id', {
          method: 'POST',
          prefer: 'resolution=merge-duplicates,return=minimal',
          body: JSON.stringify({
            jugador_id: estado.jugadorId,
            fiesta_id:  estado.fiestaId,
            apodo:      estado.apodo,
            avatar:     estado.avatar,
            visto_el:   new Date().toISOString(),
          }),
        });
      } catch (e) {}
    },

    /* Lista de quienes estan conectados ahora (ultimos 30 seg) */
    async conectados() {
      if (!estado.online || !estado.fiestaId) return [];
      try {
        const hace30 = new Date(Date.now() - 30000).toISOString();
        const filas = await api('presencia?fiesta_id=eq.' + estado.fiestaId +
                                '&visto_el=gt.' + encodeURIComponent(hace30) +
                                '&select=apodo,avatar&order=visto_el.desc');
        return filas || [];
      } catch (e) { return []; }
    },

    /* Al salir: se borra la presencia y, si era el ultimo,
       el servidor borra toda la conversacion. */
    async salirDelChat() {
      if (!estado.online || !estado.jugadorId || estado.jugadorId === 'local') return;
      try {
        await api('presencia?jugador_id=eq.' + estado.jugadorId, {
          method: 'DELETE', prefer: 'return=minimal',
        });
        // Le pedimos al servidor que limpie si no queda nadie
        await fetch(SUPABASE_URL + '/rest/v1/rpc/limpiar_chat_si_vacio', {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': 'Bearer ' + SUPABASE_KEY,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ p_fiesta: estado.fiestaId }),
          keepalive: true,          // permite que salga aunque se cierre la pestana
        });
      } catch (e) {}
    },

    /* ============================================================
       PANEL DE ADMINISTRADOR
       ------------------------------------------------------------
       Todo pide la clave de admin, que se verifica en el SERVIDOR.
       La clave nunca queda expuesta: solo se manda para validar.
       ============================================================ */
    admin: {
      clave:        null,   // clave interna de la fiesta que se administra ahora
      fiestaId:     null,
      usuario:      null,   // login maestro (para acciones de super)
      claveMaestra: null,
      rol:          null,   // 'super' o 'normal'

      /* LOGIN DEL PANEL
         Verifica usuario + contraseña en el SERVIDOR y devuelve
         que puede administrar la persona:
           - un SUPER admin recibe TODAS las fiestas
           - un admin NORMAL recibe SOLO la suya
         Devuelve un objeto { rol, fiestas:[...] }, o null si el
         usuario/contraseña estan mal. */
      async entrarMaestro(usuario, clave) {
        try {
          const r = await rpc('admin_entrar_maestro', {
            p_usuario: usuario,
            p_clave:   clave,
          });
          const d = Array.isArray(r) ? r[0] : r;
          if (!d || !d.rol) return null;
          this.usuario = usuario; this.claveMaestra = clave; this.rol = d.rol;
          return d;
        } catch (e) {
          return null;   // el servidor rechazo las credenciales
        }
      },

      /* SUPER · Crea una fiesta nueva. El servidor le pone una
         clave interna aleatoria. Devuelve { id, codigo, clave_admin }
         o { error } si algo fallo (ej: codigo repetido). */
      async crearFiestaSuper(codigo, nombre, festejado, dias, subtitulo, imagen) {
        try {
          const r = await rpc('super_crear_fiesta', {
            p_usuario:   this.usuario, p_clave: this.claveMaestra,
            p_codigo:    codigo, p_nombre: nombre,
            p_festejado: festejado,
            p_subtitulo: subtitulo || null,
            p_imagen:    imagen || null,
            p_dias:      dias || 30,
          });
          const d = Array.isArray(r) ? r[0] : r;
          return (d && d.id) ? d : { error: 'no se pudo' };
        } catch (e) {
          const m = (e.motivo || '') + ' ' + (e.message || '');
          if (m.indexOf('codigo-repetido') >= 0) return { error: 'Ese código ya existe' };
          return { error: 'No se pudo crear la fiesta' };
        }
      },

      /* SUPER · Crea (o actualiza) la cuenta de un admin (padre)
         para una fiesta. Devuelve { ok, usuario } o null. */
      async crearAdmin(nuevoUsuario, nuevaClave, fiestaId) {
        try {
          const r = await rpc('super_crear_admin', {
            p_usuario:       this.usuario, p_clave: this.claveMaestra,
            p_nuevo_usuario: nuevoUsuario, p_nueva_clave: nuevaClave,
            p_fiesta:        fiestaId,
          });
          const d = Array.isArray(r) ? r[0] : r;
          return (d && d.ok) ? d : null;
        } catch (e) { return null; }
      },

      /* SUPER · Lista todos los admins (sin sus claves). */
      async listarAdmins() {
        try {
          const r = await rpc('super_listar_admins', {
            p_usuario: this.usuario, p_clave: this.claveMaestra,
          });
          return Array.isArray(r) ? r : [];
        } catch (e) { return []; }
      },

      /* SUPER · Borra la cuenta de un admin por su id. */
      async borrarAdmin(id) {
        try {
          await rpc('super_borrar_admin', {
            p_usuario: this.usuario, p_clave: this.claveMaestra, p_id: id,
          });
          return true;
        } catch (e) { return false; }
      },

      /* Entra a administrar UNA fiesta. Devuelve sus datos o null. */
      async entrar(codigo, clave) {
        try {
          const r = await rpc('admin_entrar', { p_codigo: codigo, p_clave: clave });
          const d = Array.isArray(r) ? r[0] : r;
          if (!d || !d.fiesta_id) return null;
          this.clave = clave;
          this.fiestaId = d.fiesta_id;
          return d;
        } catch (e) { return null; }
      },

      salir() { this.clave = null; this.fiestaId = null; },

      /* MODERACION DE CHAT
         Lee los mensajes de la fiesta SIN limpiar la sala (a
         diferencia del chat normal, que se borra solo cuando
         queda vacia). Asi el admin puede moderar tranquilo. */
      async mensajesModerar() {
        try {
          const r = await rpc('admin_mensajes', { p_fiesta:this.fiestaId, p_clave:this.clave });
          return Array.isArray(r) ? r : [];
        } catch (e) { return []; }
      },

      /* Borra un mensaje puntual del chat. */
      async borrarMensaje(id) {
        try { await rpc('admin_borrar_mensaje', { p_fiesta:this.fiestaId, p_clave:this.clave, p_id:id }); return true; }
        catch (e) { return false; }
      },

      /* Lista de jugadores con sus datos para moderar */
      async jugadores() {
        try {
          const r = await rpc('admin_jugadores', { p_fiesta: this.fiestaId, p_clave: this.clave });
          return Array.isArray(r) ? r : [];
        } catch (e) { return []; }
      },

      async borrarJugador(id) {
        try { await rpc('admin_borrar_jugador', { p_fiesta:this.fiestaId, p_clave:this.clave, p_jugador:id }); return true; }
        catch (e) { return false; }
      },

      async limpiarChat() {
        try { await rpc('admin_limpiar_chat', { p_fiesta:this.fiestaId, p_clave:this.clave }); return true; }
        catch (e) { return false; }
      },

      async resetearPuntajes() {
        try { await rpc('admin_resetear_puntajes', { p_fiesta:this.fiestaId, p_clave:this.clave }); return true; }
        catch (e) { return false; }
      },

      async activarFiesta(activa) {
        try { await rpc('admin_activar_fiesta', { p_fiesta:this.fiestaId, p_clave:this.clave, p_activa:activa }); return true; }
        catch (e) { return false; }
      },

      /* Crea una fiesta nueva (para tus proximos clientes) */
      async crearFiesta(codigo, nombre, festejado, claveNueva, dias) {
        try {
          const r = await rpc('admin_crear_fiesta', {
            p_clave_maestra: this.clave,
            p_codigo: codigo, p_nombre: nombre, p_festejado: festejado,
            p_clave_admin: claveNueva, p_dias: dias || 30,
          });
          const d = Array.isArray(r) ? r[0] : r;
          return d && d.codigo ? d : null;
        } catch (e) { return null; }
      },
    },

    sesionGuardada() { return local.leer('sesion', null); },
    puntajesLocales() { return local.leer('puntajes', {}); },
  };
})();
