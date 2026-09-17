import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../relay.dart';
import '../swarm.dart';
import '../theme.dart';

/// The agent grid: deploy a master task across multiple sub-agents, watch them
/// think in parallel, and read the converged result.
class SwarmScreen extends StatefulWidget {
  const SwarmScreen({super.key, required this.relay});

  final RelayClient relay;

  @override
  State<SwarmScreen> createState() => _SwarmScreenState();
}

class _SwarmScreenState extends State<SwarmScreen> {
  final TextEditingController _task = TextEditingController();
  final Set<String> _spread = {};
  bool _seededSpread = false;
  String? _selectedRunId;

  @override
  void initState() {
    super.initState();
    widget.relay.addListener(_changed);
    _seedSpread();
  }

  @override
  void dispose() {
    widget.relay.removeListener(_changed);
    _task.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (!_seededSpread) _seedSpread();
    setState(() {});
  }

  void _seedSpread() {
    if (_seededSpread) return;
    final names = widget.relay.agents.map((a) => a.name).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return;
    _spread.addAll(names.take(3));
    _seededSpread = true;
  }

  SwarmRun? get _shown {
    final id = _selectedRunId;
    if (id != null) {
      final active = widget.relay.swarm;
      if (active != null && active.id == id) return active;
      for (final run in widget.relay.swarmHistory) {
        if (run.id == id) return run;
      }
    }
    return widget.relay.swarm ?? (widget.relay.swarmHistory.isNotEmpty ? widget.relay.swarmHistory.first : null);
  }

  void _deploy() {
    final task = _task.text.trim();
    if (task.isEmpty) return;
    final spread = _spread.isEmpty
        ? (widget.relay.agents.map((a) => a.name).take(3).toList().isEmpty
            ? ['general']
            : widget.relay.agents.map((a) => a.name).take(3).toList())
        : _spread.toList();
    widget.relay.startSwarm(task, spread);
    _task.clear();
    _selectedRunId = null;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final relay = widget.relay;
    final run = _shown;

    return Column(
      children: [
        _Composer(
          controller: _task,
          agents: relay.agents.map((a) => a.name).toList(),
          spread: _spread,
          connected: relay.connected,
          running: relay.swarmRunning,
          onToggle: (name) => setState(() {
            if (!_spread.remove(name)) _spread.add(name);
          }),
          onDeploy: _deploy,
          onCancel: relay.cancelSwarm,
        ),
        if (relay.swarmHistory.isNotEmpty)
          _RunSelector(
            runs: [if (relay.swarm != null) relay.swarm!, ...relay.swarmHistory],
            selectedId: run?.id,
            onSelect: (id) => setState(() => _selectedRunId = id),
          ),
        Expanded(
          child: run == null
              ? const _Empty()
              : _RunView(run: run, onClear: relay.clearSwarm),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.agents,
    required this.spread,
    required this.connected,
    required this.running,
    required this.onToggle,
    required this.onDeploy,
    required this.onCancel,
  });

  final TextEditingController controller;
  final List<String> agents;
  final Set<String> spread;
  final bool connected;
  final bool running;
  final ValueChanged<String> onToggle;
  final VoidCallback onDeploy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Nord.surface,
        border: Border(bottom: BorderSide(color: Nord.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, size: 17, color: Nord.info),
              const SizedBox(width: 8),
              const Text(
                'Swarm orchestrator',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Nord.text1),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (connected ? Nord.success : Nord.warning).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  connected ? 'host online' : 'offline',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: connected ? Nord.success : Nord.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            enabled: !running,
            style: const TextStyle(fontSize: 13.5, color: Nord.text1),
            decoration: const InputDecoration(
              hintText: 'Give the swarm a mission… e.g. "Research X and draft a plan"',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Spread across',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Nord.muted),
          ),
          const SizedBox(height: 6),
          if (agents.isEmpty)
            const Text(
              'No agents reported yet — start Opencode to receive the roster.',
              style: TextStyle(fontSize: 11, color: Nord.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in agents)
                  FilterChip(
                    label: Text(a, style: TextStyle(fontSize: 11, color: spread.contains(a) ? Nord.bg : Nord.text2)),
                    selected: spread.contains(a),
                    onSelected: running ? null : (_) => onToggle(a),
                    backgroundColor: Nord.bg,
                    selectedColor: Nord.info,
                    side: const BorderSide(color: Nord.border, width: 0.6),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: connected && !running ? onDeploy : null,
                  icon: const Icon(Icons.rocket_launch_outlined, size: 17),
                  label: Text(running ? 'Swarm deployed…' : 'Deploy swarm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Nord.accent,
                    foregroundColor: Nord.bg,
                    disabledBackgroundColor: Nord.border,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (running) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Nord.error,
                    side: const BorderSide(color: Nord.error),
                    minimumSize: const Size(84, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Stop', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RunSelector extends StatelessWidget {
  const _RunSelector({required this.runs, required this.selectedId, required this.onSelect});

  final List<SwarmRun> runs;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: runs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final run = runs[i];
          final selected = run.id == selectedId;
          return InkWell(
            onTap: () => onSelect(run.id),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? Nord.primary.withValues(alpha: 0.25) : Nord.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? Nord.info : Nord.border, width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    run.finished ? Icons.check_circle_outline : Icons.sync,
                    size: 12,
                    color: run.finished ? Nord.success : Nord.info,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      run.task,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: selected ? Nord.text1 : Nord.muted),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView({required this.run, required this.onClear});

  final SwarmRun run;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _MasterCard(run: run),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              'Sub-agents',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Nord.text2),
            ),
            const SizedBox(width: 6),
            Text(
              '${run.doneCount}/${run.agents.length} done${run.failedCount > 0 ? ' · ${run.failedCount} failed' : ''}',
              style: const TextStyle(fontSize: 10.5, color: Nord.muted),
            ),
            const Spacer(),
            if (run.finished)
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Clear', style: TextStyle(fontSize: 11, color: Nord.muted)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final agent in run.agents) ...[
          _AgentCard(agent: agent),
          const SizedBox(height: 10),
        ],
        if (run.converging || run.summary != null) ...[
          const SizedBox(height: 4),
          _ConvergeCard(run: run),
        ],
        _CombinedOutputCard(run: run),
      ],
    );
  }
}

class _MasterCard extends StatelessWidget {
  const _MasterCard({required this.run});

  final SwarmRun run;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Nord.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nord.info.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Nord.info.withValues(alpha: 0.16),
                ),
                child: const Icon(Icons.hub, size: 15, color: Nord.info),
              ),
              const SizedBox(width: 9),
              const Text('Master task', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Nord.text1)),
              const Spacer(),
              _Elapsed(run: run),
            ],
          ),
          const SizedBox(height: 8),
          Text(run.task, style: const TextStyle(fontSize: 13, height: 1.4, color: Nord.text2)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: run.finished ? 1 : run.progress,
              minHeight: 6,
              backgroundColor: Nord.border,
              valueColor: AlwaysStoppedAnimation(run.failedCount > 0 && run.finished ? Nord.warning : Nord.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.run});

  final SwarmRun run;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  @override
  Widget build(BuildContext context) {
    final ms = widget.run.elapsedMs;
    return Text(
      '${(ms / 1000).toStringAsFixed(1)}s',
      style: const TextStyle(fontSize: 10.5, color: Nord.muted),
    );
  }
}

class _AgentCard extends StatefulWidget {
  const _AgentCard({required this.agent});

  final SwarmSubAgent agent;

  @override
  State<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<_AgentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final color = _statusColor(agent.status);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: Nord.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: agent.active ? color.withValues(alpha: 0.5) : Nord.border, width: agent.active ? 1 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusOrb(status: agent.status),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Nord.text1)),
                    Text(agent.role, style: const TextStyle(fontSize: 10, color: Nord.muted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  agentStatusLabel(agent.status),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          if (agent.detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              agent.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Nord.text2, height: 1.35),
            ),
          ],
          if (agent.output.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 15, color: Nord.info),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? 'Hide output' : 'Show output',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Nord.info),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Nord.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Nord.border, width: 0.5),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    agent.output,
                    style: const TextStyle(fontSize: 11, height: 1.45, color: Nord.text2),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ConvergeCard extends StatelessWidget {
  const _ConvergeCard({required this.run});

  final SwarmRun run;

  @override
  Widget build(BuildContext context) {
    final summary = run.summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
      decoration: BoxDecoration(
        color: Nord.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Nord.accent.withValues(alpha: 0.55), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.merge_type, size: 17, color: Nord.accent),
              const SizedBox(width: 8),
              const Text(
                'Converged result',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nord.text1),
              ),
              const Spacer(),
              if (summary == null)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: Nord.accent),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (summary == null || summary.isEmpty)
            const Text(
              'Synthesising sub-agent outputs…',
              style: TextStyle(fontSize: 11.5, color: Nord.muted),
            )
          else
            Text(summary, style: const TextStyle(fontSize: 13, height: 1.5, color: Nord.text2)),
        ],
      ),
    );
  }
}

/// All sub-agent outputs and the converged result flattened into one
/// copyable transcript, so the whole swarm's work can be lifted in one tap.
class _CombinedOutputCard extends StatefulWidget {
  const _CombinedOutputCard({required this.run});

  final SwarmRun run;

  @override
  State<_CombinedOutputCard> createState() => _CombinedOutputCardState();
}

class _CombinedOutputCardState extends State<_CombinedOutputCard> {
  late String _text;

  @override
  void didUpdateWidget(covariant _CombinedOutputCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.id != widget.run.id) _text = widget.run.combinedOutput;
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    _text = run.combinedOutput;
    final hasContent = run.agents.any((a) => a.output.trim().isNotEmpty) ||
        (run.summary != null && run.summary!.trim().isNotEmpty);

    return Padding(
      padding: EdgeInsets.only(top: hasContent ? 14 : 0),
      child: hasContent
          ? Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: Nord.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Nord.info.withValues(alpha: 0.35), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.paste_outlined, size: 16, color: Nord.info),
                      const SizedBox(width: 8),
                      const Text(
                        'Combined output',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Nord.text1),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${run.agents.length} agents',
                        style: const TextStyle(fontSize: 10.5, color: Nord.muted),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Combined output copied to clipboard.'),
                              backgroundColor: Nord.surface,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 17, color: Nord.accent),
                        tooltip: 'Copy combined output',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Nord.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Nord.border, width: 0.5),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _text,
                        style: const TextStyle(fontSize: 11.5, height: 1.45, color: Nord.text2),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.status});

  final SwarmAgentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    if (status == SwarmAgentStatus.thinking || status == SwarmAgentStatus.running) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.16)),
      child: Icon(_statusIcon(status), size: 13, color: color),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Nord.border, width: 1.4),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.hub_outlined, size: 32, color: Nord.muted),
            ),
            const SizedBox(height: 18),
            const Text(
              'Deploy a swarm',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Nord.text2),
            ),
            const SizedBox(height: 6),
            const Text(
              'Give one master task. OpenBridge spreads it across many sub-agents, each thinking in its own session, then converges their work into a single answer.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Nord.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(SwarmAgentStatus s) {
  switch (s) {
    case SwarmAgentStatus.pending:
      return Nord.muted;
    case SwarmAgentStatus.thinking:
      return Nord.info;
    case SwarmAgentStatus.running:
      return Nord.frost3;
    case SwarmAgentStatus.done:
      return Nord.success;
    case SwarmAgentStatus.failed:
      return Nord.error;
    case SwarmAgentStatus.cancelled:
      return Nord.warning;
  }
}

IconData _statusIcon(SwarmAgentStatus s) {
  switch (s) {
    case SwarmAgentStatus.pending:
      return Icons.schedule;
    case SwarmAgentStatus.thinking:
      return Icons.psychology_outlined;
    case SwarmAgentStatus.running:
      return Icons.bolt;
    case SwarmAgentStatus.done:
      return Icons.check;
    case SwarmAgentStatus.failed:
      return Icons.priority_high;
    case SwarmAgentStatus.cancelled:
      return Icons.block;
  }
}
