import 'package:flutter/material.dart';

/// Logo officiel Orange Money (asset embarqué) — réutilisable partout.
/// [size] = hauteur. [onColoredBackground] = pastille blanche pour rester
/// lisible sur fond orange/coloré (ex: bouton "Payer avec Orange Money").
class OrangeMoneyLogo extends StatelessWidget {
  final double size;
  final bool onColoredBackground;

  const OrangeMoneyLogo({
    super.key,
    this.size = 32,
    this.onColoredBackground = false,
  });

  static const orangeColor = Color(0xFFFF7900);

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/images/orange_money_logo.png',
      height: size,
      width: size * 1.4,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallback(),
    );
    if (onColoredBackground) {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: size * 0.18, vertical: size * 0.12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: logo,
      );
    }
    return logo;
  }

  /// Fallback dessiné (2 flèches croisées) si l'asset est indisponible
  Widget _fallback() {
    return SizedBox(
      width: size * 1.4,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0, top: 0,
            child: Icon(Icons.north_east_rounded,
                color: Colors.black87, size: size * 0.65),
          ),
          Positioned(
            right: 0, bottom: 0,
            child: Icon(Icons.south_west_rounded,
                color: orangeColor, size: size * 0.65),
          ),
        ],
      ),
    );
  }
}
