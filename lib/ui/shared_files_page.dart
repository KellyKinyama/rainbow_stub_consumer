import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/rest_capsule.dart';
import 'file_preview_page.dart';

enum _SortBy { date, name, size }

class SharedFilesPage extends RearchConsumer {
  const SharedFilesPage({
    super.key,
    required this.peerJid,
    required this.title,
  });

  final String peerJid;
  final String title;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final rest = use(restCapsule);
    final me = use(authCapsule).me;
    final slot = use.data<AsyncValue<List<FileDescriptor>>>(
      const AsyncLoading<List<FileDescriptor>>(None()),
    );
    final (sortBy, setSortBy) = use.state<_SortBy>(_SortBy.date);

    Option<List<FileDescriptor>> previousOf(
      AsyncValue<List<FileDescriptor>> v,
    ) => switch (v) {
      AsyncData<List<FileDescriptor>>(:final data) => Some(data),
      AsyncLoading<List<FileDescriptor>>(:final previousData) => previousData,
      AsyncError<List<FileDescriptor>>(:final previousData) => previousData,
    };

    Future<void> load() async {
      slot.value = AsyncLoading<List<FileDescriptor>>(previousOf(slot.value));
      try {
        final list = await rest.listSharedFiles(peerJid);
        slot.value = AsyncData<List<FileDescriptor>>(list);
      } on Object catch (e, s) {
        slot.value = AsyncError<List<FileDescriptor>>(
          e,
          s,
          previousOf(slot.value),
        );
      }
    }

    use.effect(() {
      load();
      return null;
    }, [peerJid]);

    Future<void> deleteOne(FileDescriptor f) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete file'),
          content: Text('Remove "${f.fileName}" from shared files?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await rest.deleteFile(f.id);
        await load();
      } on Object catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }

    List<FileDescriptor> sorted(List<FileDescriptor> src) {
      final copy = List<FileDescriptor>.of(src);
      switch (sortBy) {
        case _SortBy.date:
          copy.sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );
        case _SortBy.name:
          copy.sort(
            (a, b) =>
                a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
          );
        case _SortBy.size:
          copy.sort((a, b) => b.size.compareTo(a.size));
      }
      return copy;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Files · $title'),
        actions: [
          PopupMenuButton<_SortBy>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: sortBy,
            onSelected: setSortBy,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortBy.date, child: Text('Date')),
              PopupMenuItem(value: _SortBy.name, child: Text('Name')),
              PopupMenuItem(value: _SortBy.size, child: Text('Size')),
            ],
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: load,
          ),
        ],
      ),
      body: switch (slot.value) {
        AsyncLoading<List<FileDescriptor>>() => const Center(
          child: CircularProgressIndicator(),
        ),
        AsyncError<List<FileDescriptor>>(:final error) => Center(
          child: Text('Could not load files: $error'),
        ),
        AsyncData<List<FileDescriptor>>(:final data) when data.isEmpty =>
          const Center(child: Text('No shared files yet')),
        AsyncData<List<FileDescriptor>>(:final data) => ListView.builder(
          itemCount: data.length,
          itemBuilder: (_, i) {
            final f = sorted(data)[i];
            final canDelete = me?.id != null && me!.id == f.ownerId;
            return Dismissible(
              key: ValueKey(f.id),
              direction: canDelete
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              background: Container(
                alignment: Alignment.centerRight,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.only(right: 24),
                child: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              confirmDismiss: (_) async {
                await deleteOne(f);
                return false;
              },
              child: ListTile(
                leading: CircleAvatar(child: Icon(_iconFor(f))),
                title: Text(
                  f.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_subtitle(f)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FilePreviewPage(file: f),
                  ),
                ),
              ),
            );
          },
        ),
      },
    );
  }

  static IconData _iconFor(FileDescriptor f) {
    if (f.isImage) return Icons.image_outlined;
    if (f.mimeType.startsWith('video/')) return Icons.movie_outlined;
    if (f.mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (f.mimeType == 'application/pdf') return Icons.picture_as_pdf;
    return Icons.insert_drive_file_outlined;
  }

  static String _subtitle(FileDescriptor f) {
    final size = _humanSize(f.size);
    final when = f.createdAt == null
        ? ''
        : ' · ${f.createdAt!.toLocal().toString().split('.').first}';
    return '$size$when';
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
