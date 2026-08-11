/* ============================================================
   SONIDO · efectos generados por codigo (Web Audio API)
   ------------------------------------------------------------
   No usa archivos .mp3: los sonidos se GENERAN en el momento
   con osciladores. Ventajas:
     - La app no pesa nada mas de lo que ya pesa.
     - Suenan al instante, sin esperar descargas.
     - Se pueden variar (tono, duracion) sin tener 20 archivos.

   COMO SE USA desde cualquier juego:
     Sonido.play('comer')     -> reproduce un efecto
     Sonido.toggle()          -> prende / apaga
   ============================================================ */

const Sonido = (() => {
  let ctx = null;            // el "motor" de audio del navegador
  let activo = true;         // si el usuario lo tiene prendido

  /* Los navegadores no dejan reproducir audio hasta que el usuario
     toca algo. Por eso creamos el motor en el primer toque. */
  function motor() {
    if (!ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
    }
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }

  /* Toca UNA nota.
     freq  = frecuencia (grave = numero chico, agudo = numero grande)
     dur   = duracion en segundos
     tipo  = forma de onda: 'square' suena retro, 'sine' suave
     vol   = volumen (0 a 1)
     barrido = si se pasa, la nota se desliza hacia esa frecuencia */
  function nota(freq, dur, tipo = 'square', vol = 0.18, barrido = null) {
    const c = motor(); if (!c || !activo) return;
    const osc = c.createOscillator();
    const gan = c.createGain();
    osc.type = tipo;
    osc.frequency.setValueAtTime(freq, c.currentTime);
    if (barrido) osc.frequency.exponentialRampToValueAtTime(Math.max(20, barrido), c.currentTime + dur);
    // Envolvente: sube rapido y baja suave, para que no "cliquee"
    gan.gain.setValueAtTime(0.0001, c.currentTime);
    gan.gain.exponentialRampToValueAtTime(vol, c.currentTime + 0.01);
    gan.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + dur);
    osc.connect(gan); gan.connect(c.destination);
    osc.start(); osc.stop(c.currentTime + dur + 0.02);
  }

  /* Ruido blanco: sirve para explosiones y choques */
  function ruido(dur = 0.3, vol = 0.25) {
    const c = motor(); if (!c || !activo) return;
    const n = Math.floor(c.sampleRate * dur);
    const buffer = c.createBuffer(1, n, c.sampleRate);
    const datos = buffer.getChannelData(0);
    for (let i = 0; i < n; i++) {
      // El ruido se va apagando hacia el final (i/n)
      datos[i] = (Math.random() * 2 - 1) * (1 - i / n);
    }
    const src = c.createBufferSource(); src.buffer = buffer;
    const filtro = c.createBiquadFilter(); filtro.type = 'lowpass';
    filtro.frequency.setValueAtTime(1200, c.currentTime);
    filtro.frequency.exponentialRampToValueAtTime(120, c.currentTime + dur);
    const gan = c.createGain(); gan.gain.setValueAtTime(vol, c.currentTime);
    gan.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + dur);
    src.connect(filtro); filtro.connect(gan); gan.connect(c.destination);
    src.start();
  }

  /* Catalogo de efectos. Cada uno es una receta de notas. */
  const efectos = {
    tap:      () => nota(440, 0.05, 'square', 0.10),
    comer:    () => nota(880, 0.08, 'square', 0.15, 1400),
    disparo:  () => nota(1200, 0.07, 'square', 0.09, 400),
    explosion:() => { ruido(0.35, 0.28); nota(90, 0.3, 'sawtooth', 0.15, 40); },
    choque:   () => { ruido(0.45, 0.32); nota(70, 0.4, 'square', 0.18, 30); },
    acierto:  () => { nota(660, 0.10); setTimeout(() => nota(880, 0.14), 90); },
    error:    () => { nota(200, 0.18, 'sawtooth', 0.16, 110); },
    salto:    () => nota(500, 0.10, 'square', 0.12, 900),
    powerup:  () => { [523, 659, 784, 1047].forEach((f, i) => setTimeout(() => nota(f, 0.12, 'square', 0.16), i * 70)); },
    nivel:    () => { [523, 659, 784, 1047, 1319].forEach((f, i) => setTimeout(() => nota(f, 0.16, 'square', 0.18), i * 100)); },
    gameover: () => { [440, 370, 294, 220].forEach((f, i) => setTimeout(() => nota(f, 0.22, 'sawtooth', 0.16), i * 150)); },
    victoria: () => { [523, 523, 523, 659, 784].forEach((f, i) => setTimeout(() => nota(f, i === 4 ? 0.4 : 0.14, 'square', 0.2), i * 120)); },
  };

  return {
    play(nombre) { try { (efectos[nombre] || efectos.tap)(); } catch (e) {} },
    toggle() { activo = !activo; if (activo) this.play('tap'); return activo; },
    get activo() { return activo; },
    /* Vibracion del celular (si el aparato la soporta) */
    vibrar(ms = 30) { try { navigator.vibrate && navigator.vibrate(ms); } catch (e) {} },
  };
})();
