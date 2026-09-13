import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import '../state/capsules/auth_controller_capsule.dart';
import '../state/capsules/auth_state_capsule.dart';

/// Editable form over `PUT /users/:id`. Server does COALESCE
/// semantics so any field left empty is skipped and preserved.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _nick = TextEditingController();
  final _title = TextEditingController();
  final _jobTitle = TextEditingController();
  final _language = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _seeded = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _nick.dispose();
    _title.dispose();
    _jobTitle.dispose();
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RearchBuilder(
      builder: (context, use) {
        final me = use(authCapsule).me;
        final auth = use(authControllerCapsule);

        if (me != null && !_seeded) {
          _first.text = me.firstName ?? '';
          _last.text = me.lastName ?? '';
          _nick.text = me.nickName ?? '';
          _title.text = me.title ?? '';
          _jobTitle.text = me.jobTitle ?? '';
          _language.text = me.language ?? '';
          _seeded = true;
        }

        Future<void> save() async {
          setState(() {
            _error = null;
            _busy = true;
          });
          try {
            await auth.updateMe(
              firstName: _first.text.trim(),
              lastName: _last.text.trim(),
              nickName: _nick.text.trim(),
              title: _title.text.trim(),
              jobTitle: _jobTitle.text.trim(),
              language: _language.text.trim(),
            );
            if (!mounted) return;
            Navigator.of(context).pop();
          } on Object catch (e) {
            if (!mounted) return;
            setState(() => _error = e.toString());
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Edit profile'),
            actions: [
              TextButton(
                onPressed: _busy ? null : save,
                child: Text(_busy ? 'Saving…' : 'Save'),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(_first, 'First name'),
                    _field(_last, 'Last name'),
                    _field(_nick, 'Nick name'),
                    _field(_title, 'Title'),
                    _field(_jobTitle, 'Job title'),
                    _field(_language, 'Language (e.g. en, fr)'),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
