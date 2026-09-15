import 'package:flutter/material.dart';

/// Pinned XEP-0045 room subject header, borrowed from xmpp-web's
/// RoomSubject panel. Rendered only when a room subject is present.
class RoomSubjectBanner extends StatelessWidget {
  const RoomSubjectBanner({super.key, required this.subject});

  final String subject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.push_pin_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
