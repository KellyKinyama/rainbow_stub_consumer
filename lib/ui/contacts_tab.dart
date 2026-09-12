import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../rainbow/rest_client.dart';
import '../state/capsules/presence_capsule.dart';
import '../state/capsules/rest_capsule.dart';
import '../state/capsules/roster_capsule.dart';
import '../state/models/presence.dart';
import 'chat_page.dart';
import 'phone_empty.dart';
import 'phone_row_tile.dart';
import 'phone_search_field.dart';

class ContactsTab extends RearchConsumer {
  const ContactsTab({super.key});

  static Color _presenceColor(String? show) {
    switch (show) {
      case 'chat':
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'dnd':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final rosterAsync = use(rosterCapsule);
    final presence = use(presenceCapsule);
    final rest = use(restCapsule);
    final refresher = use(rosterRefresherCapsule);
    final (query, setQuery) = use.state<String>('');
    final normalized = query.toLowerCase().trim();
    bool matches(RainbowUser u) {
      if (normalized.isEmpty) return true;
      return u.display.toLowerCase().contains(normalized) ||
          u.loginEmail.toLowerCase().contains(normalized);
    }

    Widget list;
    switch (rosterAsync) {
      case AsyncLoading<List<RosterEntry>>():
        list = const Center(child: CircularProgressIndicator());
      case AsyncError<List<RosterEntry>>(:final error):
        list = Center(child: Text('Roster failed: $error'));
      case AsyncData<List<RosterEntry>>(:final data):
        final filtered = data
            .where((e) => matches(e.peer))
            .toList(growable: false);
        if (data.isEmpty) {
          list = const PhoneNoItems(
            icon: Icons.person_add_alt_1,
            label: 'No contacts yet. Tap the + button to add one.',
          );
        } else if (filtered.isEmpty) {
          list = PhoneNoItems(
            icon: Icons.search_off,
            label: 'No match for "$query"',
          );
        } else {
          list = ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (_, i) {
              final entry = filtered[i];
              final live = entry.peer;
              final livePresence = _presenceFor(live, presence);
              final subtitle = livePresence?.status?.isNotEmpty == true
                  ? livePresence!.status!
                  : (live.presenceStatus?.isNotEmpty == true
                        ? live.presenceStatus!
                        : live.loginEmail);
              return PhoneRowTile(
                avatar: PhoneAvatar(
                  label: live.display,
                  presenceColor: _presenceColor(
                    livePresence?.show ?? live.presenceShow,
                  ),
                ),
                title: live.display,
                subtitle: subtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ChatPage(peer: live)),
                ),
              );
            },
          );
        }
    }

    return Scaffold(
      body: Column(
        children: [
          PhoneSearchField(hint: 'Search contacts', onChanged: setQuery),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                refresher.bump();
                await Future<void>.delayed(const Duration(milliseconds: 300));
              },
              child: list,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add contact',
        onPressed: () => _openAddContactSheet(context, rest, refresher),
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Future<void> _openAddContactSheet(
    BuildContext context,
    RainbowRestClient rest,
    RosterRefresher refresher,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddContactSheet(rest: rest, onAdded: refresher.bump),
    );
  }

  // Presence capsule keys by bare JID; the roster carries only user id, so
  // check both `id@domain` variants (peer JIDs and localhost/prod).
  static Presence? _presenceFor(RainbowUser u, Map<String, Presence> map) {
    for (final key in map.keys) {
      final local = key.contains('@')
          ? key.substring(0, key.indexOf('@'))
          : key;
      if (local == u.id) return map[key];
    }
    return null;
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.rest, required this.onAdded});
  final RainbowRestClient rest;
  final VoidCallback onAdded;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _controller = TextEditingController();
  List<RainbowUser> _results = const [];
  bool _searching = false;
  String? _error;
  final _adding = <String>{};
  Timer? _debounce;

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await widget.rest.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _searching = false;
      });
    }
  }

  Future<void> _add(RainbowUser u) async {
    setState(() => _adding.add(u.id));
    try {
      await widget.rest.addContact(u.id);
      widget.onAdded();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added ${u.display}')));
      setState(() => _results = _results.where((x) => x.id != u.id).toList());
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
    } finally {
      if (mounted) setState(() => _adding.remove(u.id));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add contact',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Name or email',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _search,
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_searching) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final u = _results[i];
                    final busy = _adding.contains(u.id);
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          u.display.isNotEmpty
                              ? u.display[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(u.display),
                      subtitle: Text(u.loginEmail),
                      trailing: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.person_add_alt),
                              onPressed: () => _add(u),
                            ),
                    );
                  },
                ),
              ),
              if (!_searching &&
                  _results.isEmpty &&
                  _controller.text.trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No matches'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
