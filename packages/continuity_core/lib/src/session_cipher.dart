import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypts relay payloads before they leave either paired device.
class SessionCipher {
  SessionCipher(Uint8List key) : _key = SecretKey(key) {
    if (key.length != 32) throw ArgumentError.value(key.length, 'key.length', 'must be 32 bytes');
  }

  final SecretKey _key;
  final _algorithm = Chacha20.poly1305Aead();

  Future<Map<String, String>> seal(Map<String, dynamic> payload) async {
    final box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: _key,
      nonce: List<int>.generate(12, (_) => Random.secure().nextInt(256)),
    );
    return {
      'ciphertext': base64UrlEncode(box.cipherText),
      'nonce': base64UrlEncode(box.nonce),
      'mac': base64UrlEncode(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> open(Map<String, dynamic> sealed) async {
    final box = SecretBox(
      base64Url.decode(sealed['ciphertext'] as String),
      nonce: base64Url.decode(sealed['nonce'] as String),
      mac: Mac(base64Url.decode(sealed['mac'] as String)),
    );
    final clear = await _algorithm.decrypt(box, secretKey: _key);
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
  }
}
