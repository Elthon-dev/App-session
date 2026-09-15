import 'package:flutter/material.dart';

import '../relay.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.relay, required this.onShare});

  final RelayClient relay;
  final VoidCallback onShare;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final List<_SlashCmd> _commands = [];

  @override
  void initState() {
    super.initState();
    _commands.addAll([
      _SlashCmd('/help', 'Show available commands', Icons.help_outline, _runHelp),
      _SlashCmd('/status', 'Show connection and session info', Icons.info_outline, _runStatus),
      _SlashCmd('/clearchat', 'Clear this conversation', Icons.delete_sweep_outlined, _runClearchat),
      _SlashCmd('/share', 'Open screen share', Icons.screen_share_outlined, () => widget.onShare()),
    ]);
    widget.relay.addListener(_onChange);
    _input.addListener(_onTyping);
    _onTyping();
  }

  @override
  void dispose() {
    widget.relay.removeListener(_onChange);
    _input.removeListener(_onTyping);
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTyping() {
    if (!mounted) return;
    setState(() {});
  }

  void _execute(_SlashCmd cmd) {
    cmd.action();
    _input.clear();
    _focusInput();
  }

  void _runHelp() {
    final names = _commands.map((c) => c.name).join(', ');
    widget.relay.addSystem('Available commands: $names');
  }

  void _runStatus() {
    final relay = widget.relay;
    widget.relay.addSystem(
      'Relay: ${relay.url}\nState: ${relay.state.name.toUpperCase()}${relay.errorText != null ? '\nError: ${relay.errorText}' : ''}',
    );
  }

  void _runClearchat() => widget.relay.clearMessages();

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;

    final t = text.trim();
    if (t.startsWith('/') && !t.contains(' ')) {
      for (final c in _commands) {
        if (c.name == t.toLowerCase()) {
          _execute(c);
          return;
        }
      }
      widget.relay.addSystem('Unknown command: $t — type /help');
      _input.clear();
      return;
    }

    widget.relay.sendChat(t);
    _input.clear();
    _focusInput();
  }

  void _focusInput() => _inputFocus.requestFocus();

  @override
  Widget build(BuildContext context) {
    final messages = widget.relay.messages;

    final raw = _input.text;
    final typed = raw.trim().toLowerCase();
    var showPalette = false;
    List<_SlashCmd> matches = const [];
    if (typed.startsWith('/') && !typed.contains(' ') && _commands.isNotEmpty) {
      matches = _commands.where((c) => c.name.startsWith(typed)).toList();
      showPalette = matches.isNotEmpty;
    }

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty ? _EmptyState() : _MessageList(relay: widget.relay, scroll: _scroll),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: showPalette
              ? _CommandPalette(cmds: matches, onPick: _execute)
              : const SizedBox(width: double.infinity),
        ),
        _Composer(controller: _input, focus: _inputFocus, onSend: _send),
      ],
    );
  }
}

class _SlashCmd {
  const _SlashCmd(this.name, this.desc, this.icon, this.action);

  final String name;
  final String desc;
  final IconData icon;
  final VoidCallback action;
}

class _CommandPalette extends StatelessWidget {
  const _CommandPalette({required this.cmds, required this.onPick});

  final List<_SlashCmd> cmds;
  final ValueChanged<_SlashCmd> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Nord.surface,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in cmds)
            InkWell(
              onTap: () => onPick(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Icon(c.icon, size: 17, color: Nord.info),
                    const SizedBox(width: 12),
                    Text(
                      c.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Nord.text1),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.desc,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Nord.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined, size: 34, color: Nord.muted),
          const SizedBox(height: 10),
          const Text(
            'Session ready',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Nord.text2),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ask anything, or share your screen for hands-on help.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Nord.muted),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.relay, required this.scroll});

  final RelayClient relay;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final messages = relay.messages;
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, i) => _Bubble(message: messages[i]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final msg = message;
    final isUser = msg.role == ChatRole.user;

    if (msg.role == ChatRole.system) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          msg.text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Nord.muted),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? Nord.accent : Nord.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isUser ? 15 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 15),
          ),
          border: isUser ? null : Border.all(color: Nord.border, width: 0.5),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: isUser ? Nord.bg : Nord.text2,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.focus, required this.onSend});

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: const BoxDecoration(
        color: Nord.bg,
        border: Border(top: BorderSide(color: Nord.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 14, color: Nord.text1),
              decoration: const InputDecoration(hintText: 'Message Opencode…'),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final hasText = controller.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasText ? Nord.accent : Nord.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.send, size: 17, color: hasText ? Nord.bg : Nord.muted),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}