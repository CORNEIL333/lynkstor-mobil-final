import 'package:local_auth/local_auth.dart';

import '../logging/app_logger.dart';

/// Biométrie locale — ne remplace jamais la validation initiale PIN/mot de passe.
class BiometricService {
  BiometricService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    try {
      final can =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!can) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (e, st) {
      AppLogger.w('Biometric availability check failed', e, st);
      return false;
    }
  }

  Future<bool> authenticate({
    String reason = 'Déverrouiller KUMBA Business',
  }) async {
    try {
      final available = await isAvailable();
      if (!available) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e, st) {
      AppLogger.w('Biometric auth failed', e, st);
      return false;
    }
  }
}
