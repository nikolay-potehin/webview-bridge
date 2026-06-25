import 'package:flutter/material.dart';
import 'package:l/l.dart';

import 'audio_stream_screen.dart';

// ignore: experimental_member_use
void main() => l.capture(
  () => runApp(const WebViewBridgeApp()),
  const LogOptions(handlePrint: true, outputInRelease: true, printColors: true),
);

class WebViewBridgeApp extends StatelessWidget {
  const WebViewBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'WebView Bridge PoC', home: AudioStreamScreen());
  }
}
