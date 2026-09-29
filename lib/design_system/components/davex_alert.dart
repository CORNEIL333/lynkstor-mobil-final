import 'dart:async';

import 'package:flutter/cupertino.dart';

/// CRÉER — alertes de l'app, zéro code Material : la directive impose les
/// composants système iOS natifs.
///
/// Conformité HIG (*Alerts*, Apple HIG « Views → Alerts ») :
/// - structure `UIAlertController` = titre court gras + message factuel +
///   1 à 2 boutons ;
/// - bouton destructif en rouge (`CupertinoDialogAction` `isDestructive`,
///   rendu natif) ;
/// - bouton recommandé en gras (`isDefaultAction`) ;
/// - ordre HIG : annulation avant l'action ; le destructif n'est jamais
///   à droite d'un bouton par défaut sans confirmation — ici l'ordre des
///   [actions] est celui fourni par l'appelant, documenté à chaque usage ;
/// - pas d'alerte custom imitant le système : on utilise le widget natif
///   `CupertinoAlertDialog`, qui reproduit exactement le rendu iOS.
///
/// Retourne l'action choisie (index dans [actions]), ou null si annulé.
Future<int?> davexShowAlert(
  BuildContext context, {
  required String title,
  String? message,
  required List<DavexAlertAction> actions,
}) {
  return showCupertinoModalPopup<int>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        for (final a in actions)
          CupertinoDialogAction(
            isDefaultAction: a.isDefault,
            isDestructiveAction: a.isDestructive,
            onPressed: () => Navigator.of(context).pop(a.index),
            child: Text(a.label, overflow: TextOverflow.ellipsis),
          ),
      ],
    ),
  );
}

class DavexAlertAction {
  const DavexAlertAction(
    this.label, {
    this.index = 0,
    this.isDefault = false,
    this.isDestructive = false,
  });

  final String label;
  final int index;
  final bool isDefault;
  final bool isDestructive;
}

/// Convenience HIG : confirmation destructive (suppression…).
/// Ordre natif : « Annuler » (défaut, gras) puis l'action rouge.
Future<bool> davexConfirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
}) async {
  final result = await davexShowAlert(
    context,
    title: title,
    message: message,
    actions: [
      DavexAlertAction(cancelLabel, index: 0, isDefault: true),
      DavexAlertAction(confirmLabel, index: 1, isDestructive: true),
    ],
  );
  return result == 1;
}

/// CRÉER — bannière de notification in-app façon banner natif iOS
/// (HIG *Notifications & Banners* : sous la status bar, icône + titre +
/// corps, dismissal gestuel, n'intercepte pas les touches voisines,
/// durée ~4 s). Rendu via OverlayEntry pour ne jamais bloquer la caisse.
void davexNotify(
  BuildContext context, {
  required String title,
  String? body,
  IconData icon = CupertinoIcons.checkmark_seal_fill,
  Color accent = const Color(0xFF16C784),
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  Timer? timer;
  entry = OverlayEntry(
    builder: (context) => _DavexBanner(
      title: title,
      body: body,
      icon: icon,
      accent: accent,
      onDone: () {
        timer?.cancel();
        entry.remove();
      },
      onScheduled: () => timer = Timer(duration, () {
        if (entry.mounted) entry.remove();
      }),
    ),
  );
  overlay.insert(entry);
}

class _DavexBanner extends StatefulWidget {
  const _DavexBanner({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.onDone,
    required this.onScheduled,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Color accent;
  final VoidCallback onDone;
  final VoidCallback onScheduled;

  @override
  State<_DavexBanner> createState() => _DavexBannerState();
}

class _DavexBannerState extends State<_DavexBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _visible = true);
      widget.onScheduled();
    });
  }

  void _dismiss() {
    setState(() => _visible = false);
    Future.delayed(const Duration(milliseconds: 220), widget.onDone);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      top: mq.padding.top + 8,
      left: 12,
      right: 12,
      child: IgnorePointer(
        ignoring: false,
        child: GestureDetector(
          // Geste natif banner : swipe up pour dismiss.
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -120) _dismiss();
          },
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, -1.2),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E000000),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 18,
                            color: CupertinoColors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (widget.body != null)
                                Text(
                                  widget.body!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'maintenant',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
