import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../design_system/components/kumba_ai_badge.dart';
import '../../design_system/components/kumba_pressable.dart';
import '../../design_system/motion/lynk_avatar.dart';
import '../../l10n/app_strings.dart';
import 'lynk_prefs.dart';

final pendingAiPromptProvider = StateProvider<String?>((ref) => null);

Future<void> showLynkQuickSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LynkQuickSheet(),
  );
}

/// Mini-chat IA : chips + saisie, expand vers plein écran.
class LynkQuickSheet extends ConsumerStatefulWidget {
  const LynkQuickSheet({super.key});

  @override
  ConsumerState<LynkQuickSheet> createState() => _LynkQuickSheetState();
}

class _LynkQuickSheetState extends ConsumerState<LynkQuickSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openFull([String? prompt]) {
    if (prompt != null && prompt.trim().isNotEmpty) {
      ref.read(pendingAiPromptProvider.notifier).state = prompt.trim();
    }
    Navigator.of(context).pop();
    context.go('/ai');
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final prefs = ref.watch(lynkPrefsProvider);
    final chips = [
      S.tr('Résume mes ventes du jour', 'Summarize today’s sales'),
      S.tr('Quels articles sont en rupture ?', 'Which items are out of stock?'),
      S.tr('Qui me doit de l’argent ?', 'Who owes me money?'),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Material(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    LynkAvatar(
                      size: 48,
                      enabled: !reduce,
                      mood: LynkMood.greeting,
                      accent: prefs.accentColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prefs.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.lynkViolet,
                                ),
                          ),
                          Text(
                            S.tr(
                              'Assistant local · aucune action auto',
                              'Local assistant · no auto actions',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const KumbaAiBadge(compact: true),
                    IconButton(
                      tooltip: S.tr('Plein écran', 'Full screen'),
                      onPressed: () => _openFull(),
                      icon: const Icon(Icons.open_in_full_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  shrinkWrap: true,
                  children: [
                    for (final chip in chips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: KumbaPressable(
                          onTap: () => _openFull(chip),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: dark
                                  ? AppColors.darkSurface
                                  : AppColors.lynkVioletSoft,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusLg,
                              ),
                            ),
                            child: Text(
                              chip,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.lynkViolet,
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _openFull,
                        decoration: InputDecoration(
                          hintText: S.tr('Demander à Lynk…', 'Ask Lynk…'),
                          filled: true,
                          fillColor: dark
                              ? AppColors.darkSurface
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _openFull(_ctrl.text),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
