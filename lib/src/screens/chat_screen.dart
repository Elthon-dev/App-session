import 'package:flutter/material.dart';

import '../relay.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.relay});

  final RelayClient relay;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.relay.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.relay.removeListener(_onChange);
    _scroll.dispose();
    _input.dispose();
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

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    widget.relay.sendChat(text);
    _input.clear();
    _focusInput();
  }

  void _focusInput() => _inputFocus.requestFocus();

  final FocusNode _inputFocus = FocusNode();

  @override
  Widget build(BuildContext context) {
    final messages = widget.relay.messages;

    if (messages.isEmpty) {
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

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: messages.length,
            itemBuilder: (context, i) {
              final m = messages[i];
              return _Bubble(message: m);
            },
          ),
        ),
        _Composer(controller: _input, focus: _inputFocus, onSend: _send),
      ],
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
          border: isUser ? null : const Border.side(color: Nord.border, width: 0.5),
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