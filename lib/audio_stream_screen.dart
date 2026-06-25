import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:l/l.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'audio_bridge.dart';
import 'audio_math.dart';
import 'local_html.dart';
import 'websocket_service.dart';

/// Main screen hosting the WebView and orchestrating the audio pipeline:
///
///   WebView  →  FlutterBridge  →  [AudioStreamScreen]  →  Native mic
///        ↑                                                ↓
///        └──── updateLevel() ← RMS ← PCM bytes ← WebSocket echo ←──┘
class AudioStreamScreen extends StatefulWidget {
  const AudioStreamScreen({super.key});

  @override
  State<AudioStreamScreen> createState() => _AudioStreamScreenState();
}

class _AudioStreamScreenState extends State<AudioStreamScreen> {
  late final WebViewController _webViewController;
  final AudioBridge _audioBridge = AudioBridge();
  final WebSocketService _wsService = WebSocketService();

  bool _isStreaming = false;

  /// Counter for received audio chunks — used to throttle diagnostic logs.
  int _dataChunkCount = 0;

  /// WebSocket endpoint for the local echo server.
  ///
  /// ⚠️ `10.0.2.2` only works on the **Android emulator** (it maps to
  /// the host's localhost). On a **physical device** you must use your
  /// computer's LAN IP, e.g. `ws://192.168.x.x:8080`, and the phone must
  /// be on the same Wi-Fi network as the computer running `server.py`.
  static const String _wsUrl = 'ws://10.0.2.2:8080';

  @override
  void initState() {
    super.initState();
    l.d('AudioStreamScreen initState');
    _initWebView();
    _audioBridge.onData = _onAudioData;
    _wsService.onVolume = _onServerVolume;
  }

  // ── WebView setup ──────────────────────────────────────────────────

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (message) => _handleWebViewMessage(message.message))
      ..loadHtmlString(localHtml);
  }

  void _handleWebViewMessage(String message) {
    l.d('WebView → Flutter: "$message"');
    switch (message) {
      case 'start_stream':
        _startStreaming();
        break;
      case 'stop_stream':
        _stopStreaming();
        break;
    }
  }

  // ── Streaming lifecycle ────────────────────────────────────────────

  Future<void> _startStreaming() async {
    if (_isStreaming) {
      l.w('Start requested but stream is already running');
      return;
    }

    // 1. Request microphone permission.
    l.i('Requesting microphone permission…');
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      l.e('Microphone permission denied (status: $status)');
      _updateStatus('Microphone permission denied');
      return;
    }
    l.i('Microphone permission granted');

    // 2. Open WebSocket connection (non-fatal — audio + waveform still
    //    work even if the echo server is unreachable).
    l.i('Connecting to WebSocket $_wsUrl …');
    try {
      await _wsService.connect(_wsUrl);
      l.i('WebSocket connected');
    } catch (e, st) {
      l.w('WebSocket connection failed — continuing without it', st);
      l.e('WebSocket error: $e');
      _updateStatus('WebSocket unavailable, audio only');
    }

    // 3. Start native audio capture.
    l.i('Starting native audio capture…');
    try {
      await _audioBridge.start();
      _isStreaming = true;
      l.i('Audio stream started');
      _updateStatus('Streaming…');
    } catch (e, st) {
      l.e('Audio start error: $e', st);
      await _wsService.disconnect();
      _updateStatus('Audio start error: $e');
    }
  }

  Future<void> _stopStreaming() async {
    if (!_isStreaming) {
      l.w('Stop requested but stream is not running');
      return;
    }
    _isStreaming = false;
    l.i('Stopping audio stream…');

    await _audioBridge.stop();
    l.d('Native audio capture stopped');

    await _wsService.disconnect();
    l.d('WebSocket disconnected');

    AudioMath.reset();
    l.i('Audio stream stopped');
    _updateStatus('Stopped');
  }

  // ── Audio data handler ─────────────────────────────────────────────

  /// Called for every chunk of PCM bytes arriving from the native side.
  /// Forwards the bytes to the WebSocket.  Volume is computed server-side
  /// when connected; falls back to local computation otherwise.
  void _onAudioData(Uint8List bytes) {
    // Ignore late audio chunks that arrive after stop was requested.
    if (!_isStreaming) {
      l.d('Ignoring ${bytes.length} bytes (stream not running)');
      return;
    }

    // Throttled raw-byte diagnostic log (every 20th chunk).
    _dataChunkCount++;
    if (_dataChunkCount % 20 == 0) {
      final preview = bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      l.i('AudioData chunk #$_dataChunkCount: ${bytes.length} bytes, first 16: $preview');
    }

    // Send raw PCM over WebSocket (only if connected).
    if (_wsService.isConnected) {
      _wsService.send(bytes);
    } else {
      // Fallback: compute volume locally when WS unavailable.
      final level = AudioMath.rmsLevel(bytes);
      _webViewController.runJavaScript('updateLevel($level)');
    }
  }

  /// Called when the server sends back a computed volume level.
  void _onServerVolume(double level) {
    if (!_isStreaming) return;
    _webViewController.runJavaScript('updateLevel($level)');
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _updateStatus(String text) {
    final escaped = text.replaceAll("'", r"\'");
    _webViewController.runJavaScript("updateStatus('$escaped')");
  }

  // ── Lifecycle ───────────────────────────────────────────────────────

  @override
  void dispose() {
    l.d('AudioStreamScreen dispose');
    _stopStreaming();
    _audioBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebView + Audio + WebSocket')),
      body: WebViewWidget(controller: _webViewController),
    );
  }
}
