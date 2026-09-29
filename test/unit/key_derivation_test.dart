import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/security/key_derivation.dart';

void main() {
  test('PBKDF2-SHA256 is deterministic and password-sensitive', () {
    final first = derivePbkdf2Sha256(
      password: 'mot-de-passe-solide',
      salt: List<int>.generate(16, (index) => index),
      iterations: 10000,
    );
    final same = derivePbkdf2Sha256(
      password: 'mot-de-passe-solide',
      salt: List<int>.generate(16, (index) => index),
      iterations: 10000,
    );
    final different = derivePbkdf2Sha256(
      password: 'autre-mot-de-passe',
      salt: List<int>.generate(16, (index) => index),
      iterations: 10000,
    );

    expect(first, hasLength(32));
    expect(constantTimeBytesEqual(first, same), isTrue);
    expect(constantTimeBytesEqual(first, different), isFalse);
  });

  test('constant-time comparison rejects different lengths', () {
    expect(constantTimeBytesEqual([1, 2], [1, 2, 0]), isFalse);
  });
}
