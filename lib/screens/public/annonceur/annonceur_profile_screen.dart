import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/property_card.dart';
import '../../../models/property_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/user_model.dart';
import '../../../services/data_service.dart';
import '../property_detail/property_detail_screen.dart';

/// Écran public du profil d'un annonceur.
/// Affiche : photo / initiales, nom, message d'accueil, catégorie,
/// et toutes ses annonces actives.
class AnnonceurProfileScreen extends StatefulWidget {
  final String ownerId;
  final String ownerName;  // fallback si Firestore indisponible

  const AnnonceurProfileScreen({
    super.key,
    required this.ownerId,
    required this.ownerName,
  });

  @override
  State<AnnonceurProfileScreen> createState() => _AnnonceurProfileScreenState();
}

class _AnnonceurProfileScreenState extends State<AnnonceurProfileScreen> {
  final DataService _ds = DataService();
  UserModel? _user;
  List<PropertyModel> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Charger le profil de l'annonceur
      final user = await _ds.getUserById(widget.ownerId);
      // Charger toutes ses annonces actives
      final allProps = await _ds.getUserProperties(widget.ownerId);
      final activeProps = allProps
          .where((p) => p.status == 'Actif' && !p.isSold && !p.isRented)
          .toList();
      // Enrichir avec les avatars pour afficher la photo du propriétaire sur chaque carte
      final enriched = await _ds.enrichWithAvatars(activeProps);
      if (mounted) {
        setState(() {
          _user   = user;
          _listings = enriched;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Avatar : photo base64 ou initiales ───────────────────────────────────
  Widget _buildAvatar(double radius) {
    final avatarData = _user?.avatar;
    final initials = _user?.name.isNotEmpty == true
        ? _user!.name[0].toUpperCase()
        : widget.ownerName.isNotEmpty ? widget.ownerName[0].toUpperCase() : '?';

    Widget inner;
    if (avatarData != null && avatarData.isNotEmpty) {
      try {
        final b64 = avatarData.contains(',') ? avatarData.split(',').last : avatarData;
        final bytes = base64Decode(b64);
        inner = Image.memory(bytes, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsText(initials, radius));
      } catch (_) {
        inner = _initialsText(initials, radius);
      }
    } else {
      inner = _initialsText(initials, radius);
    }

    return MouseRegion(
      cursor: avatarData != null && avatarData.isNotEmpty
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTap: avatarData != null && avatarData.isNotEmpty
            ? () => _showFullscreen(avatarData)
            : null,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
                color: AppTheme.accentColor.withValues(alpha: 0.5), width: 2),
          ),
          child: ClipOval(child: inner),
        ),
      ),
    );
  }

  Widget _initialsText(String initials, double radius) {
    return Center(child: Text(initials, style: TextStyle(
        fontSize: radius * 0.7, fontWeight: FontWeight.w800,
        color: AppTheme.primaryColor, fontFamily: 'Poppins')));
  }

  Future<void> _shareProperty(PropertyModel p) async {
    final ref = 'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final text = '${p.title} — Réf. $ref\n$link';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  void _showFullscreen(String avatarData) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(
            child: Center(child: Builder(builder: (ctx) {
              try {
                final b64 = avatarData.contains(',')
                    ? avatarData.split(',').last : avatarData;
                final bytes = base64Decode(b64);
                return Image.memory(bytes, fit: BoxFit.contain,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height);
              } catch (_) {
                return const Icon(Icons.broken_image,
                    color: Colors.white, size: 64);
              }
            })),
          ),
          Positioned(
            top: 40, right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Badge catégorie ───────────────────────────────────────────────────────
  Widget? _buildCategoryBadge(String? category) {
    if (category == null || category.isEmpty) return null;
    Color color;
    IconData icon;
    switch (category) {
      case 'Agence Immobilière':
        color = const Color(0xFF1565C0);
        icon  = Icons.business_rounded;
      case 'Commissionnaire':
        color = const Color(0xFF6A1B9A);
        icon  = Icons.handshake_rounded;
      default:
        color = const Color(0xFF2E7D32);
        icon  = Icons.person_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(category, style: TextStyle(fontFamily: 'Poppins',
            fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _user?.name ?? widget.ownerName;
    final category    = _user?.category ?? '';
    final description = _user?.description ?? '';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(displayName,
            style: const TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, color: Colors.white),
            overflow: TextOverflow.ellipsis),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.accentColor))
          : RefreshIndicator(
              color: AppTheme.accentColor,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Carte profil ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Avatar
                      _buildAvatar(36),
                      const SizedBox(width: 14),
                      // Nom + catégorie
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(displayName,
                            style: const TextStyle(fontFamily: 'Poppins',
                                fontSize: 15, fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 5),
                        if (category.isNotEmpty)
                          _buildCategoryBadge(category) ?? const SizedBox(),
                      ])),
                    ]),
                  ),

                  // ── Message d'accueil ────────────────────────────────────
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.dividerColor),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Row(children: [
                          Icon(Icons.format_quote_rounded,
                              size: 16, color: AppTheme.primaryColor),
                          SizedBox(width: 6),
                          Text('Message d\'accueil',
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor)),
                        ]),
                        const SizedBox(height: 8),
                        Text(description,
                            style: const TextStyle(fontFamily: 'Poppins',
                                fontSize: 13, color: AppTheme.textSecondary,
                                height: 1.5)),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── Titre annonces ───────────────────────────────────────
                  Text(
                    'Annonces de $displayName (${_listings.length})',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),

                  // ── Liste annonces ───────────────────────────────────────
                  if (_listings.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(children: [
                          Icon(Icons.home_work_outlined,
                              size: 56,
                              color: AppTheme.textHint.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text('Aucune annonce active',
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 14, color: AppTheme.textHint)),
                        ]),
                      ),
                    )
                  else
                    LayoutBuilder(builder: (context, constraints) {
                      final cols = (constraints.maxWidth / 340).floor().clamp(1, 99);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 400 / 450,
                        ),
                        itemCount: _listings.length,
                        itemBuilder: (context, index) {
                          final p = _listings[index];
                          return PropertyCard(
                            property: p,
                            onShare: () => _shareProperty(p),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => PropertyDetailScreen(
                                        property: p))),
                          );
                        },
                      );
                    }),
                ]),
              ),
            ),
    );
  }
}
