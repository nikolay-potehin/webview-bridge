/// Local HTML content loaded into the WebView.
///
/// Provides start/stop buttons, a status line, and a scrolling waveform
/// visualisation that draws vertical bars whose height reflects the audio
/// volume level reported by the Dart side.
const String localHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      text-align: center;
      padding: 24px 16px;
      margin: 0;
      background: #0f172a;
      color: #e2e8f0;
      min-height: 100vh;
    }
    h2 { margin: 0 0 16px; font-size: 20px; }
    .buttons { display: flex; gap: 12px; justify-content: center; margin-bottom: 12px; }
    button {
      padding: 12px 24px;
      font-size: 16px;
      border: none;
      border-radius: 10px;
      cursor: pointer;
      transition: opacity .15s;
    }
    button:active { opacity: .7; }
    #startBtn { background: #22c55e; color: #fff; }
    #stopBtn  { background: #ef4444; color: #fff; }
    #status { font-size: 14px; color: #94a3b8; margin-bottom: 16px; min-height: 20px; }
    #waveform {
      width: 100%;
      max-width: 600px;
      height: 200px;
      background: #1e293b;
      border-radius: 12px;
      margin: 0 auto;
      display: block;
    }
  </style>
</head>
<body>
  <h2>🎙️ Audio Stream PoC</h2>
  <div class="buttons">
    <button id="startBtn" onclick="startStream()">▶ Start</button>
    <button id="stopBtn"  onclick="stopStream()">⏹ Stop</button>
  </div>
  <p id="status">Idle</p>
  <canvas id="waveform"></canvas>

  <script>
    const canvas = document.getElementById('waveform');
    const ctx = canvas.getContext('2d');
    const MAX_BARS = 120;
    const levels = [];

    function resizeCanvas() {
      canvas.width  = canvas.offsetWidth  * devicePixelRatio;
      canvas.height = canvas.offsetHeight * devicePixelRatio;
      ctx.scale(devicePixelRatio, devicePixelRatio);
    }
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    function drawBars() {
      const w = canvas.offsetWidth;
      const h = canvas.offsetHeight;
      const barWidth = w / MAX_BARS;

      ctx.clearRect(0, 0, w, h);

      for (let i = 0; i < levels.length; i++) {
        const barHeight = Math.max(2, levels[i] * h);
        const x = i * barWidth;
        const y = (h - barHeight) / 2;

        // colour gradient from green (quiet) to red (loud)
        const hue = 120 - levels[i] * 120;
        ctx.fillStyle = `hsl(` + hue + `, 80%, 55%)`;
        ctx.fillRect(x + 1, y, barWidth - 2, barHeight);
      }
      requestAnimationFrame(drawBars);
    }
    drawBars();

    function startStream() { FlutterBridge.postMessage('start_stream'); }
    function stopStream()  { FlutterBridge.postMessage('stop_stream'); }

    function updateStatus(text) {
      document.getElementById('status').innerText = text;
    }

    function updateLevel(level) {
      levels.push(Math.min(1, Math.max(0, level)));
      if (levels.length > MAX_BARS) levels.shift();
    }
  </script>
</body>
</html>
''';
