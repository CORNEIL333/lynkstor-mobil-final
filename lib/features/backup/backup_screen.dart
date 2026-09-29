import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';

final _backupsProvider = FutureProvider.autoDispose<List<BackupRecord>>((
  ref,
) async {
  final business = ref.watch(sessionProvider).business;
  if (business == null) return [];
  return ref.watch(backupServiceProvider).list(business.id);
});

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _working = false;
  String? _message;

  Future<void> _create({bool transfer = false, bool cloud = false}) async {
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    final transferPassword = transfer || cloud
        ? await _askTransferPassword(confirm: true)
        : null;
    if ((transfer || cloud) && transferPassword == null) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final record = await ref
          .read(backupServiceProvider)
          .createBackup(
            businessId: business.id,
            type: cloud
                ? 'cloud'
                : transfer
                ? 'transfer'
                : 'manual',
            includeTransferKey: transfer || cloud,
            transferPassword: transferPassword,
          );
      if (cloud) {
        await ref.read(cloudBackupServiceProvider).upload(record);
      }
      setState(() {
        _message = cloud
            ? 'Sauvegarde cloud chiffrée réussie.\n'
                  'Fichier : ${record.fileName}\n'
                  'Conservez votre mot de passe : il n’est jamais envoyé au cloud.'
            : transfer
            ? 'Export transfert réussi.\nFichier : ${record.fileName}\n'
                  'Checksum : ${record.checksum.substring(0, 12)}…\n'
                  'Le fichier est protégé par votre mot de passe de transfert.'
            : 'Sauvegarde réussie.\nFichier : ${record.fileName}\n'
                  'Checksum : ${record.checksum.substring(0, 12)}…\n'
                  'Taille : ${record.sizeBytes} octets';
      });
      ref.invalidate(_backupsProvider);
    } on AppException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _restoreLatestCloud() async {
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final cloud = ref.read(cloudBackupServiceProvider);
      final backups = await cloud.list();
      if (backups.isEmpty) {
        throw const BackupException('Aucune sauvegarde cloud disponible.');
      }
      final path = await cloud.download(backups.first);
      final password = await _askTransferPassword(confirm: false);
      if (password == null) return;
      await ref
          .read(backupServiceProvider)
          .restoreBackup(
            path,
            businessId: business.id,
            transferPassword: password,
          );
      setState(() {
        _message =
            'Dernière sauvegarde cloud restaurée et vérifiée avec succès.';
      });
    } on AppException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restorePick() async {
    final business = ref.read(sessionProvider).business;
    if (business == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final meta = await ref.read(backupServiceProvider).inspectBackup(path);
      final password = meta['passwordProtected'] == true
          ? await _askTransferPassword(confirm: false)
          : null;
      if (meta['passwordProtected'] == true && password == null) {
        if (mounted) setState(() => _working = false);
        return;
      }
      await ref
          .read(backupServiceProvider)
          .restoreBackup(
            path,
            businessId: business.id,
            transferPassword: password,
          );
      setState(() {
        _message =
            'Restauration terminée.\nSource : ${meta['businessName']}\nChecksum : ${meta['checksum']}';
      });
    } on AppException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      setState(() => _working = false);
    }
  }

  Future<String?> _askTransferPassword({required bool confirm}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          String? error;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                confirm
                    ? 'Protéger l’export de transfert'
                    : 'Mot de passe de transfert',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    confirm
                        ? 'Choisissez au moins 8 caractères. Ce mot de passe sera '
                              'indispensable sur le nouveau téléphone.'
                        : 'Saisissez le mot de passe choisi lors de l’export.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: first,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: S.tr('Mot de passe', 'Password'),
                      errorText: error,
                    ),
                  ),
                  if (confirm) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: second,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: S.tr(
                          'Confirmer le mot de passe',
                          'Confirm password',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(S.cancel),
                ),
                TextButton(
                  onPressed: () {
                    if (first.text.length < 8) {
                      setDialogState(
                        () => error = 'Au moins 8 caractères sont requis.',
                      );
                      return;
                    }
                    if (confirm && first.text != second.text) {
                      setDialogState(
                        () => error = 'Les mots de passe ne correspondent pas.',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, first.text);
                  },
                  child: Text(S.continueLabel),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      first.dispose();
      second.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_backupsProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.backup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KumbaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protection de vos données',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Chaque sauvegarde produit un fichier chiffré .kumba vérifiable. '
                  'Les exports de transfert utilisent votre mot de passe et toute '
                  'altération est détectée avant restauration.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                KumbaButton(
                  label: 'Créer une sauvegarde maintenant',
                  icon: Icons.cloud_download_outlined,
                  isLoading: _working,
                  onPressed: _working ? null : () => _create(),
                ),
                const SizedBox(height: 10),
                KumbaButton(
                  label: 'Sauvegarder dans le cloud',
                  icon: Icons.cloud_upload_outlined,
                  variant: KumbaButtonVariant.secondary,
                  isLoading: _working,
                  onPressed: _working ? null : () => _create(cloud: true),
                ),
                const SizedBox(height: 10),
                KumbaButton(
                  label: 'Export transfert téléphone',
                  icon: Icons.phonelink_setup,
                  variant: KumbaButtonVariant.secondary,
                  isLoading: _working,
                  onPressed: _working ? null : () => _create(transfer: true),
                ),
                const SizedBox(height: 10),
                KumbaButton(
                  label: 'Restaurer depuis un fichier',
                  icon: Icons.restore,
                  variant: KumbaButtonVariant.outline,
                  onPressed: _working ? null : _restorePick,
                ),
                const SizedBox(height: 10),
                KumbaButton(
                  label: 'Restaurer la dernière sauvegarde cloud',
                  icon: Icons.cloud_download_outlined,
                  variant: KumbaButtonVariant.outline,
                  onPressed: _working ? null : _restoreLatestCloud,
                ),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            KumbaCard(color: AppColors.forestSoft, child: Text(_message!)),
          ],
          const SizedBox(height: 20),
          Text(
            S.tr('Historique', 'History'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () => const KumbaLoading(),
            error: (e, _) => Text(e.toString()),
            data: (list) {
              if (list.isEmpty) {
                return Text(
                  S.tr('Aucune sauvegarde pour l’instant.', 'No backup yet.'),
                );
              }
              return Column(
                children: list
                    .map(
                      (b) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          b.status == 'success'
                              ? Icons.check_circle
                              : Icons.error,
                          color: b.status == 'success'
                              ? AppColors.forest
                              : AppColors.error,
                        ),
                        title: Text(
                          b.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(b.createdAt)} · ${b.sizeBytes} o · ${b.checksum.substring(0, 8)}…',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.share_outlined),
                          onPressed: () =>
                              Share.shareXFiles([XFile(b.filePath)]),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
