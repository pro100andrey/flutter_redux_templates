import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:sembast/sembast.dart';

Uint8List _generateEncryptPassword(String password) {
  final utf8Password = utf8.encode(password);
  final md5Password = md5.convert(utf8Password);
  final blob = Uint8List.fromList(md5Password.bytes);
  assert(blob.length == 16, 'Invalid password length');

  return blob;
}

final _random = () {
  try {
    // Try secure
    return Random.secure();
  } on Object catch (_) {
    return Random();
  }
}();

/// Random bytes generator
Uint8List _randBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => _random.nextInt(256)));

/// Salsa20 based encoder
class _EncryptEncoder extends Converter<Object?, String> {
  _EncryptEncoder(this.salsa20);
  final Salsa20 salsa20;

  @override
  String convert(Object? input) {
    // Generate random initial value
    final iv = _randBytes(8);
    final ivEncoded = base64.encode(iv);
    assert(ivEncoded.length == 12, 'Invalid IV length');

    // Encode the input value
    final encoded = Encrypter(
      salsa20,
    ).encrypt(json.encode(input), iv: IV(iv)).base64;

    // Prepend the initial value
    return '$ivEncoded$encoded';
  }
}

/// Salsa20 based decoder
class _EncryptDecoder extends Converter<String, Object?> {
  _EncryptDecoder(this.salsa20);
  final Salsa20 salsa20;

  @override
  dynamic convert(String input) {
    // Read the initial value that was prepended
    assert(input.length >= 12, 'Invalid IV length');
    final iv = base64.decode(input.substring(0, 12));

    // Extract the real input
    final sub = input.substring(12);

    // Decode the input
    final decoded = json.decode(Encrypter(salsa20).decrypt64(sub, iv: IV(iv)));
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    return decoded;
  }
}

/// Salsa20 based Codec
class _EncryptCodec extends Codec<Object?, String> {
  _EncryptCodec(Uint8List passwordBytes) {
    final salsa20 = Salsa20(Key(passwordBytes));
    _encoder = _EncryptEncoder(salsa20);
    _decoder = _EncryptDecoder(salsa20);
  }
  late _EncryptEncoder _encoder;
  late _EncryptDecoder _decoder;

  @override
  Converter<String, Object?> get decoder => _decoder;

  @override
  Converter<Object?, String> get encoder => _encoder;
}

/// Our plain text signature
const _encryptCodecSignature = 'encrypt';

/// Create a codec to use to open a database with encrypted stored data.
///
/// Hash (md5) of the password is used (but never stored) as a key to encrypt
/// the data using the Salsa20 algorithm with a random (8 bytes) initial value
///
/// This is just used as a demonstration and should not be considered as a
/// reference since its implementation (and storage format) might change.
///
/// No performance metrics has been made to check whether this is a viable
/// solution for big databases.
///
/// The usage is then
///
/// ```dart
/// // Initialize the encryption codec with a user password
/// var codec = getEncryptSembastCodec(password: '[your_user_password]');
/// // Open the database with the codec
/// Database db = await factory.openDatabase(dbPath, codec: codec);
///
/// // ...your database is ready to use
/// ```
SembastCodec getEncryptSembastCodec({required String password}) => SembastCodec(
  signature: _encryptCodecSignature,
  codec: _EncryptCodec(_generateEncryptPassword(password)),
);

/// Wrap a factory to always use the codec
class EncryptedDatabaseFactory implements DatabaseFactory {
  EncryptedDatabaseFactory({
    required this.databaseFactory,
    required String password,
  }) {
    codec = getEncryptSembastCodec(password: password);
  }
  final DatabaseFactory databaseFactory;
  late final SembastCodec codec;

  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactory.deleteDatabase(path);

  @override
  bool get hasStorage => databaseFactory.hasStorage;

  /// To use with codec, null
  @override
  Future<Database> openDatabase(
    String path, {
    int? version,
    OnVersionChangedFunction? onVersionChanged,
    DatabaseMode? mode,
    SembastCodec? codec,
  }) {
    assert(codec == null, 'Codec must be null');
    return databaseFactory.openDatabase(
      path,
      version: version,
      onVersionChanged: onVersionChanged,
      mode: mode,
      codec: this.codec,
    );
  }

  @override
  Future<bool> databaseExists(String path) =>
      databaseFactory.databaseExists(path);
}
