import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/auth_state_capsule.dart';
import 'profile_edit_page.dart';

/// Read-only view of the signed-in user's profile. Tapping "Edit"
/// pushes [ProfileEditPage].
class ProfilePage extends RearchConsumer {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final me = use(authCapsule).me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => use(authControllerCapsule).refreshMe(),
          ),
        ],
      ),
      body: me == null
          ? const Center(child: Text('Not signed in.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      _AvatarBubble(user: me),
                      const SizedBox(height: 12),
                      Text(
                        me.display,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (me.jobTitle?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          me.jobTitle!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Card(
                        child: Column(
                          children: [
                            _row(context, 'Email', me.loginEmail),
                            _row(context, 'First name', me.firstName),
                            _row(context, 'Last name', me.lastName),
                            _row(context, 'Nick name', me.nickName),
                            _row(context, 'Title', me.title),
                            _row(context, 'Job title', me.jobTitle),
                            _row(context, 'Language', me.language),
                            _row(context, 'Presence', me.presenceShow),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit profile'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ProfileEditPage(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  static Widget _row(BuildContext context, String label, String? value) {
    return ListTile(
      dense: true,
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(
        (value == null || value.isEmpty) ? '—' : value,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.user});
  final RainbowUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = user.display.isEmpty
        ? '?'
        : user.display.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 42,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
