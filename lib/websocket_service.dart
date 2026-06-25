import 'dart:async';
import 'dart:typed_data';

import 'package:l/l.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Manages a single WebSocket connection used to stream raw audio bytes
/// and receive computed volume levels back from the server.
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  /// Callback invoked when a volume level (0.0–1.0) arrives from server.
  void Function(double level)? onVolume;

  /// `true` when the WebSocket is connected and ready to send data.
  bool get isConnected => _channel != null;

  /// Opens a connection to [url].  Awaits the `ready` future so that
  /// callers know the channel is ready to send.
  ///
  /// Aborts after [timeout] so an unreachable endpoint (e.g. using the
  /// Android-emulator-only alias `10.0.2.2` on a physical device) can
  /// never block the streaming pipeline indefinitely.
  Future<void> connect(String url, {Duration timeout = const Duration(seconds: 5)}) async {
    l.d('WebSocketService: disconnecting any existing channel before connect');
    await disconnect();
    l.i('WebSocketService: connecting to $url');
    _channel = WebSocketChannel.connect(Uri.parse(url));
    try {
      await _channel!.ready.timeout(timeout);
      l.i('WebSocketService: connected to $url');
      // Listen for incoming volume messages (4-byte float32).
      _sub = _channel!.stream.listen(
        (data) {
          if (data is! List<int>) return;
          if (data.length < 4) return;
          final bytes = Uint8List.fromList(data);
          final level = ByteData.sublistView(bytes).getFloat32(0, Endian.little);
          onVolume?.call(level);
        },
        onError: (Object e) {
          l.w('WebSocketService: stream error: $e');
        },
        onDone: () {
          l.d('WebSocketService: stream done');
        },
      );
    } catch (e) {
      // Clean up the half-open channel so isConnected stays accurate.
      await disconnect();
      rethrow;
    }
  }

  /// Sends raw binary data (PCM bytes) over the WebSocket.
  void send(Uint8List bytes) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(bytes);
    } catch (e) {
      l.w('WebSocketService: failed to send ${bytes.length} bytes: $e');
    }
  }

  /// Closes the WebSocket if currently open.
  ///
  /// Nullifies [_channel] immediately so that [isConnected] returns
  /// `false` right away and [send] stops using the old channel.
  /// The actual `sink.close()` is fired in the background (fire-and-
  /// forget) so the caller is never blocked waiting for the server to
  /// complete the closing handshake.
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    final channel = _channel;
    if (channel == null) return;
    _channel = null;
    l.d('WebSocketService: closing channel (fire-and-forget)');
    // Close in the background — don't await.
    channel.sink.close().catchError((Object e) {
      l.w('WebSocketService: error during background close: $e');
    });
  }
}
