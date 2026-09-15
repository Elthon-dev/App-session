import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the native Kotlin MediaProjection handler over MethodChannel.
class ScreenCaptureService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('openbridge/screen');

  bool capturing = false;
  String? lastFrame;
  Timer? _timer;

  /// Longest side in px for scaled preview frames.
  int maxSide = 720;

  /// JPEG quality 10..95.
  int quality = 60;

  /// Set up the Dart-side handler for native -> Dart notifications.
  void bind() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'captureStopped') {
        await stop();
      }
      return null;
    });
  }

  Future<bool> start() async {
    try {
      final ok = await _channel.invokeMethod<bool>('startCapture', {
        'maxSide': maxSide,
        'quality': quality,
      });
      capturing = ok == true;
      notifyListeners();
      return capturing;
    } catch (_) {
      return false;
    }
  }

  bool get active => capturing;

  /// Polls the native side for the latest jpeg frame at [intervalMs].
  void poll({required void Function(String dataUrl) onFrame, int intervalMs = 280}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (!capturing) return;
      String? frame;
      try {
        frame = await _channel.invokeMethod<String>('captureFrame');
      } catch (_) {}
      if (frame != null && frame.isNotEmpty) {
        lastFrame = frame;
        onFrame(frame);
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    capturing = false;
    lastFrame = null;
    try {
      await _channel.invokeMethod('stopCapture');
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}