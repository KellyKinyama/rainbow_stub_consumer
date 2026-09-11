import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/connectivity_capsule.dart';
import '../state/capsules/permissions_capsule.dart';
import '../state/capsules/push_capsule.dart';
import 'bubbles_tab.dart';
import 'call_log_page.dart';
import 'contacts_tab.dart';
import 'conversations_tab.dart';
import 'profile_page.dart';

class HomePage extends RearchConsumer {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final auth = use(authControllerCapsule);
    final actions = use(chatActionsCapsule);
    final me = use(authCapsule).me;
    // Register a fake push token as a side-effect on login. Result
    // ignored — the capsule handles retries + logout deregister.
    use(pushCapsule);
    final permissions = use(permissionsCapsule);
    final online = use(connectivityCapsule);
    final (tab, setTab) = use.state<int>(0);

    const pages = [ConversationsTab(), ContactsTab(), BubblesTab()];
    const titles = ['Recent', 'Contacts', 'Bubbles'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              child: Text(
                me?.display.isNotEmpty == true
                    ? me!.display[0].toUpperCase()
                    : '?',
              ),
            ),
            onSelected: (v) async {
              switch (v) {
                case 'profile':
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfilePage(),
                    ),
                  );
                case 'calls':
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CallLogPage(),
                    ),
                  );
                case 'online':
                case 'away':
                case 'dnd':
                  await actions.setMyPresence(v);
                case 'signout':
                  await auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('My profile')),
              PopupMenuItem(value: 'calls', child: Text('Recent calls')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'online', child: Text('Presence: online')),
              PopupMenuItem(value: 'away', child: Text('Presence: away')),
              PopupMenuItem(
                value: 'dnd',
                child: Text('Presence: do not disturb'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: permissions.anyDenied
          ? Column(
              children: [
                if (!online) const _OfflineBanner(),
                _PermissionsBanner(state: permissions),
                Expanded(child: pages[tab]),
              ],
            )
          : Column(
              children: [
                if (!online) const _OfflineBanner(),
                Expanded(child: pages[tab]),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: setTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Recent',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Bubbles',
          ),
        ],
      ),
    );
  }
}

class _PermissionsBanner extends StatelessWidget {
  const _PermissionsBanner({required this.state});
  final PermissionsState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Some permissions were denied. Calls and file attachments may not work.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: state.ask, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.wifi_off, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You are offline. Messages will send when the connection returns.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


