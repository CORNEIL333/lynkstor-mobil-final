import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';

/// Primitives DAVEX — port Flutter fidèle de `src/ui/primitives.tsx`
/// et `src/design-system/components.css`.
///
/// Géométrie maquette : radius medium 12, cible tactile 44 min,
/// press scale 0.97, typo 2 graisses (regular/medium).

// ——— Button ———

enum LkButtonTone { primary, secondary, ghost, danger }

class LkButton extends StatelessWidget {
  const LkButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = LkButtonTone.primary,
    this.icon,
    this.expanded = false,
    this.loading = false,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final LkButtonTone tone;
  final IconData? icon;
  final bool expanded;
  final bool loading;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final enabled = onPressed != null && !loading;

    final (Color bg, Color fg, BorderSide side) = switch (tone) {
      LkButtonTone.primary => (
        p.action,
        p.onAction,
        const BorderSide(),
      ),
      LkButtonTone.secondary => (
        p.surface,
        p.text,
        BorderSide(color: p.borderControl),
      ),
      LkButtonTone.ghost => (
        Colors.transparent,
        p.link,
        const BorderSide(),
      ),
      LkButtonTone.danger => (
        p.dangerFg,
        p.surface,
        const BorderSide(),
      ),
    };
    final hoverBg = switch (tone) {
      LkButtonTone.primary => p.actionHover,
      LkButtonTone.danger => p.danger,
      _ => bg,
    };

    final child = AnimatedContainer(
      duration: AppMotion.fast,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: large ? AppSpacing.md : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.fromBorderSide(side),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else if (icon != null)
            Icon(icon, size: 18, color: fg),
          if (loading || icon != null) const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: large ? 16 : 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: LkPressable(
        onTap: enabled ? onPressed : null,
        hoverColor: hoverBg,
        baseColor: bg,
        child: expanded ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

/// Press physique scale(0.97) — `.lk-ds-button:active` de la maquette.
class LkPressable extends StatefulWidget {
  const LkPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.hoverColor,
    this.baseColor,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? hoverColor;
  final Color? baseColor;
  final BorderRadius? borderRadius;

  @override
  State<LkPressable> createState() => _LkPressableState();
}

class _LkPressableState extends State<LkPressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? AppMotion.pressScale : 1,
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            decoration: BoxDecoration(
              borderRadius:
                  widget.borderRadius ??
                  BorderRadius.circular(AppSpacing.radiusMd),
              color: _hover && widget.hoverColor != null
                  ? widget.hoverColor
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ——— IconButton ———

class LkIconButton extends StatelessWidget {
  const LkIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.count = 0,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final int count;

  /// null = transparent ; sinon fond de la pastille (header sombre).
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final button = Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: InkWell(
        onTap: onPressed,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.touchTarget,
            minHeight: AppSpacing.touchTarget,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone ?? Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, size: 22, color: tone == null ? p.text : Colors.white),
        ),
      ),
    );
    if (count <= 0) return button;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: p.action,
      textColor: p.onAction,
      child: button,
    );
  }
}

// ——— Field + Input (erreur inline, rôle alerte) ———

class LkField extends StatelessWidget {
  const LkField({
    super.key,
    required this.label,
    required this.child,
    this.error,
    this.hint,
    this.forId,
  });

  final String label;
  final Widget child;
  final String? error;
  final String? hint;
  final String? forId;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: p.text,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            label: error,
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: p.dangerFg),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 13, color: p.dangerFg),
                  ),
                ),
              ],
            ),
          ),
        ] else if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: TextStyle(fontSize: 13, color: p.textSecondary)),
        ],
      ],
    );
  }
}

class LkInput extends StatelessWidget {
  const LkInput({
    super.key,
    this.controller,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.error = false,
    this.prefixIcon,
    this.suffix,
    this.maxLines = 1,
    this.autofocus = false,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool error;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int maxLines;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return SizedBox(
      height: maxLines == 1 ? AppSpacing.inputHeight : null,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: TextStyle(color: p.text, fontSize: 15),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(color: p.textSecondary),
          errorText: error ? ' ' : null,
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide(color: p.dangerFg),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: BorderSide(color: p.dangerFg, width: 2),
          ),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, size: 20, color: p.textSecondary),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

// ——— Badge (paires sémantiques par ton) ———

enum LkBadgeTone { neutral, info, success, warning, danger, action }

class LkBadge extends StatelessWidget {
  const LkBadge({
    super.key,
    required this.label,
    this.tone = LkBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final LkBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final (Color bg, Color fg) = switch (tone) {
      LkBadgeTone.neutral => (p.surfaceMuted, p.textSecondary),
      LkBadgeTone.info => (p.infoBg, p.infoFg),
      LkBadgeTone.success => (p.successBg, p.successFg),
      LkBadgeTone.warning => (p.warningBg, p.warningFg),
      LkBadgeTone.danger => (p.dangerBg, p.dangerFg),
      LkBadgeTone.action => (p.selectedBg, p.selectedFg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ——— ShopAvatar — initiales + image optionnelle (.lk-shop-avatar) ———

class ShopAvatar extends StatelessWidget {
  const ShopAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
  });

  final String name;
  final String? imageUrl;
  final double size;

  static String initialsOf(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s.characters.first)
      .join()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    final initials = initialsOf(name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.selectedBg,
          border: Border.all(color: p.borderControl),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: imageUrl == null
            ? Text(
                initials.isEmpty ? 'LS' : initials,
                style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w500,
                  color: p.selectedFg,
                  letterSpacing: 0.2,
                ),
              )
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initials.isEmpty ? 'LS' : initials,
                    style: TextStyle(
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w500,
                      color: p.selectedFg,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ——— Vue d'erreur rattrapable (AppErrorBoundary) ———

class LkErrorView extends StatelessWidget {
  const LkErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Affichage indisponible',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = LkPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.report_gmailerrorred_outlined, size: 40, color: p.dangerFg),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: p.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              LkButton(
                label: "Réessayer l'affichage",
                icon: Icons.refresh,
                tone: LkButtonTone.secondary,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Limite d'erreur : si [child] plante au build, affiche [LkErrorView] avec
/// « Réessayer l'affichage » — équivalent Flutter de AppErrorBoundary.
class LkErrorBoundary extends StatefulWidget {
  const LkErrorBoundary({super.key, required this.child, this.label});

  final Widget child;
  final String? label;

  @override
  State<LkErrorBoundary> createState() => _LkErrorBoundaryState();
}

class _LkErrorBoundaryState extends State<LkErrorBoundary> {
  int _attempt = 0;
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return LkErrorView(
        key: ValueKey(_attempt),
        message: widget.label ?? 'Une erreur est survenue à cet écran.',
        onRetry: () => setState(() {
          _error = null;
          _attempt++;
        }),
      );
    }
    return Builder(
      key: ValueKey(_attempt),
      builder: (context) => ErrorBuilder(
        onError: (e) => setState(() => _error = e),
        child: widget.child,
      ),
    );
  }
}

/// Helper interne : déclenche [onError] si le sous-arbre lance pendant build.
class ErrorBuilder extends StatefulWidget {
  const ErrorBuilder({super.key, required this.child, required this.onError});

  final Widget child;
  final ValueChanged<Object> onError;

  @override
  State<ErrorBuilder> createState() => _ErrorBuilderState();
}

class _ErrorBuilderState extends State<ErrorBuilder> {
  @override
  Widget build(BuildContext context) {
    try {
      return widget.child;
    } catch (e) {
      // Le framework signale déjà l'erreur ; on bascule sur la vue de repli.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onError(e);
      });
      return const SizedBox.shrink();
    }
  }
}
