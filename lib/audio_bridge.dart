import 'dart:async';
import 'dart:typed_data';

import 'package:l/l.dart';
import 'package:record/record.dart';

/// Callback invoked for every chunk of raw PCM audio bytes received
/// from the native side.
typedef AudioDataCallback = void Function(Uint8List bytes);

/// Wraps the `record` package to capture raw PCM 16-bit audio and expose
/// it as a stream of bytes.
///
/// Uses [AudioRecorder.startStream] with [AudioEncoder.pcm16bits] so the
/// platform plugin handles all native AudioRecord/MediaCodec plumbing,
/// endian conversion, and thread management for us.
class AudioBridge {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Uint8List>? _sub;
  AudioDataCallback? onData;

  /// Starts streaming raw PCM 16-bit audio at 16 kHz mono.
  ///
  /// Each chunk from the platform stream is forwarded to [onData].
  Future<void> start() async {
    l.i('AudioBridge: starting PCM stream');

    // Stop any existing stream first.
    await stop();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _sub = stream.listen(
      (Uint8List bytes) {
        if (onData != null) {
          onData!(bytes);
        }
      },
      onError: (Object e, StackTrace st) {
        l.e('AudioBridge: stream error: $e', st);
      },
      onDone: () {
        l.d('AudioBridge: stream done');
      },
    );

    l.i('AudioBridge: PCM stream started');
  }

  /// Stops the audio stream and cancels the subscription.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // stop() throws if not recording — safe to ignore.
    }
    l.i('AudioBridge: PCM stream stopped');
  }

  /// Releases recorder resources. Call in `dispose`.
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    l.d('AudioBridge: disposed');
  }
}
