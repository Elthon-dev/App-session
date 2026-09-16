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
        _PickerBar(
          relay: widget.relay,
          onModel: _openModelPicker,
          onAgent: _openAgentPicker,
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

  void _openModelPicker() {
    final models = widget.relay.models;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Nord.bg,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return _PickerSheet<ModelInfo>(
          title: 'Model',
          icon: Icons.memory_outlined,
          items: models,
          emptyText: 'No models received yet.\nRestart Opencode, then tap Sync.',
          selected: widget.relay.selectedModel,
          labelOf: (m) => m.label,
          subtitleOf: (m) => m.providerID,
          selectedOf: (m) => widget.relay.selectedModel?.modelID == m.modelID,
          onPick: (m) {
            widget.relay.selectModel(m);
            Navigator.pop(ctx);
          },
          onRefresh: () => widget.relay.sendRaw({'type': 'get-config'}),
        );
      },
    );
  }

  void _openAgentPicker() {
    final agents = widget.relay.agents;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Nord.bg,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return _PickerSheet<AgentInfo>(
          title: 'Agent',
          icon: Icons.auto_awesome_outlined,
          items: agents,
          emptyText: 'No agents received yet.\nRestart Opencode, then tap Sync.',
          selected: widget.relay.selectedAgent,
          labelOf: (a) => a.name,
          subtitleOf: (a) => a.description,
          selectedOf: (a) => widget.relay.selectedAgent?.name == a.name,
          onPick: (a) {
            widget.relay.selectAgent(a);
            Navigator.pop(ctx);
          },
          onRefresh: () => widget.relay.sendRaw({'type': 'get-config'}),
        );
      },
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

class _PickerBar extends StatelessWidget {
  const _PickerBar({required this.relay, required this.onModel, required this.onAgent});

  final RelayClient relay;
  final VoidCallback onModel;
  final VoidCallback onAgent;

  Widget _pill({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Nord.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? Nord.info.withValues(alpha: 0.8) : Nord.border,
              width: active ? 1.3 : 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: active ? Nord.info : Nord.muted),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Nord.text1 : Nord.text2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 14, color: Nord.muted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = relay.selectedModel;
    final agent = relay.selectedAgent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      color: Nord.bg,
      child: Row(
        children: [
          _pill(
            icon: Icons.memory,
            label: model?.label ?? 'Model',
            active: model != null,
            onTap: onModel,
          ),
          const SizedBox(width: 8),
          _pill(
            icon: Icons.auto_awesome,
            label: agent?.name ?? 'Agent',
            active: agent != null,
            onTap: onAgent,
          ),
          const Spacer(),
          if (!relay.loaded)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: Nord.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
    required this.selected,
    required this.labelOf,
    required this.subtitleOf,
    required this.selectedOf,
    required this.onPick,
    required this.onRefresh,
  });

  final String title;
  final IconData icon;
  final List<T> items;
  final String emptyText;
  final T? selected;
  final String Function(T) labelOf;
  final String Function(T) subtitleOf;
  final bool Function(T) selectedOf;
  final ValueChanged<T> onPick;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final tileH = 60.0;
    final listH = items.isEmpty ? 130.0 : (items.length * tileH).clamp(0.0, tileH * 6.0);
    return SafeArea(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Nord.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: Nord.info),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Select $title',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Nord.text1),
                    ),
                  ),
                  IconButton(
                    onPressed: onRefresh,
                    tooltip: 'Sync from Opencode',
                    icon: const Icon(Icons.sync, size: 18, color: Nord.muted),
                  ),
                ],
              ),
            ),
            items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5, height: 1.5, color: Nord.muted),
                    ),
                  )
                : SizedBox(
                    height: listH,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final isSel = selectedOf(item);
                        return InkWell(
                          onTap: () => onPick(item),
                          child: Container(
                            height: tileH,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: isSel ? Nord.surface : Colors.transparent,
                              border: Border(bottom: BorderSide(color: Nord.border.withValues(alpha: 0.4), width: 0.4)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSel ? Nord.accent : Nord.muted,
                                      width: 1.6,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: isSel
                                      ? Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Nord.accent),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        labelOf(item),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: isSel ? Nord.text1 : Nord.text2,
                                        ),
                                      ),
                                      if (subtitleOf(item).isNotEmpty)
                                        Text(
                                          subtitleOf(item),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Nord.muted),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isSel) const Icon(Icons.check, size: 17, color: Nord.accent),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
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