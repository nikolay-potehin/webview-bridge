# Where Are My Kids — PoC

MVP на Flutter, демонстрирующий три ключевых сценария: двусторонний мост между WebView и нативной частью, захват сырых PCM-байтов с микрофона в реальном времени, и потоковая передача бинарных данных через WebSocket с серверной обработкой.

## Покрываемые сценарии

### 1. Двусторонний мост WebView ↔ Flutter

UI полностью реализован на HTML/CSS/JS и хостится на GitHub Pages. Flutter загружает страницу в `WebView` и обеспечивает двустороннюю связь:

- **JS → Dart**: `JavaScriptChannel` с именем `FlutterBridge` — WebView отправляет команды (`start_stream`, `stop_stream`) через `postMessage()`.
- **Dart → JS**: `WebViewController.runJavaScript()` — Flutter вызывает функции `updateLevel(level)` и `updateStatus(text)` внутри WebView.

Никакой модификации веб-контента не требуется — Flutter выступает мостом к нативным возможностям.

### 2. Потоковый захват аудио в реальном времени

Захват сырых PCM-байтов (16 кГц, моно, 16-bit) с микрофона через пакет `record` (`AudioRecorder.startStream` с `AudioEncoder.pcm16bits`). Платформный плагин управляет `AudioRecord` (Android) / `AVAudioEngine` (iOS) и отдаёт чанки байтов в Dart-сторону как `Stream<Uint8List>` в реальном времени, без записи в файл.

### 3. WebSocket-стриминг бинарных данных

Сырые PCM-байты отправляются на локальный Python-сервер через WebSocket как бинарные фреймы. Сервер вычисляет RMS-уровень громкости и отправляет обратно `float32` (0.0–1.0). Уровень отображается в WebView в виде waveform-визуализации.

**Альтернатива — gRPC.** Для production-сценариев gRPC bidi-streaming RPC даёт преимущества: строгая типизация через protobuf, встроенный flow control, HTTP/2-мультиплексирование, кодогенерация клиентов. WebSocket выбран для PoC как более простой вариант.

## Поток данных

```
┌──────────────────────────────────────────────────────────────┐
│  WebView (HTML/CSS/JS, GitHub Pages)                         │
│                                                              │
│  ┌─────────────┐      FlutterBridge.postMessage()            │
│  │  Mic button │──────────────────────────────────┐          │
│  └─────────────┘                                  │          │
│  ┌─────────────┐      updateLevel(0.0–1.0)        │          │
│  │  Waveform   │  <───────────────────────────────│          │
│  └─────────────┘                                  │          │
└───────────────────────────────────────────────────┼──────────┘
                                                    │
                                           JavaScriptChannel
                                           runJavaScript
                                                    │
┌───────────────────────────────────────────────────┼──────────┐
│  Flutter (Dart)                                   │          │
│                                                   ▼          │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  AudioStreamScreen                                  │     │
│  │  • обрабатывает команды из WebView                  │     │
│  │  • запрашивает permission_handler                   │     │
│  │  • управляет жизненным циклом записи                │     │
│  └──────┬──────────────────────────────┬───────────────┘     │
│         │ record.startStream()         │ ws.send(bytes)      │
│         ▼                              ▼                     │
│  ┌──────────────┐              ┌──────────────────┐          │
│  │ AudioBridge  │              │ WebSocketService │          │
│  │ (PCM stream) │              │ (binary frames)  │          │
│  └──────┬───────┘              └────────┬─────────┘          │
└─────────┼───────────────────────────────┼────────────────────┘
          │ Native (AudioRecord /         │ WebSocket (ws://)
          │ AVAudioEngine)                │
          ▼                               ▼
   сырые PCM-байты              ┌─────────────────────┐
   16 кГц · mono · 16-bit       │  Python WS Server   │
                                │                     │
                                │  PCM → RMS → float  │
                                │  0.0 – 1.0          │
                                └─────────┬───────────┘
                                          │ float32 (LE)
                                          ▼
                                WebSocketService.onVolume
                                          │
                                          ▼
                                runJavaScript('updateLevel(...)')
```

## Демо

<video src="https://github.com/user-attachments/assets/8accb445-a198-4f35-b0b9-951ed4ff449a" width="40%" controls></video>

## Запуск

### Требования

- Flutter 3.x (stable)
- Python 3.10+
- Android-эмулятор или физическое устройство

### 1. WebSocket-сервер

```bash
cd server
python -m venv .venv

# Windows (PowerShell):
. .venv/Scripts/Activate.ps1
# macOS / Linux:
source .venv/bin/activate

pip install -r requirements.txt
python server.py
# → ws://0.0.0.0:8080
```

### 2. Flutter-приложение

```bash
flutter pub get
flutter run
```

### 3. Настройка URL

В `lib/audio_stream_screen.dart`:

- **Эмулятор Android**: `ws://10.0.2.2:8080` (маппится на `localhost` хост-машины)
- **Физическое устройство**: `ws://<IP-компьютера>:8080` (телефон и компьютер в одной сети)

WebView-контент хостится на GitHub Pages:
`https://nikolay-potehin.github.io/webview-bridge/`

### Структура проекта

```
lib/
├── main.dart              # точка входа
├── audio_stream_screen.dart  # оркестрация: WebView + audio + WebSocket
├── audio_bridge.dart      # захват PCM через record package
├── websocket_service.dart # WebSocket-клиент (send bytes / recv volume)
├── local_html.dart        # fallback HTML для WebView
└── audio_math.dart        # RMS-расчёт (не используется в основном потоке)
server/
├── server.py              # WebSocket-сервер: PCM → RMS → float32
└── requirements.txt
docs/
└── index.html             # WebView UI (GitHub Pages)
```
