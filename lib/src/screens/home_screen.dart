import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../relay.dart';
import '../screen_capture.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'connection_screen.dart';
import 'screen_share_screen.dart';

const kDefaultServer = 'ws://127.0.0.1:8765';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RelayClient? _relay;
  final ScreenCaptureService _capture = ScreenCaptureService();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _capture.bind();
    _restoreAndConnect();
  }

  Future<void> _restoreAndConnect() async {
    _capture.bind();
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('bridge-server') ?? kDefaultServer;
    if (!mounted) return;
    _relay?.removeListener(_onRelay);
    final relay = RelayClient(url: url);
    relay.addListener(_onRelay);
    setState(() => _relay = relay);
    relay.connect();
  }

  void _onRelay() => setState(() {});

  Future<void> _connectTo(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bridge-server', url);
    if (!mounted) return;
    _relay?.removeListener(_onRelay);
    final relay = RelayClient(url: url);
    relay.addListener(_onRelay);
    setState(() => _relay = relay);
    await relay.connect();
  }

  void _disconnect() {
    _relay?.disconnect();
  }

  @override
  void dispose() {
    _relay?.removeListener(_onRelay);
    _relay?.dispose();
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relay = _relay;

    return Scaffold(
      body: relay == null || !relay.connected
          ? ConnectionScreen(
              initialUrl: relay?.url ?? kDefaultServer,
              busy: relay?.busy ?? false,
              error: relay?.errorText,
              onConnect: _connectTo,
            )
          : SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _StatusStrip(relay: relay, onDisconnect: _disconnect),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        ChatScreen(relay: relay),
                        ScreenShareScreen(
                          relay: relay,
                          capture: _capture,
                        ),
                      ],
                    ),
                  ),
                  NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    height: 64,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.forum_outlined),
                        selectedIcon: Icon(Icons.forum),
                        label: 'Chat',
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
            ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.relay, required this.onDisconnect});

  final RelayClient relay;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Nord.surface,
        border: Border(bottom: BorderSide(color: Nord.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: relay.connected ? Nord.success : Nord.warning,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            relay.connected ? 'Connected' : 'Connecting…',
            style: const TextStyle(color: Nord.text2, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              relay.url,
              style: const TextStyle(color: Nord.muted, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onDisconnect,
            child: const Icon(Icons.logout, size: 17, color: Nord.muted),
          ),
        ],
      ),
    );
  }
}