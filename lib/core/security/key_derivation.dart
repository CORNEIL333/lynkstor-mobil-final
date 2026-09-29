import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Uint8List derivePbkdf2Sha256({
  required String password,
  required List<int> salt,
  int iterations = 120000,
  int length = 32,
}) {
  final passwordBytes = utf8.encode(password);
  final hmac = Hmac(sha256, passwordBytes);
  final result = <int>[];
  var blockIndex = 1;

  while (result.length < length) {
    final block = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..buffer.asByteData().setUint32(salt.length, blockIndex);
    var u = hmac.convert(block).bytes;
    final output = List<int>.from(u);
    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var index = 0; index < output.length; index++) {
        output[index] ^= u[index];
      }
    }
    result.addAll(output);
    blockIndex++;
  }

  return Uint8List.fromList(result.take(length).toList());
}

bool constantTimeBytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}
