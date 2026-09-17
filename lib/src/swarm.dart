enum SwarmAgentStatus { pending, thinking, running, done, failed, cancelled }

SwarmAgentStatus parseAgentStatus(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'pending':
    case 'queued':
      return SwarmAgentStatus.pending;
    case 'thinking':
      return SwarmAgentStatus.thinking;
    case 'running':
    case 'working':
      return SwarmAgentStatus.running;
    case 'done':
    case 'complete':
    case 'completed':
      return SwarmAgentStatus.done;
    case 'failed':
    case 'error':
      return SwarmAgentStatus.failed;
    case 'cancelled':
    case 'canceled':
      return SwarmAgentStatus.cancelled;
    default:
      return SwarmAgentStatus.pending;
  }
}

String agentStatusLabel(SwarmAgentStatus s) {
  switch (s) {
    case SwarmAgentStatus.pending:
      return 'Queued';
    case SwarmAgentStatus.thinking:
      return 'Thinking';
    case SwarmAgentStatus.running:
      return 'Working';
    case SwarmAgentStatus.done:
      return 'Done';
    case SwarmAgentStatus.failed:
      return 'Failed';
    case SwarmAgentStatus.cancelled:
      return 'Cancelled';
  }
}

/// A single deployed sub-agent inside a swarm run.
class SwarmSubAgent {
  SwarmSubAgent({
    required this.id,
    required this.name,
    required this.role,
    this.status = SwarmAgentStatus.pending,
    this.output = '',
    this.detail = '',
    this.progress = 0,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String name;
  final String role;
  SwarmAgentStatus status;
  String output;
  String detail;
  double progress;
  int? startedAt;
  int? endedAt;

  int get elapsedMs {
    final start = startedAt;
    if (start == null) return 0;
    final end = endedAt ?? DateTime.now().millisecondsSinceEpoch;
    return end - start;
  }

  bool get active =>
      status == SwarmAgentStatus.thinking || status == SwarmAgentStatus.running;

  bool get finished =>
      status == SwarmAgentStatus.done ||
      status == SwarmAgentStatus.failed ||
      status == SwarmAgentStatus.cancelled;
}

/// A full swarm orchestration run: one master task spread across sub-agents,
/// converging into a synthesised result.
class SwarmRun {
  SwarmRun({
    required this.id,
    required this.task,
    required this.agents,
    this.summary,
    this.startedAt,
    this.endedAt,
    this.converging = false,
  });

  final String id;
  final String task;
  final List<SwarmSubAgent> agents;
  String? summary;
  int? startedAt;
  int? endedAt;
  bool converging;

  bool get finished =>
      endedAt != null &&
      agents.every((a) => a.finished) &&
      (summary != null && summary!.isNotEmpty);

  int get doneCount => agents.where((a) => a.status == SwarmAgentStatus.done).length;
  int get failedCount => agents.where((a) => a.status == SwarmAgentStatus.failed).length;
  int get activeCount => agents.where((a) => a.active).length;

  double get progress {
    if (agents.isEmpty) return 0;
    final total = agents.fold<double>(0, (sum, a) {
      if (a.finished) return sum + 1;
      if (a.active) return sum + a.progress.clamp(0.0, 0.9);
      return sum;
    });
    return (total / agents.length).clamp(0.0, 1.0);
  }

  int get elapsedMs {
    final start = startedAt;
    if (start == null) return 0;
    final end = endedAt ?? DateTime.now().millisecondsSinceEpoch;
    return end - start;
  }

  SwarmSubAgent? agentById(String id) {
    for (final a in agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Every sub-agent's final output plus the converged result, flattened into
  /// one copyable transcript.
  String get combinedOutput {
    final buf = StringBuffer();
    buf.writeln('Master task: $task');
    buf.writeln('${'─' * 48}');
    for (final a in agents) {
      buf.writeln('');
      buf.writeln('## ${a.name} (${a.role}) — ${agentStatusLabel(a.status)}');
      buf.writeln(a.output.trim().isEmpty ? '(no output)' : a.output.trim());
    }
    final summary = this.summary;
    if (summary != null && summary.trim().isNotEmpty) {
      buf.writeln('');
      buf.writeln('${'─' * 48}');
      buf.writeln('');
      buf.writeln('## Converged result');
      buf.writeln(summary.trim());
    }
    return buf.toString();
  }
}
