import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/xmpp_client.dart';
import '../state/capsules/active_thread_capsule.dart';
import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/auth_state_capsule.dart';
import '../state/capsules/bubbles_capsule.dart';
import '../state/capsules/chat_actions_capsule.dart';
import '../state/capsules/connectivity_capsule.dart';
import '../state/capsules/detail_selection_capsule.dart';
import '../state/capsules/outbox_count_capsule.dart';
import '../state/capsules/permissions_capsule.dart';
import '../state/capsules/push_capsule.dart';
import '../state/capsules/roster_capsule.dart';
import '../state/capsules/unread_capsule.dart';
import '../state/capsules/xmpp_capsule.dart';
import 'bubble_topics_page.dart';
import 'bubbles_tab.dart';
import 'call_log_page.dart';
import 'chat_page.dart';
import 'contacts_tab.dart';
import 'conversations_tab.dart';
import 'dialer_page.dart';
import 'profile_page.dart';
import 'responsive.dart';

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
    final outboxCount = use(outboxCountCapsule);
    final unread = use(unreadCapsule);
    final activeThread = use(activeThreadCapsule);
    final events = use(xmppEventsCapsule);
    final selection = use(detailSelectionCapsule);
    final rosterAsync = use(rosterCapsule);
    final roster = switch (rosterAsync) {
      AsyncData(:final data) => data,
      _ => const [],
    };
    final bubblesAsync = use(bubblesCapsule);
    final bubbleIds = switch (bubblesAsync) {
      AsyncData(:final data) => data.map((b) => b.id).toSet(),
      _ => const <String>{},
    };
    var bubbleUnread = 0;
    var recentUnread = 0;
    unread.counts.forEach((k, v) {
      if (bubbleIds.contains(k)) {
        bubbleUnread += v;
      } else {
        recentUnread += v;
      }
    });
    final (tab, setTab) = use.state<int>(0);

    // In-app snackbar toast for incoming 1:1 or MUC messages when
    // the user is NOT currently inside the target thread. Resolves ids
    // to display names via the roster (1:1 + group sender) and bubbles
    // (group room). Suppresses own carbons and empty bodies.
    use.effect(() {
      final myId = me?.id;
      if (myId == null) return null;
      final rosterNames = {for (final r in roster) r.peer.id: r.peer.display};
      final bubbleNames = <String, String>{};
      if (bubblesAsync case AsyncData(:final data)) {
        for (final b in data) {
          bubbleNames[b.id] = b.name;
        }
      }
      final scaffold = ScaffoldMessenger.of(context);
      void toast(String title, String body) {
        scaffold.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }

      final sub = events
          .where((e) => e is XmppChatMessage)
          .cast<XmppChatMessage>()
          .where((e) => e.body.isNotEmpty)
          .listen((e) {
            if (e.isGroupChat) {
              // MUC delivery: from = <senderId>@domain/res, to =
              // <bubbleId>@muc.<domain>.
              final bubbleId = _localPart(e.to);
              final senderId = _localPart(e.from);
              if (senderId == myId) return; // own group echo
              if (bubbleId.isEmpty || bubbleId == activeThread.value) return;
              final room = bubbleNames[bubbleId] ?? 'Group';
              final sender = rosterNames[senderId] ?? senderId;
              toast('$room · $sender', e.body);
            } else {
              final fromLocal = _localPart(e.from);
              if (fromLocal == myId) return; // own carbon
              if (fromLocal.isEmpty || fromLocal == activeThread.value) return;
              toast(rosterNames[fromLocal] ?? fromLocal, e.body);
            }
          });
      return sub.cancel;
    }, [events, me?.id, activeThread.value, roster, bubblesAsync]);

    const pages = [ConversationsTab(), ContactsTab(), BubblesTab()];
    const titles = ['Recent', 'Contacts', 'Bubbles'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        actions: [
          IconButton(
            tooltip: 'Phone / Dialer',
            icon: const Icon(Icons.dialpad),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const DialerPage())),
          ),
          PopupMenuButton<String>(
            icon: Badge.count(
              isLabelVisible: unread.total > 0,
              count: unread.total,
              child: CircleAvatar(
                child: Text(
                  me?.display.isNotEmpty == true
                      ? me!.display[0].toUpperCase()
                      : '?',
                ),
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
                case 'dialer':
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DialerPage()),
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
              PopupMenuItem(
                value: 'profile',
                child: _MenuRow(icon: Icons.person, label: 'My profile'),
              ),
              PopupMenuItem(
                value: 'calls',
                child: _MenuRow(icon: Icons.call, label: 'Recent calls'),
              ),
              PopupMenuItem(
                value: 'dialer',
                child: _MenuRow(icon: Icons.dialpad, label: 'Phone / Dialer'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'online',
                child: _MenuRow(
                  icon: Icons.circle,
                  iconColor: Colors.green,
                  label: 'Presence: online',
                ),
              ),
              PopupMenuItem(
                value: 'away',
                child: _MenuRow(
                  icon: Icons.circle,
                  iconColor: Colors.orange,
                  label: 'Presence: away',
                ),
              ),
              PopupMenuItem(
                value: 'dnd',
                child: _MenuRow(
                  icon: Icons.circle,
                  iconColor: Colors.red,
                  label: 'Presence: do not disturb',
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'signout',
                child: _MenuRow(icon: Icons.logout, label: 'Sign out'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!online) const _OfflineBanner(),
          if (outboxCount > 0) _OutboxBanner(count: outboxCount),
          if (permissions.anyDenied) _PermissionsBanner(state: permissions),
          Expanded(
            child: isWideLayout(context)
                ? Row(
                    children: [
                      SizedBox(width: 360, child: pages[tab]),
                      const VerticalDivider(width: 1),
                      Expanded(child: _DetailPane(selection: selection.value)),
                    ],
                  )
                : pages[tab],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: setTab,
        destinations: [
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: recentUnread > 0,
              count: recentUnread,
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge.count(
              isLabelVisible: recentUnread > 0,
              count: recentUnread,
              child: const Icon(Icons.chat_bubble),
            ),
            label: 'Recent',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: bubbleUnread > 0,
              count: bubbleUnread,
              child: const Icon(Icons.forum_outlined),
            ),
            selectedIcon: Badge.count(
              isLabelVisible: bubbleUnread > 0,
              count: bubbleUnread,
              child: const Icon(Icons.forum),
            ),
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
    final missing = state.deniedLabels.join(', ');
    final needsSettings = state.anyPermanentlyDenied;
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
                needsSettings
                    ? '$missing blocked. Enable in system settings to use calls and attachments.'
                    : '$missing denied. Calls and file attachments may not work.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (needsSettings)
              TextButton(
                onPressed: state.openSettings,
                child: const Text('Open settings'),
              )
            else
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

class _OutboxBanner extends StatelessWidget {
  const _OutboxBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.schedule_send, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? '1 message queued � will send when reconnected.'
                    : '$count messages queued � will send when reconnected.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _localPart(String jid) {
  final at = jid.indexOf('@');
  return at < 0 ? jid : jid.substring(0, at);
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: iconColor ?? Theme.of(context).colorScheme.onSurface,
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

/// Right-hand detail pane of the desktop two-pane layout — renders the
/// selected 1:1 or group chat, or a placeholder when nothing is picked.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.selection});
  final ChatSelection? selection;

  @override
  Widget build(BuildContext context) {
    return switch (selection) {
      PeerSelection(:final peer) => ChatPage(
        key: ValueKey('peer:${peer.id}'),
        peer: peer,
      ),
      BubbleSelection(:final bubble) => BubbleTopicsPage(
        key: ValueKey('bubble:${bubble.id}'),
        bubble: bubble,
      ),
      null => const _NoConversationSelected(),
    };
  }
}

class _NoConversationSelected extends StatelessWidget {
  const _NoConversationSelected();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              'Select a conversation',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
