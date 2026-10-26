import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Encrypts the LMS password and session cookies before they go into MySQL:
/// AES-256-GCM, stored as base64 of 12-byte IV + ciphertext + 16-byte tag.
/// The key is a file (/etc/tuitmate/secret.key, base64 of 32 bytes) readable
/// only by the service, never stored in the database.
class Vault {
  Vault(List<int> key) : _key = SecretKey(key) {
    if (key.length != 32) throw ArgumentError('the key must be 32 bytes');
  }

  final SecretKey _key;
  static final _aes = AesGcm.with256bits();

  static Vault fromFile(String path) => Vault(base64.decode(File(path).readAsStringSync().trim()));

  /// [context] is bound to the ciphertext (e.g. "password:1"), so a value
  /// copied into another row or column does not decrypt.
  Future<String> seal(String plain, String context) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: _key, aad: utf8.encode(context));
    return base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> open(String sealed, String context) async {
    final b = base64.decode(sealed);
    if (b.length < 28) throw const FormatException('sealed value too short');
    final plain = await _aes.decrypt(
      SecretBox(b.sublist(12, b.length - 16), nonce: b.sublist(0, 12), mac: Mac(b.sublist(b.length - 16))),
      secretKey: _key,
      aad: utf8.encode(context),
    );
    return utf8.decode(plain);
  }
}
