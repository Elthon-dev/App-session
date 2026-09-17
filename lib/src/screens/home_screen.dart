import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../relay.dart';
import '../screen_capture.dart';
import '../sessions.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'connection_screen.dart';
import 'control_screen.dart';
import 'screen_share_screen.dart';
import 'session_panel.dart';
import 'swarm_screen.dart';

const kDefaultServer = 'ws://127.0.0.1:8765';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScreenCaptureService _capture = ScreenCaptureService();
  final SessionManager _sessions = SessionManager();
  RelayClient? _relay;
  bool _panelOpen = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _capture.bind();
    _capture.refreshPermissions();
    _sessions.addListener(_onSessionsChanged);
    _sessions.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBatteryBypass());
  }

  Future<void> _checkBatteryBypass() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('battery_bypass_done') == true) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Nord.surface,
        title: const Text('Keep alive during capture', style: TextStyle(color: Nord.text1)),
        content: const Text(
          'Android may kill OpenBridge while screen sharing is active. '
          'Allow unrestricted battery usage to prevent crashes?',
          style: TextStyle(color: Nord.muted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow', style: TextStyle(color: Nord.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await _capture.requestBatteryBypass();
    if (mounted) await prefs.setBool('battery_bypass_done', true);
  }

  @override
  void dispose() {
    _sessions.removeListener(_onSessionsChanged);
    _sessions.dispose();
    _relay?.removeListener(_onRelay);
    _relay?.dispose();
    _capture.dispose();
    super.dispose();
  }

  void _onRelay() => setState(() {});

  Future<void> _onControl(String action, double x, double y, Map<String, dynamic> raw) async {
    final x2 = (raw['x2'] as num?)?.toDouble();
    final y2 = (raw['y2'] as num?)?.toDouble();
    final keyCode = raw['keyCode'] as int?;
    final text = raw['text'] as String?;
    final ok = await _capture.executeControl(action, x, y, x2: x2, y2: y2, keyCode: keyCode, text: text);
    if (!ok) {
      final r = _capture.lastControlResult;
      final mode = r?.mode ?? 'unknown';
      final exit = r?.exit ?? -1;
      final String note;
      if (exit == -2) {
        note = 'Control $action queued (engine binding) — will run when connected.';
      } else if (exit == -1) {
        note = 'Control $action blocked: Shizuku permission needed.';
      } else {
        note = 'Control $action not applied (mode=$mode, exit=$exit).';
      }
      _relay?.sendStatus(note);
      if (_relay == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(note),
            backgroundColor: Nord.surface,
          ),
        );
      }
    }
  }

  void _onSessionsChanged() {
    final active = _sessions.active;
    if (active == null) return;
    if (!mounted) return;
    if (_relay != null && _relay!.url == active.serverUrl) {
      setState(() {});
      return;
    }
    _relay?.removeListener(_onRelay);
    _relay?.dispose();
    final relay = RelayClient(url: active.serverUrl);
    relay.onControl = _onControl;
    relay.addListener(_onRelay);
    setState(() => _relay = relay);
    relay.connect();
  }

  Future<void> _connectTo(String url) async {
    _relay?.removeListener(_onRelay);
    _relay?.dispose();
    final relay = RelayClient(url: url);
    relay.onControl = _onControl;
    relay.addListener(_onRelay);
    setState(() => _relay = relay);
    await relay.connect();
  }

  Future<void> _addSession(String name, String url) async {
    await _sessions.add(name, url);
  }

  void _disconnect() {
    _relay?.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final relay = _relay;
    final active = _sessions.active;

    final body = stackOfMain(relay, active);

    return Scaffold(
      body: Stack(
        children: [
          body,
          Positioned.fill(
            child: SessionPanel(
              manager: _sessions,
              open: _panelOpen,
              onClose: () => setState(() => _panelOpen = false),
              onAddSession: _addSession,
            ),
          ),
        ],
      ),
    );
  }

  Widget stackOfMain(RelayClient? relay, PhoneSession? active) {
    if (relay == null || !relay.connected) {
      return ConnectionScreen(
        initialUrl: active?.serverUrl ?? kDefaultServer,
        busy: relay?.busy ?? false,
        error: relay?.errorText,
        onMenu: () => setState(() => _panelOpen = true),
        onConnect: _connectTo,
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _StatusStrip(
            relay: relay,
            sessionName: active?.name,
            panelOpen: _panelOpen,
            onMenu: () => setState(() => _panelOpen = !_panelOpen),
            onDisconnect: _disconnect,
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                ChatScreen(
                  relay: relay,
                  onShare: () => setState(() => _tab = 3),
                ),
                ControlScreen(relay: relay, capture: _capture),
                SwarmScreen(relay: relay),
                ScreenShareScreen(relay: relay, capture: _capture),
              ],
            ),
          ),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            height: 62,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum),
                label: 'Chat',
              ),
              NavigationDestination(
                icon: Icon(Icons.touch_app_outlined),
                selectedIcon: Icon(Icons.touch_app),
                label: 'Control',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: 'Swarm',
              ),
              NavigationDestination(
                icon: Icon(Icons.screen_share_outlined),
                selectedIcon: Icon(Icons.screen_share),
                label: 'Share',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.relay,
    required this.sessionName,
    required this.panelOpen,
    required this.onMenu,
    required this.onDisconnect,
  });

  final RelayClient relay;
  final String? sessionName;
  final bool panelOpen;
  final VoidCallback onMenu;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 6, right: 12),
      decoration: const BoxDecoration(
        color: Nord.surface,
        border: Border(bottom: BorderSide(color: Nord.border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onMenu,
            child: AnimatedRotation(
              turns: panelOpen ? 0.125 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: const Icon(Icons.menu, size: 20, color: Nord.text2),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: relay.connected ? Nord.success : Nord.warning,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  relay.connected ? (sessionName ?? 'Connected') : 'Connecting…',
                  style: const TextStyle(
                    color: Nord.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  relay.url,
                  style: const TextStyle(color: Nord.muted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDisconnect,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.logout, size: 17, color: Nord.muted),
            ),
          ),
        ],
      ),
    );
  }
}