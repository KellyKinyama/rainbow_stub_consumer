import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/rainbow_session.dart';
import 'bubbles_tab.dart';
import 'contacts_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<RainbowSession>().me;
    final pages = const [ContactsTab(), BubblesTab()];
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Contacts' : 'Bubbles'),
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
              final s = context.read<RainbowSession>();
              switch (v) {
                case 'online':
                case 'away':
                case 'dnd':
                  await s.setMyPresence(v);
                case 'signout':
                  await s.signOut();
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
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
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
