import 'package:flutter/material.dart';

/// Widget utilitaire qui ajoute automatiquement cursor:pointer sur le web
/// pour tous les éléments cliquables (remplace GestureDetector simple).
///
/// Usage :
///   Tappable(onTap: () => ..., child: MyWidget())
///
/// Équivalent à MouseRegion(cursor: SystemMouseCursors.click,
///              child: GestureDetector(onTap: ..., child: ...))
class Tappable extends StatelessWidget {
  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null || onLongPress != null || onDoubleTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        behavior: behavior,
        child: child,
      ),
    );
  }
}
