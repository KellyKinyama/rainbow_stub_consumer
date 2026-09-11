import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import 'auth_state_capsule.dart';
import 'rest_capsule.dart';

/// Call-history capsule. Fires a fresh `GET /users/:id/calllogs` each
/// time it's requested, hydrating from the server. The consumer can
/// trigger a refresh by re-reading (the family capsule setup below
/// gives us a `refresh` callback).
class CallLogController {
  const CallLogController({
    required this.entries,
    required this.refresh,
    required this.delete,
    this.loading = false,
    this.error,
  });

  final AsyncValue<List<CallLogEntry>> entries;
  final Future<void> Function() refresh;
  final Future<void> Function(String id) delete;
  final bool loading;
  final Object? error;
}

CallLogController callLogsCapsule(CapsuleHandle use) {
  final rest = use(restCapsule);
  final me = use(authCapsule).me;
  final slot = use.data<AsyncValue<List<CallLogEntry>>>(
    const AsyncLoading<List<CallLogEntry>>(None()),
  );

  Option<List<CallLogEntry>> previousOf(AsyncValue<List<CallLogEntry>> v) =>
      switch (v) {
        AsyncData<List<CallLogEntry>>(:final data) => Some(data),
        AsyncLoading<List<CallLogEntry>>(:final previousData) => previousData,
        AsyncError<List<CallLogEntry>>(:final previousData) => previousData,
      };

  Future<void> load() async {
    if (me == null) {
      slot.value = const AsyncData<List<CallLogEntry>>(<CallLogEntry>[]);
      return;
    }
    slot.value = AsyncLoading<List<CallLogEntry>>(previousOf(slot.value));
    try {
      final list = await rest.listCallLogs(userId: me.id);
      slot.value = AsyncData<List<CallLogEntry>>(list);
    } on Object catch (e, s) {
      slot.value = AsyncError<List<CallLogEntry>>(e, s, previousOf(slot.value));
    }
  }

  Future<void> deleteOne(String id) async {
    if (me == null) return;
    await rest.deleteCallLog(userId: me.id, id: id);
    final current = slot.value;
    if (current is AsyncData<List<CallLogEntry>>) {
      slot.value = AsyncData<List<CallLogEntry>>(
        current.data.where((e) => e.id != id).toList(growable: false),
      );
    }
  }

  use.effect(() {
    load();
    return null;
  }, [me?.id]);

  return CallLogController(
    entries: slot.value,
    refresh: load,
    delete: deleteOne,
    loading: slot.value is AsyncLoading,
  );
}
