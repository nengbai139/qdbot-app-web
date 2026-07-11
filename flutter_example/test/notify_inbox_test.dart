import 'package:flutter_test/flutter_test.dart';
import 'package:qdbot_app_example/util/notify_inbox.dart';

void main() {
  test('inbox stable ids', () {
    expect(NotifyInbox.inboxIdForIm({'msgId': 'm1'}), 'im_m1');
    expect(NotifyInbox.inboxIdForAi({'msgId': 'a1'}), 'ai_a1');
    expect(NotifyInbox.inboxIdForSubscription(DateTime(2026, 7, 1)), 'sub_2026-07-01');
  });

  test('mergeEntries prefers server read and newer body', () {
    final local = [
      NotifyEntry(
        id: 'im_1',
        kind: 'im',
        title: 'A',
        body: 'old',
        at: DateTime(2026, 1, 1),
      ),
    ];
    final server = [
      NotifyEntry(
        id: 'im_1',
        kind: 'im',
        title: 'A',
        body: 'new',
        at: DateTime(2026, 1, 2),
        read: true,
      ),
    ];
    final merged = NotifyInbox.mergeEntries(local, server);
    expect(merged.length, 1);
    expect(merged.first.body, 'new');
    expect(merged.first.read, true);
  });

  test('mergeServerWins uses server body', () {
    final local = [NotifyEntry(id: 'im_1', kind: 'im', title: 'A', body: 'local', at: DateTime(2026, 1, 2))];
    final server = [NotifyEntry(id: 'im_1', kind: 'im', title: 'A', body: 'remote', at: DateTime(2026, 1, 1))];
    final merged = NotifyInbox.mergeServerWins(local, server);
    expect(merged.first.body, 'remote');
  });

  test('countConflicts detects read/body mismatch', () {
    final local = [NotifyEntry(id: 'x', kind: 'im', title: 't', body: 'a', at: DateTime.now())];
    final server = [NotifyEntry(id: 'x', kind: 'im', title: 't', body: 'b', at: DateTime.now(), read: true)];
    expect(NotifyInbox.countConflicts(local, server), 1);
  });
}
