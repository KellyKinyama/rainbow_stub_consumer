import 'package:flutter/material.dart';

import '../rainbow/models.dart';

/// Opens a bottom sheet listing roster contacts that aren't already
/// bubble members, returning the chosen [RainbowUser] or null.
Future<RainbowUser?> showBubbleContactPicker(
  BuildContext context, {
  required List<RosterEntry> roster,
  required List<BubbleMember> alreadyMembers,
}) async {
  final existing = alreadyMembers.map((m) => m.userId).toSet();
  final options = roster
      .where((r) => !existing.contains(r.peer.id))
      .toList(growable: false);
  if (options.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Everyone in your roster is already here')),
    );
    return null;
  }
  return showModalBottomSheet<RainbowUser>(
    context: context,
    showDragHandle: true,
    builder: (bc) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final r in options)
            ListTile(
              leading: CircleAvatar(
                child: Text(r.peer.display.characters.first.toUpperCase()),
              ),
              title: Text(r.peer.display),
              subtitle: Text(r.peer.loginEmail),
              onTap: () => Navigator.of(bc).pop(r.peer),
            ),
        ],
      ),
    ),
  );
}
