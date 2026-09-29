import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/user_error_message.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../design_system/components/lk_overlay.dart';
import '../../l10n/app_strings.dart';

/// Verrouillage PIN — design premium (sans flutter_animate pour stabilité Element).
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  String? _error;
  int _attempts = 0;
  bool _loading = false;
  bool _bioTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tryBiometric(automatic: true),
    );
  }

  Future<void> _tryBiometric({bool automatic = false}) async {
    if (_loading || (automatic && _bioTried)) return;
    if (automatic) _bioTried = true;
    try {
      final session = ref.read(sessionProvider);
      if (!session.biometricEnabled) return;
      final ok = await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Déverrouiller ${S.appName}');
      if (!ok || !mounted) return;
      final opened = await ref
          .read(sessionServiceProvider)
          .openSessionAfterBiometric();
      if (!opened) {
        if (!mounted) return;
        setState(() {
          _error = S.tr(
            'La session locale est incomplète. Relancez l’activation ou restaurez une sauvegarde.',
            'The local session is incomplete. Activate again or restore a backup.',
          );
        });
        return;
      }
      final secure = ref.read(secureStorageProvider);
      final endpoint = await secure.getCloudSyncEndpoint();
      final token = await secure.getCloudSyncToken();
      final businessId = await secure.getCurrentBusinessId();
      final deviceId = await secure.getDeviceId();
      if (endpoint != null &&
          endpoint.isNotEmpty &&
          token != null &&
          token.isNotEmpty) {
        await ref
            .read(syncEngineProvider)
            .start(
              endpoint: endpoint,
              authToken: token,
              businessId: businessId,
              deviceId: deviceId,
            );
      }
      if (!mounted) return;
      await ref.read(sessionProvider.notifier).refresh();
    } catch (error, stack) {
      AppLogger.e('Biometric unlock failed', error, stack);
      if (!mounted) return;
      setState(() {
        _error = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Déverrouillage biométrique indisponible. Utilisez votre PIN.',
            'Biometric unlock is unavailable. Use your PIN.',
          ),
        );
      });
    }
  }

  Future<void> _submit() async {
    if (_pin.length != 4 || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await ref.read(sessionServiceProvider).loginWithPin(_pin);
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        final secure = ref.read(secureStorageProvider);
        final endpoint = await secure.getCloudSyncEndpoint();
        final token = await secure.getCloudSyncToken();
        final businessId = await secure.getCurrentBusinessId();
        final deviceId = await secure.getDeviceId();
        if (endpoint != null &&
            endpoint.isNotEmpty &&
            token != null &&
            token.isNotEmpty) {
          await ref
              .read(syncEngineProvider)
              .start(
                endpoint: endpoint,
                authToken: token,
                businessId: businessId,
                deviceId: deviceId,
              );
        }
        if (!mounted) return;
        await ref.read(sessionProvider.notifier).refresh();
        if (!mounted) return;
        await ref.read(sessionProvider.notifier).refreshSubscription();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _attempts++;
          _pin = '';
          _error = _attempts >= 5
              ? 'Trop de tentatives. Restaurez depuis une sauvegarde de transfert si le PIN est perdu.'
              : '${S.wrongPin}. $_attempts/5';
        });
      }
    } catch (error, stack) {
      AppLogger.e('PIN unlock failed', error, stack);
      if (!mounted) return;
      setState(() {
        _pin = '';
        _error = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Le déverrouillage a échoué. Fermez puis rouvrez l’application et réessayez.',
            'Unlock failed. Close and reopen the application, then try again.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onKey(String digit) {
    if (_pin.length >= 4 || _loading) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(sessionProvider.select((s) => s.business));
    final bio = ref.watch(sessionProvider.select((s) => s.biometricEnabled));

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/lock_ledger.webp',
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.42),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xF00A5CF6)),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(
                  height: 176,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.72),
                              width: 1.2,
                            ),
                            image: const DecorationImage(
                              image: AssetImage(
                                'assets/images/ic_launcher.png',
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.tr('Accès sécurisé', 'Secure access'),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: AppColors.skyMist,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                business?.name ?? 'Commerce local',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppSpacing.radiusXxl),
                      ),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
                      child: Column(
                        children: [
                          Text(
                            S.enterPin,
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<List<String?>>(
                            future: Future.wait([
                              ref
                                  .read(secureStorageProvider)
                                  .getCloudSyncEndpoint(),
                              ref
                                  .read(secureStorageProvider)
                                  .getCloudSyncToken(),
                            ]),
                            builder: (context, snap) {
                              final ep =
                                  snap.data != null && snap.data!.isNotEmpty
                                  ? snap.data![0]
                                  : null;
                              final tok =
                                  snap.data != null && snap.data!.length > 1
                                  ? snap.data![1]
                                  : null;
                              final linked =
                                  ep != null &&
                                  ep.isNotEmpty &&
                                  tok != null &&
                                  tok.isNotEmpty;
                              final isDemo = business?.isDemo == true;
                              final label = isDemo
                                  ? S.tr('Démonstration locale', 'Local demo')
                                  : linked
                                  ? S.tr(
                                      'Commerce synchronisé',
                                      'Synced business',
                                    )
                                  : S.tr(
                                      'Disponible hors ligne',
                                      'Offline ready',
                                    );
                              final color = isDemo
                                  ? AppColors.sahelGold
                                  : linked
                                  ? AppColors.emerald
                                  : AppColors.onSurfaceVariant;

                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    label,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: color),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (i) {
                              final filled = i < _pin.length;
                              return AnimatedContainer(
                                duration: AppMotion.fast,
                                curve: AppMotion.easeOut,
                                width: filled ? 14 : 12,
                                height: filled ? 14 : 12,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: filled
                                      ? AppColors.primary
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: filled
                                        ? AppColors.primary
                                        : AppColors.outlineVariant,
                                    width: 1.8,
                                  ),
                                ),
                              );
                            }),
                          ),
                          if (_loading) ...[
                            const SizedBox(height: 14),
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.errorSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          if (bio) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _tryBiometric,
                              icon: const Icon(Icons.fingerprint_rounded),
                              label: Text(
                                S.tr('Utiliser la biométrie', 'Use biometrics'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _pad(),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              showLkToast(
                                context,
                                'PIN oublié : utilisez une sauvegarde de transfert (.kumba) après réinstallation.',
                                tone: LkToastTone.info,
                                icon: Icons.info_outline,
                              );
                            },
                            child: Text(
                              S.tr('PIN oublié ?', 'Forgot PIN?'),
                              style: const TextStyle(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        childAspectRatio: 1.42,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          return Material(
            color: k == '⌫'
                ? Colors.transparent
                : AppColors.surfaceBright.withValues(alpha: 0.98),
            shape: CircleBorder(
              side: k == '⌫'
                  ? BorderSide.none
                  : BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      width: 1,
                    ),
            ),
            elevation: k == '⌫' ? 0 : 1.5,
            shadowColor: AppColors.primary.withValues(alpha: 0.18),
            child: InkWell(
              onTap: () {
                if (k == '⌫') {
                  _backspace();
                } else {
                  _onKey(k);
                }
              },
              customBorder: const CircleBorder(),
              child: Center(
                child: k == '⌫'
                    ? Icon(
                        Icons.backspace_outlined,
                        color: AppColors.onSurfaceVariant,
                        size: 22,
                      )
                    : Text(
                        k,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                              fontSize: 22,
                            ),
                      ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
