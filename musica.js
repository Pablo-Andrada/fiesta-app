/* ============================================================
   MUSICA · melodias arcade generadas por codigo
   ------------------------------------------------------------
   Igual que los efectos de sonido, la musica NO son archivos
   mp3: se genera en el momento con osciladores. Ventajas:
     - La app no pesa ni un byte mas.
     - Arranca al instante, sin descargas.
     - Cada juego tiene su propio tema.

   COMO SUENA
   Cada tema tiene dos capas:
     MELODIA -> la tonada principal (onda cuadrada, tipo consola)
     BAJO    -> notas graves que marcan el ritmo
   Se repiten en bucle mientras dura la partida.

   COMO SE USA
     Musica.tocar('nave')   -> arranca el tema de ese juego
     Musica.parar()         -> lo detiene
   Respeta el boton de sonido: si esta en mudo, no suena.
   ============================================================ */

const Musica = (() => {

  /* ---- Notas musicales y su frecuencia (en Hz) ---- */
  const N = {
    DO:261.63, DOs:277.18, RE:293.66, REs:311.13, MI:329.63, FA:349.23,
    FAs:369.99, SOL:392.00, SOLs:415.30, LA:440.00, LAs:466.16, SI:493.88,
    DO2:523.25, DOs2:554.37, RE2:587.33, REs2:622.25, MI2:659.25, FA2:698.46,
    FAs2:739.99, SOL2:783.99, LAs2:932.33, LA2:880.00, SI2:987.77, DO3:1046.50,
    _:0,   // silencio
  };

  /* ---- Los temas de cada juego ----
     tempo   = milisegundos que dura cada nota
     melodia = la tonada
     bajo    = notas graves de acompanamiento
     onda    = timbre: 'square' retro, 'triangle' suave, 'sawtooth' aspero */
  const TEMAS = {

    /* Espacial, misteriosa y con tension */
    nave: {
      tempo:150, onda:'square', vol:0.055,
      melodia:[N.LA,N.DO2,N.MI2,N.LA2, N.SOL2,N.MI2,N.DO2,N.MI2,
               N.FA,N.LA,N.DO2,N.FA2, N.MI2,N.DO2,N.LA,N.DO2,
               N.SOL,N.SI,N.RE2,N.SOL2, N.FA2,N.RE2,N.SI,N.RE2,
               N.LA,N.DO2,N.MI2,N.LA2, N.MI2,N.DO2,N.LA,N._],
      bajo:   [N.LA/2,N._,N.LA/2,N._, N.FA/2,N._,N.FA/2,N._,
               N.SOL/2,N._,N.SOL/2,N._, N.LA/2,N._,N.LA/2,N._],
    },

    /* Veloz y nerviosa, como una carrera */
    autos: {
      tempo:125, onda:'square', vol:0.05,
      melodia:[N.MI2,N.MI2,N._,N.MI2, N._,N.DO2,N.MI2,N._,
               N.SOL2,N._,N._,N._, N.SOL,N._,N._,N._,
               N.DO2,N._,N._,N.SOL, N._,N._,N.MI,N._,
               N._,N.LA,N._,N.SI, N._,N.LAs,N.LA,N._],
      bajo:   [N.DO/2,N._,N.SOL/2,N._, N.DO/2,N._,N.SOL/2,N._],
    },

    /* Alegre y rebotona */
    frutas: {
      tempo:160, onda:'triangle', vol:0.06,
      melodia:[N.DO2,N.MI2,N.SOL2,N.MI2, N.FA2,N.LA2,N.FA2,N.DO2,
               N.SOL,N.SI,N.RE2,N.SI, N.DO2,N.MI2,N.DO2,N._],
      bajo:   [N.DO/2,N._,N.SOL/2,N._, N.FA/2,N._,N.DO/2,N._],
    },

    /* Juguetona, tipo dibujito */
    topos: {
      tempo:145, onda:'square', vol:0.05,
      melodia:[N.SOL,N.LA,N.SI,N.SOL, N.DO2,N.SI,N.LA,N.SOL,
               N.MI,N.SOL,N.LA,N.DO2, N.SI,N.SOL,N.MI,N._],
      bajo:   [N.SOL/2,N._,N.RE/2,N._, N.MI/2,N._,N.SOL/2,N._],
    },

    /* Trotecito de carrera */
    corredor: {
      tempo:130, onda:'square', vol:0.05,
      melodia:[N.MI,N.SOL,N.LA,N.SOL, N.MI,N.RE,N.MI,N._,
               N.SOL,N.LA,N.SI,N.LA, N.SOL,N.MI,N.SOL,N._,
               N.LA,N.SI,N.DO2,N.SI, N.LA,N.SOL,N.LA,N._,
               N.MI,N.SOL,N.MI,N.RE, N.DO,N.RE,N.MI,N._],
      bajo:   [N.DO/2,N._,N.DO/2,N._, N.SOL/2,N._,N.SOL/2,N._,
               N.LA/2,N._,N.LA/2,N._, N.FA/2,N._,N.SOL/2,N._],
    },

    /* Tranquila, para pensar */
    memoria: {
      tempo:230, onda:'triangle', vol:0.045,
      melodia:[N.DO2,N.MI2,N.SOL,N.MI2, N.LA,N.DO2,N.MI,N.SOL,
               N.FA,N.LA,N.DO2,N.LA, N.SOL,N.SI,N.RE2,N._],
      bajo:   [N.DO/2,N._,N.LA/2,N._, N.FA/2,N._,N.SOL/2,N._],
    },

    /* Serpenteante, de a poquito */
    snake: {
      tempo:180, onda:'square', vol:0.045,
      melodia:[N.RE,N.FA,N.LA,N.FA, N.MI,N.SOL,N.SI,N.SOL,
               N.DO2,N.LA,N.FA,N.LA, N.RE2,N.LA,N.FA,N._],
      bajo:   [N.RE/2,N._,N.RE/2,N._, N.SOL/2,N._,N.LA/2,N._],
    },

    /* Rebotona, tipo gimnasio */
    basquet: {
      tempo:170, onda:'square', vol:0.05,
      melodia:[N.SOL,N.DO2,N.MI2,N.DO2, N.SOL,N.SI,N.RE2,N.SI,
               N.FA,N.LA,N.DO2,N.LA, N.SOL,N.DO2,N.SOL,N._],
      bajo:   [N.DO/2,N._,N.SOL/2,N._, N.FA/2,N._,N.SOL/2,N._],
    },

    /* Marchita de estadio */
    penales: {
      tempo:175, onda:'square', vol:0.055,
      melodia:[N.DO2,N.DO2,N.SOL,N.SOL, N.LA,N.LA,N.SOL,N._,
               N.FA,N.FA,N.MI,N.MI, N.RE,N.RE,N.DO,N._,
               N.SOL,N.SOL,N.FA,N.FA, N.MI,N.MI,N.RE,N._,
               N.SOL,N.SOL,N.FA,N.FA, N.MI,N.RE,N.DO,N._],
      bajo:   [N.DO/2,N._,N.DO/2,N._, N.FA/2,N._,N.SOL/2,N._],
    },

    /* Constructiva, va subiendo */
    torre: {
      tempo:190, onda:'triangle', vol:0.05,
      melodia:[N.DO,N.MI,N.SOL,N.DO2, N.SI,N.SOL,N.MI,N.SOL,
               N.FA,N.LA,N.DO2,N.FA2, N.MI2,N.DO2,N.LA,N._],
      bajo:   [N.DO/2,N._,N.SOL/2,N._, N.FA/2,N._,N.DO/2,N._],
    },

    /* Enigmatica, de memoria */
    simon: {
      tempo:210, onda:'sine', vol:0.05,
      melodia:[N.DO2,N.MI2,N.SOL2,N.MI2, N.LA,N.DO2,N.MI2,N.DO2,
               N.FA,N.LA,N.DO2,N.LA, N.SOL,N.SI,N.RE2,N._],
      bajo:   [N.DO/2,N._,N.LA/2,N._, N.FA/2,N._,N.SOL/2,N._],
    },
  };

  let ctx=null, timer=null, temaActual=null, paso=0;
  let gananciaMaster=null;

  function motor(){
    if(!ctx){
      const AC=window.AudioContext||window.webkitAudioContext;
      if(!AC) return null;
      ctx=new AC();
      gananciaMaster=ctx.createGain();
      gananciaMaster.gain.value=1;
      gananciaMaster.connect(ctx.destination);
    }
    if(ctx.state==='suspended') ctx.resume();
    return ctx;
  }

  /* Toca una nota puntual */
  function nota(freq, dur, onda, vol){
    const c=motor(); if(!c || !freq) return;
    const osc=c.createOscillator(), gan=c.createGain();
    osc.type=onda;
    osc.frequency.setValueAtTime(freq, c.currentTime);
    gan.gain.setValueAtTime(0.0001, c.currentTime);
    gan.gain.exponentialRampToValueAtTime(vol, c.currentTime+0.012);
    gan.gain.exponentialRampToValueAtTime(0.0001, c.currentTime+dur);
    osc.connect(gan); gan.connect(gananciaMaster);
    osc.start(); osc.stop(c.currentTime+dur+0.02);
  }

  return {
    /* Arranca el tema de un juego (si no tiene, no suena nada) */
    tocar(juego){
      this.parar();
      const tema=TEMAS[juego];
      if(!tema) return;
      if(!Sonido.activo) { temaActual=juego; return; }   // esta en mudo
      const c=motor(); if(!c) return;
      temaActual=juego; paso=0;

      timer=setInterval(()=>{
        if(!Sonido.activo) return;                        // respeta el mudo
        const m=tema.melodia[paso % tema.melodia.length];
        const b=tema.bajo[paso % tema.bajo.length];
        const dur=tema.tempo/1000*0.92;
        if(m) nota(m, dur, tema.onda, tema.vol);
        if(b) nota(b, dur*1.6, 'triangle', tema.vol*0.75);
        paso++;
      }, tema.tempo);
    },

    parar(){
      if(timer){ clearInterval(timer); timer=null; }
      temaActual=null; paso=0;
    },

    /* Baja el volumen de la musica un momento (para que se
       escuchen bien los efectos importantes, como ganar) */
    agachar(ms=1200){
      if(!gananciaMaster) return;
      try{
        const c=motor(); if(!c) return;
        gananciaMaster.gain.cancelScheduledValues(c.currentTime);
        gananciaMaster.gain.setValueAtTime(0.25, c.currentTime);
        gananciaMaster.gain.linearRampToValueAtTime(1, c.currentTime+ms/1000);
      }catch(e){}
    },

    get sonando(){ return temaActual; },
  };
})();
