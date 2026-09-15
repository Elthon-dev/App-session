import 'package:flutter/material.dart';

import '../theme.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    super.key,
    required this.initialUrl,
    required this.onConnect,
    this.busy = false,
    this.error,
  });

  final String initialUrl;
  final ValueChanged<String> onConnect;
  final bool busy;
  final String? error;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final TextEditingController _server = TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _server.text.trim();
    if (url.isEmpty) return;
    widget.onConnect(url);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 2),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Nord.primary, Nord.info],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'O',
                style: TextStyle(
                  color: Nord.text1,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'OpenBridge',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Nord.text1),
            ),
            const SizedBox(height: 6),
            const Text(
              'Talk to Opencode from your phone.\nStart the relay in Termux, then connect.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Nord.muted, height: 1.5),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _server,
              onSubmitted: (_) => _submit(),
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Relay address',
                hintText: 'ws://127.0.0.1:8765',
              ),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Nord.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: widget.busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: Nord.accent,
                foregroundColor: Nord.bg,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: widget.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Nord.bg),
                    )
                  : const Text('Connect'),
            ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}