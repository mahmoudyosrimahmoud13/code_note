import 'package:code_note/online/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile', () {
    test('reads the API shape', () {
      final p = Profile.fromJson({
        'id': 'u1',
        'name': 'Sara Ali',
        'username': 'sara',
        'avatar_url': '',
        'is_admin': true,
        'last_seen_at': '2026-11-22T10:00:00.000Z',
      });
      expect(p.handle, '@sara');
      expect(p.initials, 'SA');
      expect(p.avatarUrl, isNull); // empty means no picture
      expect(p.isAdmin, isTrue);
      expect(p.lastSeenAt!.isUtc, isFalse); // shown in local time
    });
  });

  group('ChatMessage', () {
    test('reads and writes the same shape', () {
      final m = ChatMessage.fromJson({
        'id': 'm1',
        'seq': 42,
        'chat_id': 'c1',
        'sender_id': 'u1',
        'client_id': 'abc',
        'kind': 'block',
        'body': 'print(1)',
        'payload': {'text': 'print(1)', 'language': 'Language.python'},
        'reply_to': {'id': 'm0', 'sender_id': 'u2', 'kind': 'text', 'body': 'hi'},
        'reactions': {'u2': '👍'},
        'pinned': true,
        'edited': false,
        'deleted': false,
        'created_at': '2026-11-22T10:00:00.000Z',
      });
      expect(m.kind, MessageKind.block);
      expect(m.replyTo!.body, 'hi');
      expect(m.reactions, {'u2': '👍'});
      expect(m.preview, '‹/› print(1)');
      final again = ChatMessage.fromJson(m.toJson());
      expect(again.seq, 42);
      expect(again.replyTo!.id, 'm0');
      expect(again.kind, MessageKind.block);
    });

    test('previews', () {
      ChatMessage of(String kind, {String body = '', Map<String, dynamic>? payload, bool deleted = false}) =>
          ChatMessage.fromJson({
            'id': 'x', 'seq': 1, 'chat_id': 'c', 'kind': kind, 'body': body, 'payload': payload,
            'deleted': deleted, 'created_at': '2026-11-22T10:00:00Z',
          });
      expect(of('image').preview, '📷 Photo');
      expect(of('image', body: 'look').preview, '📷 look');
      expect(of('note', payload: {'title': 'Tips'}).preview, '📝 Tips');
      expect(of('text', body: 'x', deleted: true).preview, 'This message was deleted');
      expect(of('unknown-kind', body: 'hello').kind, MessageKind.text);
    });
  });

  group('Chat', () {
    test('who can send', () {
      Chat chat(Map<String, dynamic> extra) => Chat.fromJson({'id': 'c', 'name': 'Team', 'is_group': true, ...extra});
      expect(chat({'admin_only': true, 'my_role': 'member'}).canSend, isFalse);
      expect(chat({'admin_only': true, 'my_role': 'admin'}).canSend, isTrue);
      expect(Chat.fromJson({'id': 'd', 'name': 'Omar', 'blocked': 'me'}).canSend, isFalse);
      expect(Chat.fromJson({'id': 'd', 'name': 'Omar', 'other_user': {'id': 'u', 'name': 'x', 'is_deleted': true}}).canSend,
          isFalse);
    });

    test('details with members', () {
      final c = Chat.fromJson({
        'id': 'c',
        'name': 'Team',
        'is_group': true,
        'members': [
          {'user': {'id': 'u1', 'name': 'A'}, 'role': 'admin', 'read_seq': 5, 'delivered_seq': 7},
        ],
      });
      expect(c.members!.single.isAdmin, isTrue);
      expect(c.members!.single.withReceipt(read: 9).readSeq, 9);
    });
  });

  group('Live events', () {
    test('WebSocket events', () {
      expect(liveEventFromJson({'type': 'typing', 'chat_id': 'c', 'user_id': 'u'}), isA<TypingEvent>());
      final r = liveEventFromJson({'type': 'receipt', 'chat_id': 'c', 'user_id': 'u', 'read_seq': 3, 'delivered_seq': 4}) as ReceiptEvent;
      expect(r.deliveredSeq, 4);
      final m = liveEventFromJson({
        'type': 'message.new',
        'chat_id': 'c',
        'message': {'id': 'm', 'seq': 1, 'chat_id': 'c', 'kind': 'text', 'body': 'hi', 'created_at': '2026-11-22T10:00:00Z'},
      }) as MessageEvent;
      expect(m.isNew, isTrue);
      expect(liveEventFromJson({'type': 'sync', 'rev': 12}), isA<SyncEvent>());
      expect(liveEventFromJson({'type': 'nope'}), isNull);
    });
  });

  group('Sync', () {
    test('pull and push results', () {
      final pull = SyncPull.fromJson({
        'rev': 3,
        'latest': 5,
        'items': [
          {'kind': 'note', 'id': 'n1', 'data': {'title': 'x'}, 'deleted': false, 'rev': 3},
        ],
      });
      expect(pull.items.single.data!['title'], 'x');
      final push = SyncPushResult.fromJson({'rev': 4, 'applied': ['n1'], 'conflicts': []});
      expect(push.applied, ['n1']);
    });
  });
}
