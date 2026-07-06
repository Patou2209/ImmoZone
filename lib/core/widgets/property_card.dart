import 'package:flutter/material.dart';
import '../../models/property_model.dart';
import '../../core/theme/app_theme.dart';
import 'property_image.dart';

class PropertyCard extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final bool showStatus;
  /// Pays sélectionné dans le filtre — déclenche l'affichage de la conversion si non-RDC
  final String? selectedCountry;

  const PropertyCard({
    super.key,
    required this.property,
    this.onTap,
    this.onFavorite,
    this.isFavorite = false,
    this.showStatus = false,
    this.selectedCountry,
  });

  // ── Conversion USD → monnaie locale ─────────────────────────────────────
  static const Map<String, Map<String, dynamic>> _currencyMap = {
    'Congo (Brazzaville)': {'code': 'FCFA', 'rate': 655.0,  'decimals': 0},
    'Angola':              {'code': 'AOA',  'rate': 900.0,  'decimals': 0},
    'Rwanda':              {'code': 'RWF',  'rate': 1300.0, 'decimals': 0},
    'Burundi':             {'code': 'BIF',  'rate': 2850.0, 'decimals': 0},
    'Tanzanie':            {'code': 'TZS',  'rate': 2500.0, 'decimals': 0},
    'Zambie':              {'code': 'ZMW',  'rate': 27.0,   'decimals': 2},
  };

  String? _localEquivalent() {
    if (selectedCountry == null || selectedCountry == 'Congo (RDC)' || selectedCountry!.isEmpty) return null;
    final info = _currencyMap[selectedCountry];
    if (info == null) return null;
    final rate = info['rate'] as double;
    final decimals = info['decimals'] as int;
    final converted = property.price * rate;
    String formatted;
    if (decimals == 0) {
      // Arrondi au multiple de 1 000 le plus proche
      final rounded = ((converted / 5000).round() * 5000);
      final s = rounded.toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
        buf.write(s[i]);
      }
      formatted = buf.toString();
    } else {
      formatted = converted.toStringAsFixed(decimals);
    }
    return '≈ $formatted ${info['code']}';
  }

  // Card dimensions: 400 × 450  (image 65% = 293px, description 35% = 157px)
  static const double _cardWidth       = 400;
  static const double _cardHeight      = 450;
  static const double _cardRadius      = 18;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_cardRadius),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // ── Image (3/4 of card height) ───────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(_cardRadius)),
                  child: PropertyImage(
                    src: property.mainImage,
                    height: _cardHeight * 0.65,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                // Transaction Badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: property.transactionType == 'Vente'
                          ? AppTheme.accentColor
                          : AppTheme.successColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      property.transactionType,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),
                // Status Badge (admin)
                if (showStatus)
                  Positioned(
                    top: 10,
                    right: 50,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(property.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        property.status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                // Favorite Button
                if (onFavorite != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                            )
                          ],
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? Colors.red : Colors.grey,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                // Sold / Occupied overlay banner
                if (property.isSold || property.isRented)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.42),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            decoration: BoxDecoration(
                              color: property.isSold
                                  ? AppTheme.successColor
                                  : const Color(0xFF0288D1),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  property.isSold
                                      ? Icons.check_circle_rounded
                                      : Icons.lock_rounded,
                                  color: Colors.white, size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  property.isSold ? 'VENDU' : 'OCCUPÉ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Poppins',
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Badge Offre Spéciale / Spécial (boost actif) — au-dessus du badge IZ
                if (property.isBoostActive && !property.isSold && !property.isRented)
                  Positioned(
                    bottom: 36,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: property.isVip
                            ? const LinearGradient(
                                colors: [Color(0xFF7B1FA2), Color(0xFFE040FB)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : property.isPremium
                                ? const LinearGradient(
                                    colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.30),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            property.isVip ? Icons.workspace_premium_rounded : Icons.star_rounded,
                            color: Colors.white,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            property.boostBadge ?? 'Offre Spéciale',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Badge Référence IZ (toujours affiché, bas-gauche)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'REF: IZ${property.id.length >= 4 ? property.id.substring(property.id.length - 4).toUpperCase() : property.id.toUpperCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                // Category badge (Agence / Commissionnaire / Propriétaire)
                if (property.ownerCategory.isNotEmpty)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _getCategoryColor(property.ownerCategory),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getCategoryIcon(property.ownerCategory),
                              color: Colors.white, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _categoryShortLabel(property.ownerCategory),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            // ── Description (35% of card height) ──────────────────────
            SizedBox(
              height: _cardHeight * 0.35,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Row 1: Title LEFT + Price RIGHT on the same line
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          property.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    property.formattedPrice,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accentColor,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                  if (property.transactionType == 'Location')
                                    Text(
                                      property.type == 'Chambre d\'hôtel'
                                          ? '/nuitée'
                                          : (property.type == 'Salle de Fêtes' ||
                                             property.type == 'Espace Funéraire' ||
                                             property.type == 'Salle polyvalente')
                                              ? '/jour'
                                              : '/mois',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textSecondary,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                ],
                              ),
                              if (_localEquivalent() != null)
                                Text(
                                  _localEquivalent()!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFFA726),
                                    fontFamily: 'Poppins',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Row 2: Location
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 13, color: AppTheme.accentColor),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          '${property.commune}, ${property.city}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            fontFamily: 'Poppins',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // Row 3: Feature chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (property.bedrooms != null && property.bedrooms! > 0)
                        _featureChip(Icons.bed, '${property.bedrooms} Ch.'),
                      if (property.bathrooms != null && property.bathrooms! > 0)
                        _featureChip(Icons.bathtub, '${property.bathrooms} SDB'),
                      if (property.type == 'Concession' && property.surface != null)
                        _featureChip(Icons.landscape_outlined,
                            '${property.surface!.toStringAsFixed(property.surface! == property.surface!.truncateToDouble() ? 0 : 2)} ha')
                      else if (property.type == 'Terrain à bâtir' &&
                          property.longueurM != null &&
                          property.largeurM != null)
                        _featureChip(Icons.straighten,
                            '${property.longueurM!.toInt()}m × ${property.largeurM!.toInt()}m')
                      else if (property.surface != null)
                        _featureChip(
                            Icons.square_foot, '${property.surface!.toInt()} m²'),
                      if (property.type == 'Chambre d\'hôtel' &&
                          property.numberOfBeds != null &&
                          property.numberOfBeds! > 0)
                        _featureChip(Icons.single_bed_rounded, '${property.numberOfBeds} Lit(s)'),
                    ],
                  ),
                  // Row 4: Garantie badge LEFT + clock + views RIGHT
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Garantie badge (Location only)
                      if (property.transactionType == 'Location' &&
                          property.type != 'Chambre d\'hôtel' &&
                          property.type != 'Salle de Fêtes' &&
                          property.type != 'Espace Funéraire' &&
                          property.type != 'Salle polyvalente' &&
                          property.garantieMois != null &&
                          property.garantieMois! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color:
                                    AppTheme.accentColor.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.security_rounded,
                                  size: 9, color: AppTheme.accentColor),
                              const SizedBox(width: 3),
                              Text(
                                'Gar. ${property.garantieMois}m',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentColor,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      // Clock (time ago) + eye (views)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 12, color: AppTheme.textHint),
                          const SizedBox(width: 3),
                          Text(
                            _timeAgo(property.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textHint,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.visibility_outlined,
                              size: 12, color: AppTheme.textHint),
                          const SizedBox(width: 3),
                          Text(
                            '${property.views}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textHint,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ), // SizedBox description
          ],
            ), // Column
          ), // Container
        ), // ClipRRect
        ), // AspectRatio
      ), // GestureDetector
    ); // MouseRegion
  }

  /// Returns a human-readable time-ago string based on [dt].
  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}j';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}sem';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
    return '${(diff.inDays / 365).floor()}an';
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.accentColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.accentColor,
              fontWeight: FontWeight.w500,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Agence Immobilière':
        return const Color(0xFF1565C0);
      case 'Commissionnaire':
        return const Color(0xFF6A1B9A);
      case 'Propriétaire':
      default:
        return const Color(0xFF2E7D32);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Agence Immobilière':
        return Icons.business_rounded;
      case 'Commissionnaire':
        return Icons.handshake_rounded;
      case 'Propriétaire':
      default:
        return Icons.home_rounded;
    }
  }

  String _categoryShortLabel(String category) {
    switch (category) {
      case 'Agence Immobilière':
        return 'Agence';
      case 'Commissionnaire':
        return 'Commis.';
      case 'Propriétaire':
      default:
        return 'Propriétaire';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Actif':
        return AppTheme.statusActive;
      case 'En attente':
        return AppTheme.statusPending;
      case 'Vendu':
        return AppTheme.statusSold;
      case 'Loué':
        return AppTheme.statusRented;
      case 'Rejeté':
        return AppTheme.statusRejected;
      default:
        return Colors.grey;
    }
  }
}
