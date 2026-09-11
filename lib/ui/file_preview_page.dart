import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rainbow/models.dart';
import '../state/capsules/rest_capsule.dart';

class FilePreviewPage extends RearchConsumer {
  const FilePreviewPage({super.key, required this.file});

  final FileDescriptor file;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final rest = use(restCapsule);
    final bytesSlot = use.data<AsyncValue<Uint8List>>(
      const AsyncLoading<Uint8List>(None()),
    );

    Future<void> fetch() async {
      if (file.downloadUrl.isEmpty) {
        bytesSlot.value = AsyncError<Uint8List>(
          StateError('No download URL'),
          StackTrace.current,
          const None(),
        );
        return;
      }
      bytesSlot.value = const AsyncLoading<Uint8List>(None());
      try {
        final raw = await rest.downloadFileBytes(file.downloadUrl);
        bytesSlot.value = AsyncData<Uint8List>(Uint8List.fromList(raw));
      } on Object catch (e, s) {
        bytesSlot.value = AsyncError<Uint8List>(e, s, const None());
      }
    }

    use.effect(() {
      if (file.isImage) fetch();
      return null;
    }, [file.id]);

    return Scaffold(
      appBar: AppBar(
        title: Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.link),
            onPressed: file.downloadUrl.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: file.downloadUrl),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetaCard(file: file),
            const SizedBox(height: 16),
            if (file.isImage)
              _ImagePreview(state: bytesSlot.value, onRetry: fetch)
            else
              _NonImageActions(file: file),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.file});
  final FileDescriptor file;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(Icons.description_outlined, file.fileName),
            const SizedBox(height: 8),
            _row(Icons.category_outlined, file.mimeType),
            const SizedBox(height: 8),
            _row(Icons.numbers, _humanSize(file.size)),
            if (file.createdAt != null) ...[
              const SizedBox(height: 8),
              _row(
                Icons.event,
                file.createdAt!.toLocal().toString().split('.').first,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.state, required this.onRetry});
  final AsyncValue<Uint8List> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AsyncLoading<Uint8List>() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      AsyncError<Uint8List>(:final error) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Preview failed: $error'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
      AsyncData<Uint8List>(:final data) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(data, fit: BoxFit.contain),
      ),
    };
  }
}

class _NonImageActions extends StatelessWidget {
  const _NonImageActions({required this.file});
  final FileDescriptor file;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: file.downloadUrl.isEmpty
              ? null
              : () async {
                  final uri = Uri.tryParse(file.downloadUrl);
                  if (uri == null) return;
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open link')),
                    );
                  }
                },
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open link'),
        ),
        const SizedBox(height: 8),
        Text(
          'Inline preview supports images only. Non-image files can be opened '
          'in the browser (requires the server to accept the current session).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
