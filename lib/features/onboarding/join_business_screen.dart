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

class JoinBusinessScreen extends ConsumerStatefulWidget {
  const JoinBusinessScreen({super.key});

  @override
  ConsumerState<JoinBusinessScreen> createState() => _JoinBusinessScreenState();
}

class _JoinBusinessScreenState extends ConsumerState<JoinBusinessScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  String? _businessName;
  String? _role;
  bool _loading = false;
  String? _error;
  int _step = 0;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _peek() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(
        () => _error = S.tr(
          'Saisissez un code d’invitation valide.',
          'Enter a valid invitation code.',
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await ref
          .read(invitationServiceProvider)
          .peekInvitation(code);
      if (!mounted) return;
      setState(() {
        _code.text = code;
        _businessName = info.business.name;
        _role = info.role;
        _step = 1;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    if (_name.text.trim().isEmpty || _pin.text.length != 4) {
      setState(
        () => _error = S.tr(
          'Nom et PIN (4 chiffres) obligatoires.',
          'Name and 4-digit PIN are required.',
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
          .read(invitationServiceProvider)
          .acceptInvitation(
            code: _code.text,
            fullName: _name.text,
            pin: _pin.text,
            phone: _phone.text.isEmpty ? null : _phone.text,
          );
      await ref.read(sessionProvider.notifier).refresh();
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
      appBar: AppBar(title: Text(S.joinBusiness)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              if (_step == 0) ...[
                Text(
                  S.tr(
                    'Rejoignez un commerce déjà configuré',
                    'Join an existing business',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  S.tr(
                    'Utilisez le code d’invitation donné par le propriétaire. '
                    'Les codes INV-… rejoignent un commerce synchronisé sur '
                    'plusieurs appareils.',
                    'Use the employee invitation code provided by the owner. '
                    'INV-… codes join a business synced across devices.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                KumbaTextField(
                  controller: _code,
                  label: 'Code d’invitation',
                  hint: 'Ex. INV-A3K9-MP2X',
                  prefixIcon: Icons.group_add_outlined,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z0-9\-_]'),
                    ),
                    LengthLimitingTextInputFormatter(32),
                  ],
                ),
                const SizedBox(height: 20),
                KumbaButton(
                  label: 'Vérifier',
                  isLoading: _loading,
                  onPressed: _loading ? null : _peek,
                ),
              ] else ...[
                KumbaCard(
                  color: AppColors.kpiSalesBg,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.kpiSales,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _businessName ?? '',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${S.tr('Rôle proposé', 'Proposed role')} : $_role',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                KumbaTextField(
                  controller: _name,
                  label: 'Votre nom',
                  prefixIcon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                KumbaTextField(
                  controller: _phone,
                  label: 'Téléphone',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                KumbaTextField(
                  controller: _pin,
                  label: 'PIN personnel (4 chiffres)',
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  prefixIcon: Icons.pin_outlined,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
                const SizedBox(height: 20),
                KumbaButton(
                  label: 'Rejoindre et ouvrir',
                  isLoading: _loading,
                  onPressed: _loading ? null : _accept,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
