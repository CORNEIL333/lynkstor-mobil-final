import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// RECRÉER depuis `.lk-search-field` (components.css L335–354) :
/// conteneur min-height 48, padding 0×13, gap 10, bord 1 px borderControl,
/// radius 12, fond surface ; input interne min-height 44 sans bordure
/// (HIG : cible tactile du champ ≥ 44 pt).
class DavexSearchField extends StatelessWidget {
  const DavexSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(LkColors.radiusMedium),
        border: Border.all(color: p.borderControl),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: p.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              autofocus: autofocus,
              enabled: enabled,
              style: TextStyle(color: p.text, fontSize: 14),
              cursorColor: p.action,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: hintText,
                hintStyle: TextStyle(color: p.textSecondary, fontSize: 14),
              ),
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: 10), suffix!],
        ],
      ),
    );
  }
}
