import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the native Kotlin MediaProjection handler over MethodChannel.
class ScreenCaptureService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('openbridge/screen');

  bool capturing = false;
  String? lastError;
  String? lastFrame;
  Timer? _timer;

  /// Shizuku is running on the device.
  bool shizukuAvailable = false;

  /// OpenBridge is authorized inside the Shizuku app.
  bool shizukuGranted = false;

  /// Notification permission granted (always true before Android 13).
  bool notificationGranted = true;

  /// App is exempt from battery optimizations.
  bool batteryExempt = false;

  /// True when shell-based control commands will actually work.
  bool get controlReady => shizukuAvailable && shizukuGranted;

  /// Longest side in px for scaled preview frames.
  int maxSide = 720;

  /// JPEG quality 10..95.
  int quality = 60;

  /// Set up the Dart-side handler for native -> Dart notifications.
  void bind() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'captureStopped':
          await stop();
        case 'shizukuStatusChanged':
        case 'permissionChanged':
          await refreshPermissions();
      }
      return null;
    });
  }

  /// Query current Shizuku availability + permission state from native.
  Future<void> refreshShizuku() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('shizukuStatus');
      shizukuAvailable = m?['available'] == true;
      shizukuGranted = m?['granted'] == true;
      notifyListeners();
    } catch (_) {}
  }

  /// Refresh all permission-related state in one native round-trip.
  Future<void> refreshPermissions() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('permissionStatus');
      notificationGranted = m?['notifications'] == true;
      batteryExempt = m?['battery'] == true;
      shizukuAvailable = m?['shizukuAvailable'] == true;
      shizukuGranted = m?['shizukuGranted'] == true;
      notifyListeners();
    } catch (_) {}
  }

  /// Ask the user to authorize OpenBridge inside the Shizuku app.
  Future<bool> requestShizukuPermission() async {
    try {
      final ok = await _channel.invokeMethod<bool>('requestShizukuPermission');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Ask for notification permission (Android 13+ shows the system dialog).
  Future<bool> requestNotificationPermission() async {
    try {
      final ok = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Request battery optimization bypass (opens system settings).
  Future<bool> requestBatteryBypass() async {
    try {
      final ok = await _channel.invokeMethod<bool>('requestBatteryBypass');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Execute a screen control action (tap, swipe, key, text) via shell.
  Future<bool> executeControl(String action, double x, double y, {double? x2, double? y2, int? keyCode, String? text}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('executeControl', {
        'action': action,
        'x': x,
        'y': y,
        if (x2 != null) 'x2': x2,
        if (y2 != null) 'y2': y2,
        if (keyCode != null) 'keyCode': keyCode,
        if (text != null) 'text': text,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> start() async {
    try {
      final ok = await _channel.invokeMethod<bool>('startCapture', {
        'maxSide': maxSide,
        'quality': quality,
      });
      capturing = ok == true;
      lastError = capturing ? null : 'native rejected startCapture';
      notifyListeners();
      return capturing;
    } catch (e) {
      capturing = false;
      lastError = e is PlatformException
          ? '${e.code}: ${e.message ?? 'no detail'}'
          : '$e';
      notifyListeners();
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