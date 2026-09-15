import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum RelayState { idle, connecting, connected, disconnected, error }

enum ChatRole { user, assistant, system }

class ChatMessage {
  ChatMessage({required this.role, required this.text});
  final ChatRole role;
  final String text;
}

class OverlayData {
  OverlayData({
    required this.shape,
    required this.x,
    required this.y,
    this.dx,
    this.dy,
    this.label,
    this.ttl = 4000,
  });

  final String shape;
  final double x;
  final double y;
  final double? dx;
  final double? dy;
  final String? label;
  final int ttl;
}

class RelayClient extends ChangeNotifier {
  RelayClient({required this.url}) {
    _sessionId = 'ob${1000 + Random().nextInt(9000)}';
  }

  final String url;
  late final String _sessionId;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pendingOverlay;
  Timer? _reconnectTimer;
  int _attempts = 0;

  RelayState state = RelayState.idle;
  List<ChatMessage> messages = [];
  OverlayData? overlay;
  String? errorText;

  bool get connected => state == RelayState.connected;
  bool get busy => state == RelayState.connecting;

  void _set(RelayState s) {
    state = s;
    notifyListeners();
  }

  void _push(ChatRole role, String text) {
    messages.add(ChatMessage(role: role, text: text));
    notifyListeners();
  }

  void sendRaw(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> connect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    _channel = null;
    messages.clear();
    overlay = null;
    errorText = null;
    _set(RelayState.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _sub = channel.stream.listen(
        _handle,
        onError: (_) => _onClose(),
        onDone: _onClose,
        cancelOnError: true,
      );
      unawaited(channel.ready.then((_) {
        sendRaw({'type': 'register', 'platform': 'phone', 'sessionId': _sessionId});
      }));
    } catch (e) {
      errorText = 'Could not reach the relay: $e';
      _set(RelayState.error);
      _scheduleReconnect();
    }
  }

  void _handle(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = j['type'] as String? ?? '';
      switch (type) {
        case 'ready':
          _attempts = 0;
          _set(RelayState.connected);
          break;
        case 'chat':
          final t = j['text'] as String? ?? '';
          if (t.trim().isNotEmpty) _push(ChatRole.assistant, t);
          break;
        case 'toast':
          _push(ChatRole.system, j['text'] as String? ?? '');
          break;
        case 'overlay':
          _pendingOverlay?.cancel();
          overlay = OverlayData(
            shape: j['shape'] as String? ?? 'tap',
            x: ((j['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
            y: ((j['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
            dx: (j['dx'] as num?)?.toDouble(),
            dy: (j['dy'] as num?)?.toDouble(),
            label: j['label'] as String?,
            ttl: (j['ttl'] as num?)?.toInt() ?? 4000,
          );
          notifyListeners();
          _pendingOverlay = Timer(Duration(milliseconds: overlay!.ttl), () {
            overlay = null;
            notifyListeners();
          });
          break;
        case 'vibrate':
          final d = (j['duration'] as num?)?.toInt() ?? 120;
          unawaited(Vibration.vibrate(duration: d < 20 ? 80 : d));
          break;
        case 'open':
          final u = j['url'] as String? ?? '';
          if (u.isNotEmpty) {
            unawaited(launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication));
          }
          break;
        case 'ping':
          sendRaw({'type': 'pong'});
          break;
      }
    } catch (_) {}
  }

  void _onClose() {
    _channel = null;
    _sub = null;
    overlay = null;
    _set(RelayState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    _attempts += 1;
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _reconnectTimer = null;
      connect();
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _attempts = 0;
    await _sub?.cancel();
    _sub = null;
    _channel = null;
    overlay = null;
    messages.clear();
    _set(RelayState.idle);
  }

  void sendChat(String text) {
    if (text.trim().isEmpty) return;
    _push(ChatRole.user, text);
    sendRaw({'type': 'chat', 'text': text});
  }

  void sendFrame(String dataUrl) {
    sendRaw({'type': 'screen', 'image': dataUrl});
  }

  void sendGesture({required String type, required double x, required double y}) {
    sendRaw({'type': 'gesture', 'type': type, 'x': x, 'y': y});
  }

  @override
  void dispose() {
    _pendingOverlay?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}