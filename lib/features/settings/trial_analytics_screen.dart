import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/errors/user_error_message.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_format.dart';
import '../../design_system/components/kumba_button.dart';
import '../../design_system/components/kumba_card.dart';
import '../../design_system/components/kumba_states.dart';
import '../../l10n/app_strings.dart';
import '../../shared/services/analytics_service.dart';

final _trialSnapshotProvider = FutureProvider.autoDispose<TrialSnapshot>((ref) {
  return ref.watch(analyticsServiceProvider).captureSnapshot(persist: false);
});

class TrialAnalyticsScreen extends ConsumerStatefulWidget {
  const TrialAnalyticsScreen({super.key});

  @override
  ConsumerState<TrialAnalyticsScreen> createState() =>
      _TrialAnalyticsScreenState();
}

class _TrialAnalyticsScreenState extends ConsumerState<TrialAnalyticsScreen> {
  bool _sending = false;
  bool _sharing = false;
  bool _writingFolder = false;
  String? _message;
  String? _folderPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final existing = ref.read(analyticsServiceProvider).lastFolder;
      if (existing != null && mounted) {
        setState(() {
          _folderPath = existing.publicFolderPath ?? existing.folderPath;
        });
      }
      await _writeFolder();
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final ok = await ref.read(analyticsServiceProvider).flush(force: true);
      ref.invalidate(_trialSnapshotProvider);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = ok
            ? S.tr('Données envoyées vers le Drive.', 'Data sent to Drive.')
            : S.tr(
                'Envoi impossible pour le moment. Les données restent sur cet appareil.',
                'Could not send right now. Data stays on this device.',
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Envoi impossible pour le moment.',
            'Could not send right now.',
          ),
        );
      });
    }
  }

  Future<void> _writeFolder() async {
    setState(() {
      _writingFolder = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(analyticsServiceProvider)
          .persistToDeviceFolder(force: true);
      if (!mounted) return;
      setState(() {
        _writingFolder = false;
        _folderPath = result?.publicFolderPath ?? result?.folderPath;
        _message = _folderPath == null
            ? S.tr(
                'Dossier introuvable pour le moment.',
                'Folder could not be created right now.',
              )
            : S.tr(
                'Dossier mis à jour : $_folderPath',
                'Folder updated: $_folderPath',
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _writingFolder = false;
        _message = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Impossible d’écrire le dossier.',
            'Could not write the folder.',
          ),
        );
      });
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await ref.read(analyticsServiceProvider).shareExport();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = userFacingErrorMessage(
          error,
          fallback: S.tr(
            'Export impossible pour le moment.',
            'Could not export right now.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_trialSnapshotProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: Text(S.tr('Données du test', 'Test data'))),
      body: async.when(
        loading: () => const KumbaLoading(),
        error: (e, _) => KumbaErrorState(message: e.toString()),
        data: (snap) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                S.tr(
                  'L’app crée un dossier Lynkstor sur ce téléphone (Documents ou Téléchargements) avec les JSON/CSV du test. Les envois remplissent aussi le tableur Drive. Aucun nom, téléphone ou PIN.\n${AppConfig.analyticsDashboardUrl}',
                  'The app creates a Lynkstor folder on this phone (Documents or Downloads) with the trial JSON/CSV files. Sends also fill the Drive spreadsheet. No name, phone or PIN.\n${AppConfig.analyticsDashboardUrl}',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              KumbaCard(
                child: Column(
                  children: [
                    _row(S.tr('Ventes', 'Sales'), '${snap.salesCount}'),
                    _row(
                      S.tr('Chiffre d’affaires', 'Turnover'),
                      MoneyFormat.format(snap.soldFcfa),
                    ),
                    _row(
                      S.tr('Produits activés', 'Activated products'),
                      '${snap.catalogActivatedCount}',
                    ),
                    _row(
                      S.tr('Produits au catalogue', 'Catalog products'),
                      '${snap.productsCount}',
                    ),
                    _row(
                      S.tr('Clients', 'Customers'),
                      '${snap.customersCount}',
                    ),
                    _row(
                      S.tr('Jours d’ouverture', 'Open days'),
                      '${snap.openDays}',
                    ),
                    _row(
                      S.tr('Événements en attente', 'Pending events'),
                      '${snap.pendingCount}',
                    ),
                    _row(
                      S.tr('Événements enregistrés', 'Recorded events'),
                      '${snap.eventCount}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              KumbaButton(
                label: S.tr(
                  'Mettre à jour le dossier local',
                  'Update local folder',
                ),
                icon: Icons.folder_outlined,
                isLoading: _writingFolder,
                onPressed: _writingFolder ? null : _writeFolder,
              ),
              const SizedBox(height: 10),
              KumbaButton(
                label: S.tr('Envoyer les données du test', 'Send test data'),
                icon: Icons.cloud_upload_outlined,
                variant: KumbaButtonVariant.outline,
                isLoading: _sending,
                onPressed: _sending ? null : _send,
              ),
              const SizedBox(height: 10),
              KumbaButton(
                label: S.tr('Exporter le fichier', 'Export file'),
                icon: Icons.ios_share_rounded,
                variant: KumbaButtonVariant.outline,
                isLoading: _sharing,
                onPressed: _sharing ? null : _share,
              ),
              if (_folderPath != null) ...[
                const SizedBox(height: 12),
                Text(
                  _folderPath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(_message!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
