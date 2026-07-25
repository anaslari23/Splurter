import 'dart:typed_data';

import 'package:continuity_core/continuity_core.dart';
import 'package:test/test.dart';

void main() {
  test('relay envelope has a stable round trip', () {
    final message = RelayEnvelope(
      version: RelayEnvelope.currentVersion,
      id: 'message-1',
      kind: RelayKind.clipboard,
      senderId: 'android',
      recipientId: 'mac',
      sentAt: DateTime.utc(2026),
      payload: {'text': 'hello'},
    );
    expect(RelayEnvelope.decode(message.encode()).payload['text'], 'hello');
  });

  test('session cipher rejects a modified payload', () async {
    final cipher = SessionCipher(Uint8List(32));
    final sealed = await cipher.seal({'text': 'private'});
    expect(await cipher.open(sealed), {'text': 'private'});
    sealed['mac'] = 'AAAAAAAAAAAAAAAAAAAAAA';
    await expectLater(cipher.open(sealed), throwsA(anything));
  });

  test('remote commands validate their required data', () {
    expect(const RemoteControlCommand('tap', x: 1, y: 2).isValid, isTrue);
    expect(const RemoteControlCommand('text').isValid, isFalse);
    expect(const RemoteControlCommand('launchMissiles').isValid, isFalse);
  });
}
