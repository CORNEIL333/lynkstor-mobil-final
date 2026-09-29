import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/shared/models/subscription_info.dart';

void main() {
  test('recent active cloud subscription allows sales', () {
    final info = SubscriptionInfo(
      planName: 'PRO',
      status: 'active',
      checkedAt: DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      expiresAt: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      licenseActive: true,
      source: 'cloud',
    );

    expect(info.isVerificationStale, isFalse);
    expect(info.allowsSales, isTrue);
  });

  test('cloud verification older than seven days blocks new sales', () {
    final info = SubscriptionInfo(
      planName: 'PRO',
      status: 'active',
      checkedAt: DateTime.now()
          .subtract(const Duration(days: 8))
          .toIso8601String(),
      expiresAt: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      licenseActive: true,
      source: 'cloud',
    );

    expect(info.isVerificationStale, isTrue);
    expect(info.allowsSales, isFalse);
  });

  test('expired cloud subscription blocks sales', () {
    final info = SubscriptionInfo(
      planName: 'STARTER',
      status: 'active',
      checkedAt: DateTime.now().toIso8601String(),
      expiresAt: DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String(),
      licenseActive: true,
      source: 'cloud',
    );

    expect(info.isExpired, isTrue);
    expect(info.allowsSales, isFalse);
  });

  test('legacy local business remains available offline', () {
    const info = SubscriptionInfo(
      planName: 'LOCAL',
      status: 'local',
      licenseActive: true,
      source: 'local',
    );

    expect(info.allowsSales, isTrue);
  });

  group('S1 enforcement (requireAgentActivationCode / enforceLicense)', () {
    test('forged local source no longer grants sales when enforced', () {
      const info = SubscriptionInfo(
        planName: 'LOCAL',
        status: 'local',
        licenseActive: true,
        source: 'local',
        enforceLicense: true,
      );
      // C'est LE bypass S1 fermé : sans preuve signée, un flag local forgé ne
      // suffit plus à autoriser l'exploitation commerciale.
      expect(info.allowsSales, isFalse);
    });

    test('unknown source no longer grants sales when enforced', () {
      const info = SubscriptionInfo(
        planName: '—',
        status: 'unknown',
        licenseActive: true,
        source: 'unknown',
        enforceLicense: true,
      );
      expect(info.allowsSales, isFalse);
    });

    test('fresh cloud confirmation still allows sales when enforced', () {
      final info = SubscriptionInfo(
        planName: 'PRO',
        status: 'active',
        checkedAt: DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        expiresAt: DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
        licenseActive: true,
        source: 'cloud',
        enforceLicense: true,
      );
      expect(info.allowsSales, isTrue);
    });

    test('stale cloud confirmation is blocked when enforced', () {
      final info = SubscriptionInfo(
        planName: 'PRO',
        status: 'active',
        checkedAt: DateTime.now()
            .subtract(const Duration(days: 9))
            .toIso8601String(),
        expiresAt: DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
        licenseActive: true,
        source: 'cloud',
        enforceLicense: true,
      );
      expect(info.allowsSales, isFalse);
    });

    test('verified signed license grants offline grace even from local', () {
      const info = SubscriptionInfo(
        planName: 'PRO',
        status: 'active',
        licenseActive: true,
        source: 'local',
        enforceLicense: true,
        signedLicenseVerified: true,
      );
      // Preuve Ed25519 vérifiée => droit d'exploiter hors connexion.
      expect(info.allowsSales, isTrue);
    });

    test('verified signed license survives cloud expiry', () {
      final info = SubscriptionInfo(
        planName: 'PRO',
        status: 'expired',
        expiresAt: DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
        licenseActive: false,
        source: 'cloud',
        enforceLicense: true,
        signedLicenseVerified: true,
      );
      // La grâce est bornée par le jeton signé (déjà validée en amont) :
      // signedLicenseVerified prime sur un cache cloud périmé falsifiable.
      expect(info.allowsSales, isTrue);
    });

    test('enforcement is OFF by default (no regression for test panel)', () {
      const info = SubscriptionInfo(
        planName: 'LOCAL',
        status: 'local',
        licenseActive: true,
        source: 'local',
      );
      expect(info.enforceLicense, isFalse);
      expect(info.allowsSales, isTrue);
    });
  });
}
