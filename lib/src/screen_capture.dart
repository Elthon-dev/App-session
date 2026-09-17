import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a device-control action, including which backend executed it.
class ControlResult {
  const ControlResult({
    required this.ok,
    this.mode,
    this.exit,
    this.detail,
  });

  final bool ok;
  final String? mode;
  final int? exit;
  final String? detail;

  factory ControlResult.from(dynamic r) {
    if (r is Map) {
      return ControlResult(
        ok: r['ok'] == true,
        mode: r['mode'] as String?,
        exit: (r['exit'] as num?)?.toInt(),
        detail: r['detail'] as String?,
      );
    }
    return ControlResult(ok: r == true);
  }
}

/// An installed, launchable app on the device.
class InstalledApp {
  const InstalledApp({required this.package, required this.label, required this.launchable});

  final String package;
  final String label;
  final bool launchable;

  factory InstalledApp.fromJson(Map<Object?, Object?> j) => InstalledApp(
        package: j['package'] as String? ?? '',
        label: j['label'] as String? ?? '',
        launchable: j['launchable'] == true,
      );

  String get initial {
    final l = label.trim();
    return l.isEmpty ? '?' : String.fromCharCode(l.runes.first).toUpperCase();
  }
}

/// One audio stream's level snapshot.
class AudioStream {
  const AudioStream({required this.level, required this.max, required this.muted});

  final int level;
  final int max;
  final bool muted;

  factory AudioStream.fromJson(dynamic j) {
    if (j is Map) {
      return AudioStream(
        level: (j['level'] as num?)?.toInt() ?? 0,
        max: (j['max'] as num?)?.toInt() ?? 1,
        muted: j['muted'] == true,
      );
    }
    return const AudioStream(level: 0, max: 1, muted: false);
  }

  double get fraction => max <= 0 ? 0 : level / max;
}

class AudioState {
  const AudioState({required this.streams});

  final Map<String, AudioStream> streams;

  AudioStream? operator [](String name) => streams[name];

  factory AudioState.fromJson(Map<Object?, Object?> j) => AudioState(
        streams: {
          for (final key in const ['music', 'ring', 'alarm', 'notification', 'system'])
            if (j[key] != null) key: AudioStream.fromJson(j[key]),
        },
      );
}

/// Whole-device memory/swap snapshot for CrashGuard.
class SystemMem {
  const SystemMem({
    required this.totalMB,
    required this.availableMB,
    required this.swapTotalMB,
    required this.swapFreeMB,
    required this.load1,
    required this.uptimeS,
    required this.shizuku,
  });

  factory SystemMem.fromJson(Map<Object?, Object?> m) => SystemMem(
        totalMB: (m['totalMB'] as num?)?.toInt() ?? 0,
        availableMB: (m['availableMB'] as num?)?.toInt() ?? 0,
        swapTotalMB: (m['swapTotalMB'] as num?)?.toInt() ?? 0,
        swapFreeMB: (m['swapFreeMB'] as num?)?.toInt() ?? 0,
        load1: (m['load1'] as num?)?.toDouble() ?? 0,
        uptimeS: (m['uptimeS'] as num?)?.toInt() ?? 0,
        shizuku: m['shizuku'] == true,
      );

  final int totalMB;
  final int availableMB;
  final int swapTotalMB;
  final int swapFreeMB;
  final double load1;
  final int uptimeS;

  /// Shell (Shizuku) is available, so cache trims will actually work.
  final bool shizuku;

  int get swapUsedMB {
    final used = swapTotalMB - swapFreeMB;
    if (used < 0) return 0;
    if (used > swapTotalMB) return swapTotalMB;
    return used;
  }

  /// Low threshold: lmkd/ColorOS start killing processes around here.
  bool get tight => totalMB > 0 && availableMB > 0 && availableMB < 450;
}

/// Talks to the native Kotlin bridge over MethodChannel: screen capture,
/// device control, app list, audio and brightness.
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

  /// The shell user-service binder is connected (control will actually inject).
  bool shizukuBound = false;

  /// Shizuku server API version (0/-1 when unavailable).
  int shizukuVersion = -1;

  /// True when a bind attempt has not connected for >3s.
  bool shizukuStuck = false;

  /// Most recent bind failure reason (null when none).
  String? shizukuError;

  /// Number of bind attempts this app run.
  int shizukuAttempts = 0;

  /// True when control commands are queued because the shell engine is connecting.
  bool get warmingUp => (controlReady && !shizukuBound) || shizukuStuck;

  /// Notification permission granted (always true before Android 13).
  bool notificationGranted = true;

  /// App is exempt from battery optimizations.
  bool batteryExempt = false;

  /// Android WRITE_SETTINGS granted (needed for system brightness).
  bool writeSettings = false;

  /// OpenBridge AccessibilityService is enabled (no-Shizuku control backend).
  bool accessibilityEnabled = false;

  /// True when Shizuku shell control is authorized.
  bool get shizukuReady => shizukuAvailable && shizukuGranted;

  /// True when any control backend can inject input.
  bool get controlReady => accessibilityEnabled || (shizukuAvailable && shizukuGranted);

  /// Human label for the active control backend.
  String get backendLabel {
    if (shizukuBound) return 'Shizuku';
    if (accessibilityEnabled) return 'Accessibility';
    if (shizukuReady) return 'Shizuku (warming up)';
    if (shizukuAvailable) return 'Shizuku (permission needed)';
    return 'No backend';
  }

  /// Cached installed apps for the launcher.
  List<InstalledApp> apps = [];
  bool appsLoaded = false;

  /// Last known audio state.
  AudioState? audio;

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
      shizukuBound = m?['bound'] == true;
      shizukuVersion = (m?['version'] as int?) ?? -1;
      shizukuStuck = m?['stuck'] == true;
      shizukuError = m?['error'] as String?;
      shizukuAttempts = (m?['attempts'] as int?) ?? 0;
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
      shizukuBound = m?['shizukuBound'] == true;
      accessibilityEnabled = m?['accessibility'] == true;
      writeSettings = m?['writeSettings'] == true;
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

  /// Open Android Accessibility settings so the user can enable OpenBridge.
  Future<bool> openAccessibilitySettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openAccessibilitySettings');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Open the WRITE_SETTINGS grant screen (system brightness control).
  Future<bool> openWriteSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openWriteSettings');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Refresh just the AccessibilityService enabled state.
  Future<void> refreshAccessibility() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('accessibilityStatus');
      accessibilityEnabled = m?['enabled'] == true;
      notifyListeners();
    } catch (_) {}
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

  /// Execute a device-control action on the phone itself.
  ///
  /// [action] is one of: tap, doubleTap, longPress, swipe, scroll, key, text,
  /// clearText, launch, url, back, home, recents, notifications, quickSettings,
  /// powerDialog, lock, split, wake, sleep, volume.
  Future<ControlResult> control(String action, {Map<String, dynamic> params = const {}}) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('executeControl', {
        'action': action,
        ...params,
      });
      final res = ControlResult.from(r);
      lastControlResult = res;
      return res;
    } catch (e) {
      return ControlResult(ok: false, mode: 'error', detail: '$e');
    }
  }

  /// Backwards-compatible tap/swipe/key/text entry point.
  Future<bool> executeControl(
    String action,
    double x,
    double y, {
    double? x2,
    double? y2,
    int? keyCode,
    String? text,
  }) async {
    final res = await control(action, params: {
      'x': x,
      'y': y,
      if (x2 != null) 'x2': x2,
      if (y2 != null) 'y2': y2,
      if (keyCode != null) 'keyCode': keyCode,
      if (text != null) 'text': text,
    });
    return res.ok;
  }

  /// Convenience: inject a tap at normalised (0..1) coordinates.
  Future<ControlResult> tapAt(double x, double y) => control('tap', params: {'x': x, 'y': y});

  /// Convenience: inject a swipe between two normalised points.
  Future<ControlResult> swipeAt(double x, double y, double x2, double y2, {int duration = 300}) =>
      control('swipe', params: {'x': x, 'y': y, 'x2': x2, 'y2': y2, 'duration': duration});

  /// Long-press at normalised coordinates.
  Future<ControlResult> longPressAt(double x, double y, {int duration = 800}) =>
      control('longPress', params: {'x': x, 'y': y, 'duration': duration});

  /// Double-tap at normalised coordinates.
  Future<ControlResult> doubleTapAt(double x, double y) => control('doubleTap', params: {'x': x, 'y': y});

  /// Launch an installed app by package name.
  Future<ControlResult> launchApp(String package) => control('launch', params: {'package': package});

  /// Open a URL.
  Future<ControlResult> openUrl(String url) => control('url', params: {'url': url});

  /// Send a recognised global navigation action.
  Future<ControlResult> global(String action) => control(action);

  /// Type [text] into the currently focused field.
  Future<ControlResult> typeText(String text) => control('text', params: {'text': text});

  /// Load the installed-app list (cached after first call unless [force]).
  Future<List<InstalledApp>> loadApps({bool force = false}) async {
    if (appsLoaded && !force) return apps;
    try {
      final list = await _channel.invokeMethod<List<Object?>>('listApps');
      apps = (list ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(InstalledApp.fromJson)
          .where((a) => a.package.isNotEmpty)
          .toList();
      appsLoaded = true;
      notifyListeners();
    } catch (_) {}
    return apps;
  }

  /// Read current audio levels.
  Future<AudioState?> refreshAudio() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('getAudio');
      if (m == null) return audio;
      audio = AudioState.fromJson(m);
      notifyListeners();
      return audio;
    } catch (_) {
      return audio;
    }
  }

  /// Change an audio stream: op = set|up|down|mute|unmute.
  Future<AudioStream?> setAudio(String stream, {String op = 'set', int? level}) async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('setAudio', {
        'stream': stream,
        'op': op,
        if (level != null) 'level': level,
      });
      final s = AudioStream.fromJson(m);
      final next = Map<String, AudioStream>.from(audio?.streams ?? const {});
      next[stream] = s;
      audio = AudioState(streams: next);
      notifyListeners();
      return s;
    } catch (_) {
      return null;
    }
  }

  /// Current system brightness 0..255 (or -1 when unavailable).
  Future<int> getBrightness() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('getBrightness');
      return (m?['system'] as num?)?.toInt() ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Set brightness 0..255. Returns the backend that handled it.
  Future<ControlResult> setBrightness(int level) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('setBrightness', {'level': level});
      return ControlResult.from(r);
    } catch (e) {
      return ControlResult(ok: false, mode: 'error', detail: '$e');
    }
  }

  /// Device/screen information for the control header.
  Future<Map<String, dynamic>> screenInfo() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('screenInfo');
      if (m == null) return const {};
      return m.map((key, value) => MapEntry('$key', value));
    } catch (_) {
      return const {};
    }
  }

  /// Most recent control result.
  ControlResult? lastControlResult;

  /// Most recent whole-device memory snapshot (CrashGuard).
  SystemMem? mem;

  /// Refresh the /proc memory snapshot.
  Future<SystemMem?> refreshMem() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('getSystemMemory');
      if (m != null) {
        mem = SystemMem.fromJson(m);
        notifyListeners();
      }
    } catch (_) {}
    return mem;
  }

  /// Ask the shell (Shizuku) to free app caches to relieve memory pressure.
  Future<ControlResult> trimCaches() async {
    try {
      return ControlResult.from(await _channel.invokeMethod<dynamic>('trimCaches'));
    } catch (e) {
      return ControlResult(ok: false, mode: 'error', detail: '$e');
    }
  }

  /// Cap retained background processes so the OS keeps a larger free pool.
  Future<ControlResult> applyMemoryTweaks({int maxCached = 8}) async {
    try {
      return ControlResult.from(
        await _channel.invokeMethod<dynamic>('applyMemoryTweaks', {'maxCached': maxCached}),
      );
    } catch (e) {
      return ControlResult(ok: false, mode: 'error', detail: '$e');
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
      lastError = e is PlatformException ? '${e.code}: ${e.message ?? 'no detail'}' : '$e';
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
