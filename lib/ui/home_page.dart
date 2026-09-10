import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/push_capsule.dart';
import 'bubbles_tab.dart';
import 'call_overlay.dart';
import 'contacts_tab.dart';

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
    final (tab, setTab) = use.state<int>(0);

    const pages = [ContactsTab(), BubblesTab()];

    return Scaffold(
      appBar: AppBar(
        title: Text(tab == 0 ? 'Contacts' : 'Bubbles'),
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
                case 'online':
                case 'away':
                case 'dnd':
                  await actions.setMyPresence(v);
                case 'signout':
                  await auth.signOut();
              }
            },
            itemBuilder: (_) => const [
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
      body: Stack(
        children: [
          Positioned.fill(child: pages[tab]),
          const Align(alignment: Alignment.topCenter, child: CallOverlay()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: setTab,
        destinations: const [
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
