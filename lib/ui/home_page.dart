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
import '../state/capsules/rest_capsule.dart';
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
    final rest = use(restCapsule);
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
            icon: const Icon(Icons.dialpad_rounded),
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
                child: _MenuRow(
                  icon: Icons.person_rounded,
                  label: 'My profile',
                ),
              ),
              PopupMenuItem(
                value: 'calls',
                child: _MenuRow(
                  icon: Icons.call_rounded,
                  label: 'Recent calls',
                ),
              ),
              PopupMenuItem(
                value: 'dialer',
                child: _MenuRow(
                  icon: Icons.dialpad_rounded,
                  label: 'Phone / Dialer',
                ),
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
                child: _MenuRow(icon: Icons.logout_rounded, label: 'Sign out'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!online) const _OfflineBanner(),
          if (me != null && !me.emailVerified)
            _UnverifiedEmailBanner(
              email: me.loginEmail,
              onResend: () => rest.resendVerification(me.loginEmail),
              onVerify: (code) async {
                await rest.verifyEmail(email: me.loginEmail, token: code);
                await auth.refreshMe();
              },
            ),
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
      // WhatsApp-style green 'new chat' FAB on the Chats/Recent tab
      // (narrow layout only, so it never covers the detail pane chat).
      floatingActionButton: (tab == 0 && !isWideLayout(context))
          ? FloatingActionButton(
              tooltip: 'New chat',
              onPressed: () => setTab(1),
              child: const Icon(Icons.chat_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: setTab,
        destinations: [
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: recentUnread > 0,
              count: recentUnread,
              child: const Icon(Icons.chat_outlined),
            ),
            selectedIcon: Badge.count(
              isLabelVisible: recentUnread > 0,
              count: recentUnread,
              child: const Icon(Icons.chat_rounded),
            ),
            label: 'Recent',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: bubbleUnread > 0,
              count: bubbleUnread,
              child: const Icon(Icons.groups_outlined),
            ),
            selectedIcon: Badge.count(
              isLabelVisible: bubbleUnread > 0,
              count: bubbleUnread,
              child: const Icon(Icons.groups_rounded),
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

class _UnverifiedEmailBanner extends StatelessWidget {
  const _UnverifiedEmailBanner({
    required this.email,
    required this.onResend,
    required this.onVerify,
  });

  final String email;
  final Future<String?> Function() onResend;
  final Future<void> Function(String code) onVerify;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.mark_email_unread_outlined,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Verify your email to secure your account.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _VerifyEmailDialog(
                  email: email,
                  onResend: onResend,
                  onVerify: onVerify,
                ),
              ),
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifyEmailDialog extends StatefulWidget {
  const _VerifyEmailDialog({
    required this.email,
    required this.onResend,
    required this.onVerify,
  });

  final String email;
  final Future<String?> Function() onResend;
  final Future<void> Function(String code) onVerify;

  @override
  State<_VerifyEmailDialog> createState() => _VerifyEmailDialogState();
}

class _VerifyEmailDialogState extends State<_VerifyEmailDialog> {
  final _code = TextEditingController();
  String? _error;
  String? _devHint;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await widget.onResend();
      if (!mounted) return;
      setState(() {
        _devHint = code;
        if (code != null) _code.text = code;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onVerify(code);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email verified ✓')));
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify your email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter the 6-digit code sent to ${widget.email}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Verification code'),
            onSubmitted: (_) => _verify(),
          ),
          if (_devHint != null) ...[
            const SizedBox(height: 8),
            Text(
              'Dev code: $_devHint',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Resend'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(_busy ? '…' : 'Verify'),
        ),
      ],
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
