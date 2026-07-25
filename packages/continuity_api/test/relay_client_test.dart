import 'dart:async';
import 'package:continuity_api/continuity_api.dart';
import 'package:test/test.dart';

void main() {
  group('RelayClient', () {
    test('InMemoryRelayClient delivers envelopes when connected', () async {
      final client = InMemoryRelayClient();
      expect(client.isConnected, isFalse);

      await client.connect();
      expect(client.isConnected, isTrue);

      final envelope = RelayEnvelope(
        version: RelayEnvelope.currentVersion,
        id: 'env-1',
        kind: RelayKind.clipboard,
        senderId: 'mac-1',
        recipientId: 'phone-1',
        sentAt: DateTime.now().toUtc(),
        payload: {'content': 'hello'},
      );

      final futureMsg = client.messages.first;
      await client.send(envelope);

      final received = await futureMsg;
      expect(received.id, equals('env-1'));
      expect(received.payload['content'], equals('hello'));

      await client.disconnect();
      expect(client.isConnected, isFalse);
    });

    test('FirebaseRelayClient passes messages and send calls', () async {
      final controller = StreamController<RelayEnvelope>.broadcast();
      RelayEnvelope? sentEnvelope;

      final client = FirebaseRelayClient(
        incomingStream: controller.stream,
        onSend: (env) async {
          sentEnvelope = env;
        },
      );

      await client.connect();
      expect(client.isConnected, isTrue);

      final envelope = RelayEnvelope(
        version: RelayEnvelope.currentVersion,
        id: 'fb-1',
        kind: RelayKind.transfer,
        senderId: 'mac-1',
        recipientId: 'phone-1',
        sentAt: DateTime.now().toUtc(),
        payload: {'action': 'offer', 'name': 'file.txt'},
      );

      final futureMsg = client.messages.first;
      controller.add(envelope);

      final received = await futureMsg;
      expect(received.id, equals('fb-1'));

      await client.send(envelope);
      expect(sentEnvelope?.id, equals('fb-1'));

      await client.disconnect();
      await controller.close();
    });
  });
}
