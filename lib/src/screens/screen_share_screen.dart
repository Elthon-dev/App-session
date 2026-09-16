import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../relay.dart';
import '../screen_capture.dart';
import '../theme.dart';

class ScreenShareScreen extends StatefulWidget {
  const ScreenShareScreen({super.key, required this.relay, required this.capture});

  final RelayClient relay;
  final ScreenCaptureService capture;

  @override
  State<ScreenShareScreen> createState() => _ScreenShareScreenState();
}

class _ScreenShareScreenState extends State<ScreenShareScreen> {
  bool _assist = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.relay.addListener(_onChanged);
    widget.capture.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.relay.removeListener(_onChanged);
    widget.capture.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final ok = await widget.capture.start();
    if (!mounted) return;
    if (!ok) {
      final detail = widget.capture.lastError ?? 'unknown reason';
      widget.relay.sendChat('⚠️ Screen share failed to start: $detail');
      setState(() {
        _starting = false;
        _error = 'Screen capture failed: $detail. Please accept the system prompt and try again.';
      });
      return;
    }
    widget.relay.sendChat('✅ Screen share started (quality ${widget.capture.quality})');
    widget.capture.poll(onFrame: widget.relay.sendFrame, intervalMs: 260);
    setState(() => _starting = false);
  }

  Future<void> _stop() async {
    await widget.capture.stop();
    setState(() => _error = null);
  }

  Future<void> _handleTap(TapUpDetails details, Size previewSize) async {
    if (!widget.capture.capturing || !_assist) return;
    widget.relay.sendGesture(
      gestureType: 'tap',
      x: (details.localPosition.dx / previewSize.width).clamp(0.0, 1.0),
      y: (details.localPosition.dy / previewSize.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relay = widget.relay;
    final capture = widget.capture;
    final capturing = capture.capturing;

    return Column(
      children: [
        _ControlStatusBanner(
          capture: capture,
          onOpenPermissions: () => _openPermissions(context),
        ),
        Expanded(
          child: capturing
              ? _Preview(
                  capture: capture,
                  overlay: relay.overlay,
                  assist: _assist,
                  onTap: (details, size) => _handleTap(details, size),
                )
              : _Idle(
                  starting: _starting,
                  error: _error,
                  onStart: _start,
                ),
        ),
        _Controls(
          captuturing: capturing,
          assist: _assist,
          quality: capture.quality,
          onAssist: (v) => setState(() => _assist = v),
          onQuality: (q) => setState(() => capture.quality = q),
          onStop: _stop,
        ),
      ],
    );
  }

  Future<void> _openPermissions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Nord.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PermissionsSheet(capture: widget.capture),
    );
    if (mounted) setState(() {});
  }
}

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet({required this.capture});

  final ScreenCaptureService capture;

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.capture.refreshPermissions();
  }

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    await widget.capture.refreshPermissions();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.capture;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Permissions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Nord.text1),
              ),
            ),
            const SizedBox(height: 14),
            _PermissionRow(
              icon: Icons.notifications_none,
              title: 'Notifications',
              subtitle: 'Lets the screen-share status show in the notification shade.',
              granted: c.notificationGranted,
              actionLabel: 'Allow',
              onAction: _busy ? null : () => _run(c.requestNotificationPermission),
            ),
            _PermissionRow(
              icon: Icons.battery_saver,
              title: 'Battery',
              subtitle: 'Exempts OpenBridge so Android won’t kill it while sharing.',
              granted: c.batteryExempt,
              actionLabel: 'Exempt',
              onAction: _busy ? null : () => _run(() async => c.requestBatteryBypass()),
            ),
            _PermissionRow(
              icon: Icons.shield_outlined,
              title: 'Shizuku',
              subtitle: c.shizukuAvailable
                  ? 'Enables remote tap / swipe control with shell access.'
                  : 'Shizuku isn’t running — start it from the notification shade.',
              granted: c.shizukuGranted,
              actionLabel: 'Authorize',
              onAction: _busy ? null : () => _run(c.requestShizukuPermission),
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nord.text1),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10.5, color: Nord.muted, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: granted ? null : onAction,
            style: FilledButton.styleFrom(
              backgroundColor: granted ? Nord.success : Nord.accent,
              foregroundColor: granted ? Nord.bg.withValues(alpha: 0.9) : Nord.bg,
              disabledBackgroundColor: Nord.success.withValues(alpha: 0.2),
              disabledForegroundColor: Nord.bg.withValues(alpha: 0.6),
              minimumSize: const Size(96, 36),
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

class _ControlStatusBanner extends StatelessWidget {
  const _ControlStatusBanner({required this.capture, required this.onOpenPermissions});

  final ScreenCaptureService capture;
  final VoidCallback onOpenPermissions;

  @override
  Widget build(BuildContext context) {
    final ready = capture.controlReady;
    final available = capture.shizukuAvailable;
    final bound = capture.shizukuBound;
    final stuck = capture.shizukuStuck;
    final attempts = capture.shizukuAttempts;
    final version = capture.shizukuVersion;
    final Color color;
    final String text;
    IconData icon;
    if (ready && bound) {
      color = Nord.success;
      icon = Icons.touch_app;
      text = 'Control ready — Shizuku active';
    } else if (stuck) {
      color = Nord.error;
      icon = Icons.error_outline;
      text = 'Control engine stuck (v$version, attempt $attempts)';
    } else if (ready && !bound) {
      color = Nord.warning;
      icon = Icons.sync_problem;
      text = 'Control engine warming up (attempt $attempts)…';
    } else if (available) {
      color = Nord.warning;
      icon = Icons.shield_outlined;
      text = 'Control needs permission';
    } else {
      color = Nord.warning;
      icon = Icons.warning_amber_rounded;
      text = 'Shizuku not running';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: Nord.surface,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
          ),
          const Spacer(),
          if (!ready)
            InkWell(
              onTap: () => _authorize(context),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'Fix',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Nord.accent),
                ),
              ),
            ),
          if (!ready) const SizedBox(width: 4),
          InkWell(
            onTap: onOpenPermissions,
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

  Future<void> _authorize(BuildContext context) async {
    final capture = this.capture;
    if (capture.shizukuGranted) return;
    if (!capture.shizukuAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start Shizuku first (pull down the notification shade → Shizuku → Start).'),
          backgroundColor: Nord.surface,
        ),
      );
      return;
    }
    await capture.requestShizukuPermission();
    if (context.mounted && capture.shizukuGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shizuku ready — control active.'), backgroundColor: Nord.surface),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open the Shizuku app and toggle OpenBridge to "ON" in Authorized apps.'),
          backgroundColor: Nord.surface,
        ),
      );
    }
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.capture,
    required this.overlay,
    required this.assist,
    required this.onTap,
  });

  final ScreenCaptureService capture;
  final OverlayData? overlay;
  final bool assist;
  final void Function(TapUpDetails, Size) onTap;

  @override
  Widget build(BuildContext context) {
    final frame = capture.lastFrame;
    return GestureDetector(
      onTapUp: (d) => onTap(d, context.size ?? Size.zero),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frame != null && frame.isNotEmpty)
            Image.memory(
              base64Decode(frame.split(',').last),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            )
          else
            Container(
              color: Nord.bg,
              alignment: Alignment.center,
              child: const Text(
                'Waiting for first frame…',
                style: TextStyle(color: Nord.muted, fontSize: 12.5),
              ),
            ),
          if (assist && frame != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _OverlayPainter(overlay)),
              ),
            ),
          if (!assist)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: IgnorePointer(
                child: Center(
                  child: Chip(
                    backgroundColor: Nord.surface,
                    side: BorderSide(color: Nord.border),
                    labelPadding: EdgeInsets.symmetric(horizontal: 8),
                    label: Text(
                      'Assist off — tap not sent',
                      style: TextStyle(fontSize: 10.5, color: Nord.muted),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.starting, required this.error, required this.onStart});

  final bool starting;
  final String? error;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Nord.border, width: 1.4, style: BorderStyle.solid),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.screen_share_outlined, size: 30, color: Nord.muted),
            ),
            const SizedBox(height: 18),
            const Text(
              'Share your screen with Opencode',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Nord.text1),
            ),
            const SizedBox(height: 6),
            const Text(
              'Android will ask for permission — accept it and the live preview will show here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Nord.muted, height: 1.5),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Nord.error),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: starting ? null : onStart,
              icon: const Icon(Icons.cast, size: 18),
              label: const Text('Share screen'),
              style: FilledButton.styleFrom(
                backgroundColor: Nord.accent,
                foregroundColor: Nord.bg,
                minimumSize: const Size(190, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.captuturing,
    required this.assist,
    required this.quality,
    required this.onAssist,
    required this.onQuality,
    required this.onStop,
  });

  final bool captuturing;
  final bool assist;
  final int quality;
  final ValueChanged<bool> onAssist;
  final ValueChanged<int> onQuality;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      color: Nord.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Remote control assist',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Nord.text2),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Taps on the preview go to Opencode',
                  style: TextStyle(fontSize: 10, color: Nord.muted),
                ),
                const SizedBox(height: 8),
                Switch(
                  value: assist,
                  onChanged: captuturing ? onAssist : null,
                  activeThumbColor: Nord.accent,
                  activeTrackColor: Nord.accent.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dropDown('Quality', quality, [40, 60, 80], (v) => onQuality(v)),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: captuturing ? onStop : null,
                style: FilledButton.styleFrom(
                  backgroundColor: captuturing ? Nord.error : Nord.surface,
                  foregroundColor: Nord.bg,
                  minimumSize: const Size(110, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                child: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget dropDown(String label, int value, List<int> values, ValueChanged<int> onChanged) {
    return DropdownButton<int>(
      value: value,
      dropdownColor: Nord.surface,
      style: const TextStyle(fontSize: 12, color: Nord.text1),
      underline: SizedBox(height: 1, child: Container(color: Nord.border)),
      borderRadius: BorderRadius.circular(10),
      items: [
        DropdownMenuItem(value: 40, child: Text('$label · Low')),
        DropdownMenuItem(value: 60, child: Text('$label · Med')),
        DropdownMenuItem(value: 80, child: Text('$label · High')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.overlay);

  final OverlayData? overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final o = overlay;
    if (o == null) return;

    final x = o.x * size.width;
    final y = o.y * size.height;

    if (o.shape == 'frame') {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Nord.info.withValues(alpha: 0.85)
        ..strokeCap = StrokeCap.round;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
        const Radius.circular(18),
      );
      canvas.drawRRect(rrect, paint);
      if (o.label != null) _drawLabel(canvas, offset: const Offset(16, 12), label: o.label!);
      return;
    }

    if (o.shape == 'swipe' && o.dx != null && o.dy != null) {
      final len = 56.0;
      final angle = (math.atan2(o.dy!, o.dx!));
      final start = Offset(x, y);
      final end = start + Offset(math.cos(angle) * len, math.sin(angle) * len);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Nord.info.withValues(alpha: 0.9);
      canvas.drawLine(start, end, paint);
      final tip = end - Offset(math.cos(angle) * 10, math.sin(angle) * 10);
      final perp = Offset(-math.sin(angle), math.cos(angle)) * 4.5;
      final arrow = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(tip.dx + perp.dx, tip.dy + perp.dy)
        ..lineTo(tip.dx - perp.dx, tip.dy - perp.dy)
        ..close();
      canvas.drawPath(arrow, Paint()..color = Nord.info.withValues(alpha: 0.9));
      if (o.label != null) _drawLabel(canvas, offset: Offset(x, y - 26), label: o.label!);
      return;
    }

    // tap
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Nord.accent.withValues(alpha: 0.95);
    canvas.drawCircle(Offset(x, y), 26, paint);
    canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = Nord.accent);
    if (o.label != null) _drawLabel(canvas, offset: Offset(x, y + 34), label: o.label!);
  }

  void _drawLabel(Canvas canvas, {required Offset offset, required String label}) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Nord.info,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          backgroundColor: Nord.bg,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromLTWH(
      offset.dx.clamp(0.0, 1 << 30) - tp.width / 2,
      offset.dy,
      tp.width + 12,
      tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = Nord.bg.withValues(alpha: 0.9),
    );
    tp.paint(canvas, Offset(rect.left + 6, rect.top + 3));
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => oldDelegate.overlay != overlay;
}