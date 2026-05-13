import 'package:test/test.dart';
import 'package:school_bud_e/models/message.dart';
import 'package:school_bud_e/models/conversation.dart';

void main() {
  group('Message', () {
    test('user message creates correctly', () {
      final m = Message.user('Hello');
      expect(m.role, MessageRole.user);
      expect(m.content, 'Hello');
      expect(m.id, isNotEmpty);
    });

    test('assistant message creates correctly', () {
      final m = Message.assistant('Response');
      expect(m.role, MessageRole.assistant);
      expect(m.content, 'Response');
    });

    test('toApiMap returns correct format', () {
      final m = Message.user('test');
      final map = m.toApiMap();
      expect(map['role'], 'user');
      expect(map['content'], 'test');
    });

    test('system message toApiMap', () {
      final m = Message.system('You are helpful.');
      final map = m.toApiMap();
      expect(map['role'], 'system');
    });
  });

  group('Conversation', () {
    test('autoTitle takes first user message', () {
      final conv = Conversation(id: '1');
      conv.messages.add(Message.system('sys prompt'));
      conv.messages.add(Message.user('What is photosynthesis?'));
      conv.autoTitle();
      expect(conv.title, 'What is photosynthesis?');
    });

    test('autoTitle truncates long messages', () {
      final conv = Conversation(id: '1');
      conv.messages.add(Message.user('A' * 100));
      conv.autoTitle();
      expect(conv.title.length, 50);
      expect(conv.title, endsWith('...'));
    });
  });
}
