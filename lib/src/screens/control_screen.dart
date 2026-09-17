import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../relay.dart';
import '../screen_capture.dart';
import '../theme.dart';

/// Full on-device control: live-screen direct injection plus a command deck
/// for navigation, keys, typing, the app launcher, audio and brightness.
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, required this.relay, required this.capture});

  final RelayClient relay;
  final ScreenCaptureService capture;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

enum GestureMode { tap, doubleTap, longPress, swipe }

class _ControlScreenState extends State<ControlScreen> with WidgetsBindingObserver {
  GestureMode _mode = GestureMode.tap;
  bool _inject = true;
  bool _busy = false;

  final TextEditingController _typeCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _appSearch = TextEditingController();

  double _screenAspect = 9 / 20;
  int _brightness = 128;
  bool _brightnessKnown = false;

  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.capture.addListener(_changed);
    widget.capture.refreshPermissions();
    widget.capture.refreshAudio();
    widget.capture.loadApps().then((_) {
      if (mounted) setState(() {});
    });
    _loadHardware();
  }

  Future<void> _loadHardware() async {
    final info = await widget.capture.screenInfo();
    final w = (info['width'] as num?)?.toDouble() ?? 0;
    final h = (info['height'] as num?)?.toDouble() ?? 0;
    final b = await widget.capture.getBrightness();
    if (!mounted) return;
    setState(() {
      if (w > 0 && h > 0) _screenAspect = w / h;
      if (b >= 0) {
        _brightness = b;
        _brightnessKnown = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.capture.removeListener(_changed);
    _typeCtrl.dispose();
    _urlCtrl.dispose();
    _appSearch.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.capture.refreshPermissions();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _send(Future<ControlResult> Function() action) async {
    final res = await action();
    if (!mounted) return;
    if (!res.ok) {
      final note = res.detail ?? (res.mode == 'none' ? 'No control backend available.' : 'Action failed (${res.mode ?? 'unknown'}).');
      _snack(note);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Nord.surface, duration: const Duration(seconds: 2)),
    );
  }

  bool get _ready => widget.capture.controlReady;

  // ------------------------------------------------------------------
  // Live preview gesture injection
  // ------------------------------------------------------------------

  void _onTapUp(TapUpDetails d, Size size) {
    if (!_inject || !_ready) return;
    _send(() => widget.capture.tapAt(d.localPosition.dx / size.width, d.localPosition.dy / size.height));
  }

  void _onDoubleTapDown(TapDownDetails d, Size size) {
    if (!_inject || !_ready) return;
    _send(() => widget.capture.doubleTapAt(d.localPosition.dx / size.width, d.localPosition.dy / size.height));
  }

  void _onLongPressStart(LongPressStartDetails d, Size size) {
    if (!_inject || !_ready) return;
    _send(() => widget.capture.longPressAt(d.localPosition.dx / size.width, d.localPosition.dy / size.height));
  }

  void _onPanStart(DragStartDetails d) => _swipeStart = d.localPosition;

  void _onPanEnd(DragEndDetails d, Size size) {
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null || !_inject || !_ready) return;
    final end = d.localPosition;
    _send(() => widget.capture.swipeAt(
          start.dx / size.width,
          start.dy / size.height,
          end.dx / size.width,
          end.dy / size.height,
          duration: 240,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final capture = widget.capture;
    return Column(
      children: [
        _ControlBanner(capture: capture, onPermissions: _openPermissions),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              _previewCard(capture),
              const SizedBox(height: 14),
              _NavigationDeck(capture: capture, onSend: _send),
              const SizedBox(height: 14),
              _KeyDeck(capture: capture, onSend: _send),
              const SizedBox(height: 14),
              _typingCard(capture),
              const SizedBox(height: 14),
              _appsCard(capture),
              const SizedBox(height: 14),
              _audioCard(capture),
              const SizedBox(height: 14),
              _brightnessCard(capture),
              const SizedBox(height: 14),
              _urlCard(capture),
              const SizedBox(height: 14),
              _CrashGuardCard(capture: capture),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------

  Widget _previewCard(ScreenCaptureService capture) {
    return _Card(
      title: 'Direct control',
      icon: Icons.touch_app_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Inject', style: TextStyle(fontSize: 11, color: Nord.muted)),
          Switch(
            value: _inject,
            onChanged: (v) => setState(() => _inject = v),
            activeThumbColor: Nord.accent,
            activeTrackColor: Nord.accent.withValues(alpha: 0.35),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: GestureMode.values.map((m) {
              final selected = _mode == m;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(_modeLabel(m), style: TextStyle(fontSize: 11, color: selected ? Nord.bg : Nord.text2)),
                  selected: selected,
                  onSelected: (_) => setState(() => _mode = m),
                  backgroundColor: Nord.bg,
                  selectedColor: Nord.accent,
                  side: const BorderSide(color: Nord.border, width: 0.6),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          if (capture.capturing)
            _LiveSurface(
              capture: capture,
              aspect: _screenAspect,
              mode: _mode,
              onTapUp: _onTapUp,
              onDoubleTapDown: _onDoubleTapDown,
              onLongPressStart: _onLongPressStart,
              onPanStart: _onPanStart,
              onPanEnd: _onPanEnd,
            )
          else
            _PreviewPlaceholder(
              busy: _busy,
              onStart: _startCapture,
            ),
          const SizedBox(height: 8),
          Text(
            _ready
                ? 'Tap / drag the preview to control the phone directly via ${capture.backendLabel}.'
                : 'Enable a control backend (Accessibility or Shizuku) to inject input.',
            style: const TextStyle(fontSize: 10.5, color: Nord.muted, height: 1.35),
          ),
        ],
      ),
    );
  }

  Future<void> _startCapture() async {
    setState(() => _busy = true);
    final ok = await widget.capture.start();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _snack(widget.capture.lastError ?? 'Screen capture failed.');
    } else {
      widget.capture.poll(onFrame: (_) {}, intervalMs: 320);
    }
  }

  String _modeLabel(GestureMode m) {
    switch (m) {
      case GestureMode.tap:
        return 'Tap';
      case GestureMode.doubleTap:
        return 'Double';
      case GestureMode.longPress:
        return 'Long-press';
      case GestureMode.swipe:
        return 'Swipe';
    }
  }

  Widget _typingCard(ScreenCaptureService capture) {
    return _Card(
      title: 'Type text',
      icon: Icons.keyboard_outlined,
      child: Column(
        children: [
          TextField(
            controller: _typeCtrl,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(fontSize: 13.5, color: Nord.text1),
            decoration: const InputDecoration(hintText: 'Text to type into the focused field…'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DeckButton(
                  label: 'Type',
                  icon: Icons.keyboard_return,
                  accent: true,
                  onTap: () {
                    final t = _typeCtrl.text;
                    if (t.isEmpty) return;
                    _send(() => capture.typeText(t));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DeckButton(
                  label: 'Enter',
                  icon: Icons.subdirectory_arrow_left,
                  onTap: () => _send(() => capture.control('key', params: {'keyCode': 66})),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DeckButton(
                  label: 'Clear',
                  icon: Icons.backspace_outlined,
                  onTap: () => _send(() => capture.control('clearText')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appsCard(ScreenCaptureService capture) {
    final query = _appSearch.text.trim().toLowerCase();
    final apps = capture.apps.where((a) {
      if (query.isEmpty) return true;
      return a.label.toLowerCase().contains(query) || a.package.toLowerCase().contains(query);
    }).toList();

    return _Card(
      title: 'App launcher',
      icon: Icons.apps,
      trailing: IconButton(
        onPressed: () => capture.loadApps(force: true).then((_) {
          if (mounted) setState(() {});
        }),
        icon: const Icon(Icons.sync, size: 17, color: Nord.muted),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        children: [
          TextField(
            controller: _appSearch,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13, color: Nord.text1),
            decoration: InputDecoration(
              hintText: capture.appsLoaded ? 'Search ${capture.apps.length} apps…' : 'Loading apps…',
              prefixIcon: const Icon(Icons.search, size: 17, color: Nord.muted),
            ),
          ),
          const SizedBox(height: 10),
          if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No matching apps.', style: TextStyle(fontSize: 12, color: Nord.muted)),
            )
          else
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: apps.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final app = apps[i];
                  return InkWell(
                    onTap: () => _send(() => capture.launchApp(app.package)),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 66,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      decoration: BoxDecoration(
                        color: Nord.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Nord.border, width: 0.6),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Nord.primary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              app.initial,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Nord.info),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Expanded(
                            child: Text(
                              app.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, color: Nord.text2, height: 1.1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _audioCard(ScreenCaptureService capture) {
    final audio = capture.audio;
    const streams = [
      ('music', 'Media', Icons.music_note),
      ('ring', 'Ring', Icons.phone_in_talk_outlined),
      ('notification', 'Notification', Icons.notifications_none),
      ('alarm', 'Alarm', Icons.alarm),
      ('system', 'System', Icons.tune),
    ];
    return _Card(
      title: 'Audio',
      icon: Icons.volume_up_outlined,
      trailing: IconButton(
        onPressed: () => capture.refreshAudio(),
        icon: const Icon(Icons.refresh, size: 17, color: Nord.muted),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        children: [
          for (final (key, label, icon) in streams)
            _AudioRow(
              label: label,
              icon: icon,
              stream: audio?[key],
              onChanged: (level) => capture.setAudio(key, level: level).then((_) {
                if (mounted) setState(() {});
              }),
              onMute: () => capture.setAudio(key, op: (audio?[key]?.muted ?? false) ? 'unmute' : 'mute').then((_) {
                if (mounted) setState(() {});
              }),
            ),
        ],
      ),
    );
  }

  Widget _brightnessCard(ScreenCaptureService capture) {
    return _Card(
      title: 'Brightness',
      icon: Icons.brightness_6_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.brightness_low, size: 16, color: Nord.muted),
              Expanded(
                child: Slider(
                  value: _brightness.toDouble().clamp(0, 255).toDouble(),
                  min: 0,
                  max: 255,
                  activeColor: Nord.info,
                  inactiveColor: Nord.border,
                  onChanged: (v) => setState(() => _brightness = v.round()),
                  onChangeEnd: (v) async {
                    final res = await capture.setBrightness(v.round());
                    if (!mounted) return;
                    setState(() => _brightness = v.round());
                    if (res.ok && res.mode == 'window') {
                      _snack('Only app brightness changed — grant WRITE_SETTINGS or Shizuku for system brightness.');
                    }
                  },
                ),
              ),
              const Icon(Icons.brightness_high, size: 16, color: Nord.text2),
            ],
          ),
          Row(
            children: [
              Text(
                _brightnessKnown ? 'System: $_brightness / 255' : 'System brightness unknown',
                style: const TextStyle(fontSize: 10.5, color: Nord.muted),
              ),
              const Spacer(),
              if (!capture.writeSettings && !capture.shizukuBound)
                TextButton(
                  onPressed: () => capture.openWriteSettings(),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Grant', style: TextStyle(fontSize: 11, color: Nord.accent)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _urlCard(ScreenCaptureService capture) {
    return _Card(
      title: 'Open link',
      icon: Icons.link,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontSize: 13, color: Nord.text1),
              decoration: const InputDecoration(hintText: 'https://…'),
            ),
          ),
          const SizedBox(width: 8),
          _DeckButton(
            label: 'Open',
            icon: Icons.open_in_new,
            accent: true,
            onTap: () {
              final u = _urlCtrl.text.trim();
              if (u.isEmpty) return;
              final url = u.startsWith('http') ? u : 'https://$u';
              _send(() => capture.openUrl(url));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openPermissions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Nord.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PermissionsSheet(),
    );
    if (mounted) setState(() {});
  }
}

// ======================================================================
// Widgets
// ======================================================================

class _LiveSurface extends StatelessWidget {
  const _LiveSurface({
    required this.capture,
    required this.aspect,
    required this.mode,
    required this.onTapUp,
    required this.onDoubleTapDown,
    required this.onLongPressStart,
    required this.onPanStart,
    required this.onPanEnd,
  });

  final ScreenCaptureService capture;
  final double aspect;
  final GestureMode mode;
  final void Function(TapUpDetails, Size) onTapUp;
  final void Function(TapDownDetails, Size) onDoubleTapDown;
  final void Function(LongPressStartDetails, Size) onLongPressStart;
  final void Function(DragStartDetails) onPanStart;
  final void Function(DragEndDetails, Size) onPanEnd;

  @override
  Widget build(BuildContext context) {
    final frame = capture.lastFrame;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect <= 0 ? 9 / 20 : aspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              onTapUp: mode == GestureMode.tap ? (d) => onTapUp(d, size) : null,
              onDoubleTapDown: mode == GestureMode.doubleTap ? (d) => onDoubleTapDown(d, size) : null,
              onLongPressStart: mode == GestureMode.longPress ? (d) => onLongPressStart(d, size) : null,
              onPanStart: mode == GestureMode.swipe ? onPanStart : null,
              onPanEnd: mode == GestureMode.swipe ? (d) => onPanEnd(d, size) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Nord.bg,
                  child: frame != null && frame.isNotEmpty
                      ? Image.memory(
                          base64Decode(frame.split(',').last),
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        )
                      : const Center(
                          child: Text('Waiting for frame…', style: TextStyle(fontSize: 11, color: Nord.muted)),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.busy, required this.onStart});

  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Nord.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Nord.border, width: 0.6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.screen_share_outlined, size: 26, color: Nord.muted),
          const SizedBox(height: 8),
          const Text(
            'Start mirroring to tap the screen directly',
            style: TextStyle(fontSize: 11.5, color: Nord.muted),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy ? null : onStart,
            icon: const Icon(Icons.play_arrow, size: 17),
            label: const Text('Start mirror'),
            style: FilledButton.styleFrom(
              backgroundColor: Nord.accent,
              foregroundColor: Nord.bg,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationDeck extends StatelessWidget {
  const _NavigationDeck({required this.capture, required this.onSend});

  final ScreenCaptureService capture;
  final Future<void> Function(Future<ControlResult> Function()) onSend;

  static const _items = [
    ('home', 'Home', Icons.home_outlined),
    ('back', 'Back', Icons.arrow_back),
    ('recents', 'Recents', Icons.crop_square),
    ('notifications', 'Shade', Icons.notifications_outlined),
    ('quickSettings', 'Settings', Icons.settings_outlined),
    ('powerDialog', 'Power', Icons.power_settings_new),
    ('lock', 'Lock', Icons.lock_outline),
    ('split', 'Split', Icons.vertical_split_outlined),
    ('wake', 'Wake', Icons.lightbulb_outline),
    ('sleep', 'Sleep', Icons.bedtime_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Navigation',
      icon: Icons.explore_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (action, label, icon) in _items)
            _DeckButton(label: label, icon: icon, onTap: () => onSend(() => capture.global(action))),
        ],
      ),
    );
  }
}

class _KeyDeck extends StatelessWidget {
  const _KeyDeck({required this.capture, required this.onSend});

  final ScreenCaptureService capture;
  final Future<void> Function(Future<ControlResult> Function()) onSend;

  static const _keys = [
    (66, 'Enter', Icons.keyboard_return),
    (67, 'Bksp', Icons.backspace_outlined),
    (61, 'Tab', Icons.keyboard_tab),
    (62, 'Space', Icons.space_bar),
    (111, 'Esc', Icons.close),
    (82, 'Menu', Icons.menu),
    (84, 'Search', Icons.search),
    (24, 'Vol+', Icons.volume_up),
    (25, 'Vol-', Icons.volume_down),
    (85, 'Play', Icons.play_circle_outline),
    (27, 'Camera', Icons.camera_alt_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Keys',
      icon: Icons.keyboard_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (code, label, icon) in _keys)
            _DeckButton(
              label: label,
              icon: icon,
              onTap: () => onSend(() => capture.control('key', params: {'keyCode': code})),
            ),
        ],
      ),
    );
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow({
    required this.label,
    required this.icon,
    required this.stream,
    required this.onChanged,
    required this.onMute,
  });

  final String label;
  final IconData icon;
  final AudioStream? stream;
  final ValueChanged<int> onChanged;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final s = stream;
    final max = (s?.max ?? 0).clamp(1, 1000);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Nord.muted),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: Nord.text2)),
          ),
          Expanded(
            child: Slider(
              value: (s?.level ?? 0).toDouble().clamp(0, max.toDouble()).toDouble(),
              min: 0,
              max: max.toDouble(),
              activeColor: s?.muted == true ? Nord.muted : Nord.accent,
              inactiveColor: Nord.border,
              onChanged: s == null ? null : (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${s?.level ?? 0}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10.5, color: Nord.muted),
            ),
          ),
          IconButton(
            onPressed: s == null ? null : onMute,
            icon: Icon(s?.muted == true ? Icons.volume_off : Icons.volume_up, size: 16, color: Nord.muted),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent ? Nord.primary.withValues(alpha: 0.22) : Nord.bg,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: accent ? Nord.info.withValues(alpha: 0.6) : Nord.border,
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: accent ? Nord.info : Nord.text2),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: accent ? Nord.text1 : Nord.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.child, this.trailing});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Nord.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nord.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Nord.info),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nord.text1),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ControlBanner extends StatelessWidget {
  const _ControlBanner({required this.capture, required this.onPermissions});

  final ScreenCaptureService capture;
  final Future<void> Function() onPermissions;

  @override
  Widget build(BuildContext context) {
    final ready = capture.controlReady;
    final Color color;
    final String text;
    final IconData icon;
    if (capture.shizukuBound) {
      color = Nord.success;
      icon = Icons.verified_user_outlined;
      text = 'Control ready — Shizuku shell';
    } else if (capture.accessibilityEnabled) {
      color = Nord.success;
      icon = Icons.verified_user_outlined;
      text = 'Control ready — Accessibility';
    } else if (capture.shizukuStuck) {
      color = Nord.error;
      icon = Icons.error_outline;
      text = 'Control engine stuck (v${capture.shizukuVersion})';
    } else if (capture.shizukuReady) {
      color = Nord.warning;
      icon = Icons.sync_problem;
      text = 'Shizuku warming up…';
    } else {
      color = Nord.warning;
      icon = Icons.warning_amber_rounded;
      text = 'Enable Accessibility or Shizuku for control';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: Nord.surface,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          if (!ready)
            InkWell(
              onTap: onPermissions,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('Fix', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Nord.accent)),
              ),
            ),
          InkWell(
            onTap: onPermissions,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(Icons.tune, size: 16, color: Nord.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet();

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  final ScreenCaptureService _capture = ScreenCaptureService();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _capture.refreshPermissions();
  }

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    await _capture.refreshPermissions();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _capture;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Control permissions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Nord.text1),
              ),
            ),
            const SizedBox(height: 14),
            _PermissionRow(
              icon: Icons.accessibility_new,
              title: 'Accessibility control',
              subtitle: c.accessibilityEnabled
                  ? 'Active — taps, swipes, long-press, navigation and typing work.'
                  : 'Recommended. Works without Shizuku on any device.',
              granted: c.accessibilityEnabled,
              actionLabel: 'Enable',
              onAction: _busy ? null : () => _run(c.openAccessibilitySettings),
            ),
            _PermissionRow(
              icon: Icons.shield_outlined,
              title: 'Shizuku',
              subtitle: c.shizukuAvailable
                  ? 'Shell backend for key events, brightness and app launch fallbacks.'
                  : 'Not running — start it from its notification, then authorize.',
              granted: c.shizukuGranted,
              actionLabel: 'Authorize',
              onAction: _busy ? null : () => _run(c.requestShizukuPermission),
            ),
            _PermissionRow(
              icon: Icons.brightness_6_outlined,
              title: 'WRITE_SETTINGS',
              subtitle: c.writeSettings
                  ? 'System brightness can be changed directly.'
                  : 'Needed to change system brightness without Shizuku.',
              granted: c.writeSettings,
              actionLabel: 'Grant',
              onAction: _busy ? null : () => _run(c.openWriteSettings),
            ),
            _PermissionRow(
              icon: Icons.notifications_none,
              title: 'Notifications',
              subtitle: 'Shows the capture status in the notification shade.',
              granted: c.notificationGranted,
              actionLabel: 'Allow',
              onAction: _busy ? null : () => _run(c.requestNotificationPermission),
            ),
            _PermissionRow(
              icon: Icons.battery_saver,
              title: 'Battery',
              subtitle: 'Prevents Android from killing OpenBridge while controlling.',
              granted: c.batteryExempt,
              actionLabel: 'Exempt',
              onAction: _busy ? null : () => _run(() async => c.requestBatteryBypass()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = granted ? Nord.success : Nord.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Nord.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Nord.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nord.text1)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Nord.muted, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: granted ? null : onAction,
            style: FilledButton.styleFrom(
              backgroundColor: granted ? Nord.success : Nord.accent,
              foregroundColor: Nord.bg,
              disabledBackgroundColor: Nord.success.withValues(alpha: 0.2),
              disabledForegroundColor: Nord.bg.withValues(alpha: 0.6),
              minimumSize: const Size(92, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            child: Text(granted ? 'Granted' : actionLabel),
          ),
        ],
      ),
    );
  }
}

/// CrashGuard: watches whole-device memory and — when it can — frees memory
/// *before* lmkd/ColorOS kill Termux, plus one-tap cache trim + tweaks.
class _CrashGuardCard extends StatefulWidget {
  const _CrashGuardCard({required this.capture});

  final ScreenCaptureService capture;

  @override
  State<_CrashGuardCard> createState() => _CrashGuardCardState();
}

class _CrashGuardCardState extends State<_CrashGuardCard> {
  Timer? _guardTimer;
  bool _auto = false;
  bool _busy = false;
  String? _lastResult;

  ScreenCaptureService get c => widget.capture;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    c.refreshMem();
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    _guardTimer?.cancel();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _setAuto(bool v) {
    setState(() => _auto = v);
    if (v) {
      c.refreshMem();
      _guardTimer?.cancel();
      _guardTimer = Timer.periodic(const Duration(seconds: 10), (_) => _autoTick());
    } else {
      _guardTimer?.cancel();
      _guardTimer = null;
    }
  }

  Future<void> _autoTick() async {
    final m = await c.refreshMem();
    if (!mounted || m == null) return;
    if (!m.tight) {
      setState(() {});
      return;
    }
    final res = await c.trimCaches();
    if (!mounted) return;
    setState(() {
      _lastResult = res.ok
          ? 'Automatic trim: freed caches (${m.availableMB}MB avail)'
          : 'Tight (${m.availableMB}MB) → trim failed: ${res.detail ?? res.mode}';
    });
    if (!res.ok && res.mode == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grant Shizuku so CrashGuard can free memory automatically.'),
          backgroundColor: Nord.surface,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _run(Future<ControlResult> Function() action, String done) async {
    setState(() => _busy = true);
    final res = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastResult = res.ok ? done : 'Failed: ${res.detail ?? res.mode ?? 'unknown'}';
    });
    if (!res.ok && res.mode == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Needs Shizuku (shell) authorization — open Shizuku and grant OpenBridge.'),
          backgroundColor: Nord.surface,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = c.mem;
    final swapUsed = m?.swapUsedMB ?? 0;
    final pressure = m == null || m.tight;
    final tone = m == null ? Nord.muted : (m.tight ? Nord.error : Nord.success);

    return _Card(
      title: 'CrashGuard',
      icon: Icons.health_and_safety_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Auto-guard', style: TextStyle(fontSize: 11, color: Nord.muted)),
          Switch(
            value: _auto,
            onChanged: _setAuto,
            activeThumbColor: Nord.accent,
            activeTrackColor: Nord.accent.withValues(alpha: 0.35),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m == null
                ? 'Reading system memory…'
                : 'RAM ${m.availableMB}/${m.totalMB} MB avail · swap $swapUsed/${m.swapTotalMB} MB · load ${m.load1.toStringAsFixed(1)}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tone),
          ),
          const SizedBox(height: 6),
          Text(
            'Termux is killed when the whole phone runs out of memory. ${_auto ? 'Watching now — auto-trims caches if RAM drops below 450MB.' : 'Auto-guard trims system caches before Android kills us; Low-RAM tweaks cap background processes to keep a free pool.'}',
            style: const TextStyle(fontSize: 10.5, color: Nord.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DeckButton(
                label: 'Trim caches',
                icon: Icons.cleaning_services_outlined,
                accent: true,
                onTap: _busy ? () {} : () => _run(() => c.trimCaches(), 'Cache trim done.'),
              ),
              _DeckButton(
                label: 'Low-RAM tweaks',
                icon: Icons.settings_suggest_outlined,
                onTap: _busy ? () {} : () => _run(() => c.applyMemoryTweaks(), 'max_cached_processes capped at 8.'),
              ),
              _DeckButton(
                label: 'Refresh',
                icon: Icons.refresh,
                onTap: _busy ? () {} : () {
                  c.refreshMem();
                  setState(() {});
                },
              ),
            ],
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _lastResult!,
              style: TextStyle(fontSize: 10.5, color: pressure ? Nord.warning : Nord.muted),
            ),
          ],
        ],
      ),
    );
  }
}
