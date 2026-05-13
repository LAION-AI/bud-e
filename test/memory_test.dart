import 'package:test/test.dart';
import 'package:school_bud_e/memory/memory_store.dart';
import 'package:school_bud_e/models/message.dart';

void main() {
  group('MemoryStore', () {
    test('stores and retrieves messages', () {
      final store = MemoryStore();
      store.addMessage(Message.user('Hello'));
      store.addMessage(Message.assistant('Hi there!'));

      expect(store.allMessages.length, 2);
      expect(store.allMessages[0].content, 'Hello');
      expect(store.allMessages[1].content, 'Hi there!');
    });

    test('contextWindow returns all when under limit', () {
      final store = MemoryStore(maxContextMessages: 10);
      for (var i = 0; i < 5; i++) {
        store.addMessage(Message.user('msg $i'));
      }
      expect(store.contextWindow().length, 5);
    });

    test('contextWindow truncates to limit', () {
      final store = MemoryStore(maxContextMessages: 3);
      for (var i = 0; i < 10; i++) {
        store.addMessage(Message.user('msg $i'));
      }
      final window = store.contextWindow();
      expect(window.length, 3);
      expect(window[0].content, 'msg 7');
      expect(window[2].content, 'msg 9');
    });

    test('clear removes all messages', () {
      final store = MemoryStore();
      store.addMessage(Message.user('test'));
      store.clear();
      expect(store.allMessages, isEmpty);
    });
  });
}
