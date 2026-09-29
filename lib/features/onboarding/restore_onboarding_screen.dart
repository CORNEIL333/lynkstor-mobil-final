import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_text_field.dart';
import '../../l10n/app_strings.dart';

class RestoreOnboardingScreen extends ConsumerStatefulWidget {
  const RestoreOnboardingScreen({super.key});

  @override
  ConsumerState<RestoreOnboardingScreen> createState() =>
      _RestoreOnboardingScreenState();
}

class _RestoreOnboardingScreenState
    extends ConsumerState<RestoreOnboardingScreen> {
  String? _path;
  Map<String, dynamic>? _meta;
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _owner = TextEditingController();
  bool _loading = false;
  bool _showSecrets = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _password.dispose();
    _pin.dispose();
    _owner.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _meta = null;
      _path = null;
    });
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      setState(
        () => _error = S.tr(
          'Impossible de lire le fichier.',
          'Unable to read the file.',
        ),
      );
      return;
    }
    try {
      final meta = await ref
          .read(restoreOnboardingServiceProvider)
          .inspect(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _meta = meta;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _restore() async {
    if (_path == null) return;
    if (_password.text.length < 8 || _pin.text.length != 4) {
      setState(
        () => _error = S.tr(
          'Mot de passe de transfert (8+) et PIN (4 chiffres) requis.',
          'Transfer password (8+) and a 4-digit PIN are required.',
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(restoreOnboardingServiceProvider)
          .restoreFromFile(
            filePath: _path!,
            password: _password.text,
            pin: _pin.text,
            ownerName: _owner.text.isEmpty ? null : _owner.text,
          );
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      setState(
        () => _success = S.tr(
          'Restauration terminée. Commerce prêt.',
          'Restore complete. Business ready.',
        ),
      );
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(
          title: Text(S.restoreData),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(
                  S.tr('Récupérez votre commerce', 'Recover your business'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  S.tr(
                    'Choisissez un fichier .kumba de transfert. Le mot de passe saisi '
                        'doit être celui choisi lors de l’export. L’intégrité est vérifiée '
                        'avant tout import.',
                    'Choose a .kumba transfer file. Enter the password selected during '
                        'export. File integrity is checked before anything is imported.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                KumbaButton(
                  label: 'Choisir un fichier .kumba',
                  icon: Icons.folder_open,
                  variant: KumbaButtonVariant.outline,
                  onPressed: _loading ? null : _pick,
                ),
                if (_meta != null) ...[
                  const SizedBox(height: 16),
                  KumbaCard(
                    color: AppColors.forestSoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_outlined,
                              color: AppColors.emerald,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              S.tr('Sauvegarde reconnue', 'Backup recognized'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${S.tr('Commerce', 'Business')} : '
                          '${_meta!['businessName']}',
                        ),
                        Text(
                          '${S.tr('Créé le', 'Created on')} : '
                          '${_meta!['createdAt']}',
                        ),
                        Text(
                          '${S.tr('Taille', 'Size')} : ${_meta!['size']} '
                          '${S.tr('o', 'bytes')}',
                        ),
                        Text(
                          '${S.tr('Empreinte', 'Checksum')} : '
                          '${(_meta!['checksum'] as String).substring(0, 16)}…',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  KumbaTextField(
                    controller: _owner,
                    label: 'Nom du propriétaire (optionnel)',
                  ),
                  const SizedBox(height: 12),
                  KumbaTextField(
                    controller: _password,
                    label: 'Mot de passe de transfert (et du nouvel appareil)',
                    obscureText: !_showSecrets,
                    prefixIcon: Icons.lock_outline_rounded,
                    suffixIcon: _showSecrets
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    onSuffixTap: () =>
                        setState(() => _showSecrets = !_showSecrets),
                  ),
                  const SizedBox(height: 12),
                  KumbaTextField(
                    controller: _pin,
                    label: 'Nouveau PIN (4 chiffres)',
                    obscureText: !_showSecrets,
                    prefixIcon: Icons.pin_outlined,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                  ),
                  const SizedBox(height: 20),
                  KumbaButton(
                    label: 'Vérifier et restaurer',
                    isLoading: _loading,
                    onPressed: _loading ? null : _restore,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _success!,
                    style: const TextStyle(color: AppColors.kpiSales),
                  ),
                ],
              ],
            ),
          ),
        ),
    );
  }
}
