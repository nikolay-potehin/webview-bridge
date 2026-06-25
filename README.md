# Flutter Parental Control PoC — WebView, Audio Streaming, WebSockets

## Project Overview

This project is a Proof-of-Concept (PoC) Flutter application that demonstrates the core technologies required for a parental control app:

- A **WebView** (webview_flutter) that hosts a web application.
- **Bidirectional communication** between the Flutter/Dart layer and JavaScript inside the WebView.
- **Real-time audio capture** from the device microphone as raw PCM bytes (16 kHz, mono, 16‑bit) and streaming it over a **WebSocket** connection.
- **Remote control** – the web interface can start/stop the audio stream, and the Flutter layer processes audio data and sends visual feedback back to the WebView.

The entire system works without modifying the web application’s core logic; Flutter acts as a bridge to access native hardware capabilities.

---

## Architecture

```
┌──────────────────────────┐
│       Flutter App        │
│                          │
│  ┌────────────────────┐  │
│  │     WebView        │  │
│  │ (webview_flutter)  │  │
│  │                    │  │
│  │  HTML/CSS/JS       │  │
│  │  - start/stop btn  │  │
│  │  - volume meter    │  │
│  └───────┬────────────┘  │
│          │  FlutterBridge (JavaScriptChannel)
│          │  postMessage / runJavaScript
│          │               │
│  ┌───────▼────────────┐  │
│  │   Dart Logic       │  │
│  │  - handle commands │  │
│  │  - manage WS conn  │  │
│  │  - audio RMS calc  │  │
│  └───────┬────────────┘  │
│          │ MethodChannel & BinaryMessenger
│          │ "com.example.audio_stream"
│          │               │
│  ┌───────▼────────────┐  │
│  │  Native Audio      │  │
│  │  (Kotlin/Swift)    │  │
│  │  - mic capture     │  │
│  │  - send PCM bytes  │  │
│  └────────────────────┘  │
└───────────┬──────────────┘
            │ WebSocket (wss://)
            │ BINARY frames (PCM data)
            ▼
     ┌─────────────┐
     │  WebSocket  │
     │  Server     │ (echo.websocket.events for PoC, real server later)
     └─────────────┘
```

- **WebView ↔ Flutter**: uses `JavaScriptChannel` named `FlutterBridge`. WebView calls `FlutterBridge.postMessage(...)` to send commands. Flutter calls `runJavaScript(...)` to execute JS functions like `updateLevel(volume)`.
- **Flutter ↔ Native**: uses a platform `MethodChannel` for commands (start/stop) and a `BinaryMessenger` handler to receive a stream of raw audio bytes from the native mic implementation.
- **Network**: Dart manages a `web_socket_channel` connection. Audio bytes are sent directly as binary WebSocket frames.

---

## Technology Stack

- Flutter 3.x (stable)
- Dart 3.x
- Plugin: `webview_flutter` (version ^4.9.0)
- Plugin: `web_socket_channel` (version ^3.0.1)
- Plugin: `permission_handler` (for microphone permission)
- Native Android: Kotlin, `AudioRecord`
- Native iOS: Swift, `AVAudioEngine`
- WebSocket echo server for testing: `wss://echo.websocket.events`

---

## Project Structure

```
parental_control_poc/
├── android/
│   └── app/src/main/kotlin/.../MainActivity.kt
├── ios/
│   └── Runner/AppDelegate.swift
├── lib/
│   └── main.dart
├── pubspec.yaml
└── README.md
```

All logic resides in `lib/main.dart` (for PoC simplicity). Native code for audio capture is in the platform-specific files.

---

## Setup Instructions

1. **Flutter SDK** installed and configured.
2. **Create a new Flutter project**:
   ```bash
   flutter create parental_control_poc
   cd parental_control_poc
   ```
3. **Add dependencies** in `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     webview_flutter: ^4.9.0
     web_socket_channel: ^3.0.1
     permission_handler: ^11.3.1
   ```
   Run `flutter pub get`.
4. **Platform-specific permissions**:
   - **Android**: open `android/app/src/main/AndroidManifest.xml` and add:
     ```xml
     <uses-permission android:name="android.permission.RECORD_AUDIO" />
     <uses-permission android:name="android.permission.INTERNET" />
     ```
   - **iOS**: open `ios/Runner/Info.plist` and add:
     ```xml
     <key>NSMicrophoneUsageDescription</key>
     <string>Microphone access is needed to stream audio</string>
     ```
5. **Minimum SDK versions** (usually fine with Flutter defaults).

---

## Implementation Plan (Step-by-Step for Agents)

### Step 1: Flutter Project Initialization
- Create the project as described above.
- Verify it builds on both Android and iOS (`flutter run`).

### Step 2: WebView Integration and Bidirectional Bridge
- **Objective**: Display a local HTML page inside WebView with start/stop buttons and a volume indicator. Enable two-way communication.
- **Implementation**:
  - In `main.dart`, create a `WebViewController` with `JavaScriptMode.unrestricted`.
  - Add a `JavaScriptChannel` named `'FlutterBridge'` that handles incoming messages.
  - Load local HTML (use `loadHtmlString`) containing:
    - A `startStream()` function that posts `'start_stream'` to the bridge.
    - A `stopStream()` function that posts `'stop_stream'`.
    - JavaScript functions `updateStatus(text)` and `updateLevel(level)` for the Flutter side to call.
  - In Dart, when receiving `'start_stream'`/`'stop_stream'`, trigger audio capture (to be implemented later). For now, just call `updateStatus(...)`.
- **Test**: Build and run. Pressing buttons should show a status update (even if audio is not yet connected).

### Step 3: Native Audio Capture (Android & iOS)
- **Objective**: Implement native code that captures microphone audio as raw PCM 16-bit, 16 kHz mono and streams it to Dart via a platform channel.
- **Platform channel name**: `com.example.audio_stream`
- **Android** (`MainActivity.kt`):
  - Set up a `MethodChannel` with `setMethodCallHandler` for `startAudioStream` and `stopAudioStream`.
  - When starting, request `RECORD_AUDIO` permission at runtime if needed.
  - Create an `AudioRecord` instance with sample rate 16000, channel mono, encoding PCM_16BIT, buffer size from `getMinBufferSize`.
  - Start a background thread that continuously reads audio data and sends it to Dart using `binaryMessenger.send(channelName, ByteBuffer)`.
  - When stopping, release the `AudioRecord` and stop the thread.
- **iOS** (`AppDelegate.swift`):
  - Set up a `FlutterMethodChannel` with same name.
  - Use `AVAudioEngine` and install a tap on the input node.
  - Convert audio buffer to desired format (16 kHz, mono, Int16).
  - Send the raw byte data via `binaryMessenger.send(...)`.
  - Handle microphone permission request.
- **Common**: Ensure that the binary messenger handler is properly registered on the Dart side to receive these bytes (see Step 4).

### Step 4: WebSocket Integration in Dart
- **Objective**: Connect to a WebSocket server and stream the captured audio bytes over it in real time.
- **Dependencies**: `web_socket_channel`.
- **Implementation**:
  - When the user starts streaming (command from WebView), open a `WebSocketChannel.connect(Uri.parse('wss://echo.websocket.events'))`.
  - Listen for binary messages on the platform channel using `ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(channelName, handler)`.
  - In the handler, convert the `ByteData` to `Uint8List` and send via `_wsChannel.sink.add(bytes)`.
  - When stopping, close the WebSocket channel.
  - Also compute a simple volume level (RMS) from the raw audio and call the JavaScript `updateLevel(level)` function via `runJavaScript` for visual feedback.
- **Test**: Use an echo server; you won't hear audio back, but you can verify that data flows (e.g., print bytes length). The volume meter in the WebView should react to sound.

### Step 5: Putting It All Together
- Integrate the pieces: WebView commands start/stop both the native audio capture and the WebSocket connection.
- Ensure that the `BinaryMessenger` handler is set up once during `initState`.
- Manage the lifecycle: when the app is paused/disposed, properly stop audio and close WebSocket.
- Error handling: show messages in WebView if microphone permission is denied or WebSocket fails.
- **Full flow**:
  1. User clicks “Start” in WebView → `FlutterBridge.postMessage('start_stream')`.
  2. Dart handler requests microphone permission, opens WebSocket, invokes native `startAudioStream`.
  3. Native mic starts sending byte chunks to Dart.
  4. Dart handler forwards bytes to WebSocket, calculates RMS, and calls `updateLevel(...)` in WebView.
  5. User clicks “Stop” → Dart calls native `stopAudioStream`, closes WebSocket, updates UI.

### Step 6: Testing and Debugging
- **Local WebView test**: Build and run, open the app. Buttons should work and show status changes. After granting mic permission, the volume bar should move when you speak.
- **Network**: Use a tool like [websocat](https://github.com/vi/websocat) or a simple Node.js WebSocket server to verify that the audio bytes arrive. For echo server, data will be echoed back; you can also log the received echo in Dart.
- **iOS**: Ensure that the app’s Capabilities include “Background Modes” if needed, but for PoC foreground only is fine.
- **Android**: Test on a real device (emulator mic might not provide real data). Ensure the app doesn’t crash when permission is denied.

---

## Key Implementation Details

### Dart-side Binary Message Handler

```dart
void _setupBinaryMessageHandler() {
  ServicesBinding.instance.defaultBinaryMessenger
    .setMessageHandler('com.example.audio_stream', (ByteData? message) {
    if (message == null || _wsChannel == null) return;
    final bytes = message.buffer.asUint8List();
    // Send over WebSocket
    _wsChannel!.sink.add(bytes);
    // Compute RMS and update WebView
    double rms = _calculateRms(bytes);
    _webViewController.runJavaScript("updateLevel($rms)");
    return Future.value(null);
  });
}
```

### RMS Calculation (simplified)

```dart
double _calculateRms(Uint8List pcmInt16) {
  final int16Data = pcmInt16.buffer.asInt16List();
  double sum = 0;
  for (var s in int16Data) sum += s * s;
  final rms = sum / int16Data.length;
  final db = 20 * (log(rms > 0 ? rms : 1) / ln10);
  return ((db + 60) / 60).clamp(0.0, 1.0);
}
```

(Add required helper functions for log.)

### Android Audio Thread Skeleton

```kotlin
Thread {
  val buffer = ByteArray(bufferSize)
  while (isRecording.get()) {
    val read = audioRecord?.read(buffer, 0, bufferSize) ?: 0
    if (read > 0) {
      val data = buffer.copyOf(read)
      runOnUiThread {
        flutterEngine?.dartExecutor?.binaryMessenger
            ?.send(AUDIO_CHANNEL, data)
      }
    }
  }
}.start()
```

### iOS Audio Tap Skeleton

```swift
inputNode?.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
  // convert to desired format, get Int16 samples
  let data = Data(bytes: channelData!, count: length)
  binaryMessenger.send(on: "com.example.audio_stream", message: data)
}
```

---

## Troubleshooting

| Issue | Possible Solution |
|-------|------------------|
| `webview_flutter` build error (Android) | Ensure `compileSdkVersion` is 34+ and `minSdkVersion` is 19+. |
| Microphone permission denied | Implement proper permission request flow with `permission_handler` and handle denial gracefully. |
| No audio data received in Dart | Check that binary messenger handler is registered before starting stream. Ensure the channel name matches exactly. |
| WebSocket connection fails | Verify internet permission, use `wss://` and test with a known echo server. |
| Volume meter not updating | Check that `updateLevel` function exists in WebView’s JS. Ensure RMS calculation doesn’t produce NaN. |

---

## Local WebSocket Server

A simplistic Python WebSocket echo server is included in the `server/` folder. It receives raw PCM audio bytes from the Flutter app and echoes them back, logging statistics about the data flow.

### Setup

```bash
cd server
python -m venv venv

# Activate the virtual environment:
#   Windows (PowerShell):
. venv\Scripts\Activate.ps1
#   macOS / Linux:
source venv/bin/activate

pip install -r requirements.txt
```

### Run

```bash
python server.py
# Defaults: ws://0.0.0.0:8080
# Override host/port:
python server.py --host 0.0.0.0 --port 8080
```

### Connect from Flutter

Update the WebSocket URL in `lib/audio_stream_screen.dart`:

- **Emulator**: `ws://10.0.2.2:8080` (Android emulator maps this to the host machine's `localhost`)
- **Physical device**: `ws://<your-computer-ip>:8080` (both device and computer must be on the same network)

---

## Future Enhancements

- **Audio codec** (Opus) to reduce bandwidth.
- **WebRTC** for more robust real-time communication (if requirements evolve).
- **Background audio** capture on Android/iOS.
- **Authentication** for WebSocket.
- **Multi-platform echo cancellation** for two-way voice.

---

## Conclusion

This PoC demonstrates the core technologies required for the parental control app: embedded WebView with bidirectional bridge, native low-level audio capture, and real-time streaming over WebSocket. The implementation plan above provides a clear, delegatable path to build and integrate these features. Once completed, you will have a solid foundation to extend into a full production application.