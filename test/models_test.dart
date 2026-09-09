import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';

void main() {
  test('RainbowUser.fromJson parses displayName + presence', () {
    final u = RainbowUser.fromJson(<String, dynamic>{
      'id': '6aa15562d95368e7be11c8d4',
      'loginEmail': 'alice@rainbow-stub.local',
      'firstName': 'Alice',
      'lastName': 'Sample',
      'displayName': 'Alice Sample',
      'presence': {'show': 'away', 'status': 'lunch'},
    });
    expect(u.id, '6aa15562d95368e7be11c8d4');
    expect(u.display, 'Alice Sample');
    expect(u.presenceShow, 'away');
    expect(u.presenceStatus, 'lunch');
  });

  test('RosterEntry parses peerUser subtree', () {
    final e = RosterEntry.fromJson(<String, dynamic>{
      'userId': 'a1',
      'peerId': 'b1',
      'peerUser': {
        'id': 'b1',
        'loginEmail': 'bob@rainbow-stub.local',
        'firstName': 'Bob',
        'lastName': 'Marley',
      },
      'status': 'accepted',
    });
    expect(e.peer.id, 'b1');
    expect(e.peer.display, 'Bob Marley');
    expect(e.status, 'accepted');
  });

  test('RainbowBubble parses users list', () {
    final b = RainbowBubble.fromJson(<String, dynamic>{
      'id': 'r1',
      'name': 'Team',
      'topic': 'standup',
      'users': [
        {'userId': 'a1', 'privilege': 'owner', 'status': 'accepted'},
        {'userId': 'b1', 'privilege': 'user', 'status': 'invited'},
      ],
    });
    expect(b.id, 'r1');
    expect(b.members, hasLength(2));
    expect(b.members.first.role, 'owner');
    expect(b.members.last.status, 'invited');
  });
}
