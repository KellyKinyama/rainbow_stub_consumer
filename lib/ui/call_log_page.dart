import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/call_logs_capsule.dart';

/// Full-screen list of past calls, matching RN sample's
/// ``CallLogComponent``. Supports a segment for `All / Missed` +
/// per-row delete (long-press).
class CallLogPage extends RearchConsumer {
  const CallLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final controller = use(callLogsCapsule);
    final (filter, setFilter) = use.state<_Filter>(_Filter.all);
    final entriesAsync = controller.entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent calls'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refresh,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<_Filter>(
              segments: const [
                ButtonSegment(value: _Filter.all, label: Text('All')),
                ButtonSegment(value: _Filter.missed, label: Text('Missed')),
              ],
              selected: {filter},
              onSelectionChanged: (s) => setFilter(s.first),
            ),
          ),
        ),
      ),
      body: switch (entriesAsync) {
        AsyncLoading<List<CallLogEntry>>() =>
          const Center(child: CircularProgressIndicator()),
        AsyncError<List<CallLogEntry>>(:final error) =>
          Center(child: Text('Could not load call log: $error')),
        AsyncData<List<CallLogEntry>>(:final data) => _CallList(
            entries: filter == _Filter.missed
                ? data.where((e) => e.isMissed).toList(growable: false)
                : data,
            onDelete: controller.delete,
          ),
      },
    );
  }
}

enum _Filter { all, missed }

class _CallList extends StatelessWidget {
  const _CallList({required this.entries, required this.onDelete});
  final List<CallLogEntry> entries;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No calls yet'));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        return Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Icon(
              Icons.delete,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          onDismissed: (_) => onDelete(e.id),
          child: ListTile(
            leading: _CallIcon(entry: e),
            title: Text(_titleFor(e)),
            subtitle: Text(_subtitleFor(e)),
            trailing: Text(_timeLabel(e.startedAt)),
          ),
        );
      },
    );
  }

  static String _titleFor(CallLogEntry e) {
    if (e.peerDisplayName != null && e.peerDisplayName!.isNotEmpty) {
      return e.peerDisplayName!;
    }
    final at = e.peerJid.indexOf('@');
    return at < 0 ? e.peerJid : e.peerJid.substring(0, at);
  }

  static String _subtitleFor(CallLogEntry e) {
    final direction =
        e.isOutgoing ? 'Outgoing' : 'Incoming';
    final state = switch (e.state) {
      'answered' => e.durationMs == 0 ? 'ended' : _formatDuration(e.durationMs),
      'missed' => 'missed',
      'declined' => 'declined',
      'failed' => 'failed',
      _ => e.state,
    };
    final media = e.media == 'video' ? 'video · ' : '';
    return '$direction · $media$state';
  }

  static String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    if (that == today) {
      return '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}/${t.month}';
  }
}

class _CallIcon extends StatelessWidget {
  const _CallIcon({required this.entry});
  final CallLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry.state) {
      'missed' => (Icons.call_missed, scheme.error),
      'declined' => (Icons.call_end, scheme.error),
      'failed' => (Icons.error_outline, scheme.error),
      _ when entry.isOutgoing => (Icons.call_made, scheme.primary),
      _ => (Icons.call_received, scheme.primary),
    };
    return CircleAvatar(
      backgroundColor: scheme.primaryContainer,
      child: Icon(icon, color: color),
    );
  }
}
