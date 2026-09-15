import 'package:flutter/material.dart';

import '../sessions.dart';
import '../theme.dart';

/// Left-hand session manager panel, slides in with a soft spring.
class SessionPanel extends StatelessWidget {
  const SessionPanel({
    super.key,
    required this.manager,
    required this.open,
    required this.onClose,
    required this.onAddSession,
  });

  final SessionManager manager;
  final bool open;
  final VoidCallback onClose;
  final Future<void> Function(String name, String url) onAddSession;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(264.0, 320.0).toDouble();
    final activeId = manager.active?.id;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !open,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: GestureDetector(
                onTap: onClose,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: open ? 0.45 : 0),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          left: open ? 0 : -width,
          top: 0,
          bottom: 0,
          width: width,
          child: Material(
            color: Nord.surface,
            elevation: 24,
            shadowColor: Colors.black,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: manager,
                builder: (context, _) {
                  final sessions = manager.sessions;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(onClose: onClose),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        child: Text(
                          'SESSIONS',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                            color: Nord.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: sessions.length,
                          itemBuilder: (context, i) {
                            final s = sessions[i];
                            final isActive = s.id == activeId;
                            return _SessionTile(
                              session: s,
                              active: isActive,
                              canDelete: sessions.length > 1,
                              onTap: () {
                                manager.select(s.id);
                                onClose();
                              },
                              onDelete: () => manager.remove(s.id),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        child: FilledButton.tonalIcon(
                          onPressed: () => _promptAdd(context),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('New session'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Nord.border,
                            foregroundColor: Nord.text1,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _promptAdd(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Nord.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New session', style: TextStyle(fontSize: 17, color: Nord.text1)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My relay',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Relay address',
                hintText: 'ws://192.168.1.10:8765',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Nord.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Nord.accent, foregroundColor: Nord.bg),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await onAddSession(nameCtrl.text, urlCtrl.text);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Nord.primary, Nord.info],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'O',
              style: TextStyle(color: Nord.text1, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'OpenBridge',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Nord.text1),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Nord.border.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.close, size: 17, color: Nord.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.active,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  final PhoneSession session;
  final bool active;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: active ? Nord.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? Nord.accent.withValues(alpha: 0.4) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Nord.accent : Nord.border,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    session.name.isEmpty ? '?' : session.name[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: active ? Nord.bg : Nord.text2,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: active ? Nord.text1 : Nord.text2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.serverUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Nord.muted),
                      ),
                    ],
                  ),
                ),
                if (active)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_circle, size: 17, color: Nord.accent),
                  )
                else if (canDelete)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(Icons.delete_outline, size: 16, color: Nord.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}