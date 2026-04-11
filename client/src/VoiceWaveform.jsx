import { useEffect, useRef } from "react";

export default function VoiceWaveform({ stream }) {
  const canvasRef = useRef(null);
  const rafRef = useRef(0);
  const ctxRef = useRef(null);

  useEffect(() => {
    if (!stream) return undefined;
    let audioCtx;
    let cancelled = false;

    (async () => {
      try {
        audioCtx = new AudioContext();
        if (audioCtx.state === "suspended") await audioCtx.resume();
      } catch {
        return;
      }
      if (cancelled) return;
      const src = audioCtx.createMediaStreamSource(stream);
      const analyser = audioCtx.createAnalyser();
      analyser.fftSize = 128;
      analyser.smoothingTimeConstant = 0.65;
      src.connect(analyser);
      const data = new Uint8Array(analyser.frequencyBinCount);
      const canvas = canvasRef.current;
      if (!canvas) return;
      const c = canvas.getContext("2d");
      if (!c) return;
      ctxRef.current = c;

      const draw = () => {
        if (cancelled) return;
        analyser.getByteFrequencyData(data);
        const { width, height } = canvas;
        c.clearRect(0, 0, width, height);
        const bars = 40;
        const step = Math.floor(data.length / bars) || 1;
        const barW = width / bars - 2;
        for (let i = 0; i < bars; i++) {
          let sum = 0;
          for (let j = 0; j < step; j++) sum += data[i * step + j] || 0;
          const v = sum / step / 255;
          const h = Math.max(4, v * height * 0.95);
          const x = i * (barW + 2) + 1;
          const y = (height - h) / 2;
          c.fillStyle = getComputedStyle(document.documentElement).getPropertyValue("--tg-blue").trim() || "#3390ec";
          if (typeof c.roundRect === "function") {
            c.beginPath();
            c.roundRect(x, y, barW, h, 3);
            c.fill();
          } else {
            c.fillRect(x, y, barW, h);
          }
        }
        rafRef.current = requestAnimationFrame(draw);
      };
      draw();
    })();

    return () => {
      cancelled = true;
      cancelAnimationFrame(rafRef.current);
      ctxRef.current = null;
      if (audioCtx) audioCtx.close().catch(() => {});
    };
  }, [stream]);

  return <canvas ref={canvasRef} className="voice-waveform-canvas" width={320} height={44} />;
}
