import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rearch/rearch.dart';

import '../state/capsules/rest_capsule.dart';
import 'chat_widgets.dart';

/// Bottom-sheet picker: "Camera" (mobile/web), "Image" (gallery), "File".
/// Returns picked bytes + name + mime, or `null` if the user dismissed.
class PickedAttachment {
  const PickedAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// True on platforms where `image_picker` supports the camera source.
bool get _cameraAvailable => kIsWeb || Platform.isAndroid || Platform.isIOS;

Future<PickedAttachment?> showAttachmentPicker(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_cameraAvailable)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Image'),
            onTap: () => Navigator.of(ctx).pop('image'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('File'),
            onTap: () => Navigator.of(ctx).pop('file'),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return null;

  if (choice == 'camera') {
    final xf = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (xf == null) return null;
    final bytes = kIsWeb
        ? await xf.readAsBytes()
        : await File(xf.path).readAsBytes();
    return PickedAttachment(
      bytes: bytes,
      fileName: xf.name,
      mimeType: xf.mimeType ?? _guessMime(xf.name, 'image'),
    );
  }

  final result = await FilePicker.platform.pickFiles(
    type: choice == 'image' ? FileType.image : FileType.any,
    withData: true,
  );
  final f = result?.files.firstOrNull;
  if (f?.bytes == null) return null;
  return PickedAttachment(
    bytes: f!.bytes!,
    fileName: f.name,
    mimeType: _guessMime(f.name, choice),
  );
}

String _guessMime(String name, String choice) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return choice == 'image' ? 'image/jpeg' : 'application/octet-stream';
}

/// Fetches [url] with the current bearer and renders bytes via
/// `Image.memory`. Used for inline image previews since the stub's file
/// endpoint requires authentication.
class AuthedImage extends RearchConsumer {
  const AuthedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final rest = use(restCapsule);
    final future = use.memo<Future<Uint8List>>(() async {
      final bytes = await rest.downloadFileBytes(url);
      return Uint8List.fromList(bytes);
    }, [url, rest]);
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (ctx, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            width: width,
            height: height,
            fit: fit,
          );
        }
        if (snap.hasError) {
          return SizedBox(
            width: width ?? 200,
            height: height ?? 200,
            child: const Center(child: Icon(Icons.broken_image)),
          );
        }
        return SizedBox(
          width: width ?? 200,
          height: height ?? 200,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

/// Convenience wrapper: renders a `flutter_chat_core` `ImageMessage`
/// bubble as a rounded [AuthedImage] with alignment matching sender.
class InlineImageBubble extends StatelessWidget {
  const InlineImageBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
  });

  final ImageMessage message;
  final bool isSentByMe;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AuthedImage(url: message.source, width: 240, height: 240),
          ),
          if (isSentByMe)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: MessageReceipt(message: message),
            ),
        ],
      ),
    );
  }
}
