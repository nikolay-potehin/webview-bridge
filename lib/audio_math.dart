import 'dart:math' as math;
import 'dart:typed_data';

import 'package:l/l.dart';

/// Audio-related math helpers.
class AudioMath {
  AudioMath._();

  /// Counts how many times [rmsLevel] has been called — used to throttle
  /// diagnostic logging so we only log every [logEvery] invocations.
  static int _callCount = 0;
  static const int _logEvery = 20;

  /// EMA-smoothed level so the waveform doesn't jitter on every chunk.
  static double _smoothed = 0.0;

  /// Noise gate: RMS below this is treated as silence.
  /// Emulator mics produce constant low-level noise; this kills it.
  static const double _noiseGate = 300.0;

  /// Smoothing factor.  Higher = faster response, lower = smoother bar.
  static const double _alpha = 0.3;

  /// Computes a normalised volume level (0.0 – 1.0) from raw 16-bit PCM
  /// samples using the RMS value with EMA smoothing and a noise gate.
  static double rmsLevel(Uint8List pcmInt16) {
    if (pcmInt16.length < 2) {
      l.w('AudioMath: received ${pcmInt16.length} bytes — too few for a sample');
      return _smoothed;
    }

    final int16Data = pcmInt16.buffer.asInt16List();
    if (int16Data.isEmpty) return _smoothed;

    double sumOfSquares = 0;
    int minSample = 32767;
    int maxSample = -32768;
    for (final sample in int16Data) {
      sumOfSquares += sample * sample;
      if (sample < minSample) minSample = sample;
      if (sample > maxSample) maxSample = sample;
    }
    final rms = math.sqrt(sumOfSquares / int16Data.length);

    // Noise gate: below threshold → silence.
    double linear;
    if (rms < _noiseGate) {
      linear = 0.0;
    } else {
      // Linear normalisation: RMS / full-scale.
      const double ref = 32767;
      linear = (rms / ref).clamp(0.0, 1.0);
      // Gamma curve (sqrt) expands the quiet range.
      linear = math.sqrt(linear);
    }

    // EMA smoothing: blend new value with previous.
    _smoothed = _smoothed + _alpha * (linear - _smoothed);

    // Throttled diagnostic log.
    _callCount++;
    if (_callCount % _logEvery == 0) {
      l.i(
        'AudioMath: samples=${int16Data.length} '
        'bytes=${pcmInt16.length} '
        'min=$minSample max=$maxSample '
        'rms=${rms.toStringAsFixed(1)} '
        'linear=${linear.toStringAsFixed(4)} '
        'smoothed=${_smoothed.toStringAsFixed(4)}',
      );
    }

    return _smoothed;
  }

  /// Resets the smoothed state (call when streaming stops).
  static void reset() {
    _smoothed = 0.0;
  }
}
