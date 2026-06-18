import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/ad_model.dart';
import '../../services/data_service.dart';
import '../theme/app_theme.dart';

/// Carte "Sponsorisé" affichée dans les listes d'annonces.
///
/// [gridMode] = false (défaut) : pleine largeur, hauteur fixe 230px,
///              avec margin horizontal — pour usage standalone entre deux grilles.
/// [gridMode] = true           : pas de margin, s'étire pour occuper
///              exactement le slot de la grille (400×450, géré par childAspectRatio).
///
/// Impression : comptée une seule fois à l'apparition du widget.
/// Clic : comptabilisé + ouverture du lien (URL / WhatsApp / Téléphone).
class AdBannerCard extends StatefulWidget {
  final AdModel ad;
  /// Quand true, la carte s'adapte au slot de grille (400×450).
  /// Quand false (défaut), pleine largeur autonome.
  final bool gridMode;
  const AdBannerCard({super.key, required this.ad, this.gridMode = false});

  @override
  State<AdBannerCard> createState() => _AdBannerCardState();
}

class _AdBannerCardState extends State<AdBannerCard> {
  final DataService _ds = DataService();
  bool _impressionRecorded = false;

  @override
  void initState() {
    super.initState();
    // Enregistrer l'impression une seule fois, après le premier rendu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_impressionRecorded && mounted) {
        _impressionRecorded = true;
        _ds.recordAdImpression(widget.ad.id);
      }
    });
  }

  AdModel get ad => widget.ad;

  // ── Couleur d'accent par catégorie ────────────────────────────────────────
  Color get _accentColor {
    switch (ad.category) {
      case 'Banque / Finance':         return const Color(0xFF1565C0);
      case 'Notaire / Juridique':      return const Color(0xFF4A148C);
      case 'Agence immobilière':       return AppTheme.primaryColor;
      case 'Construction / Matériaux': return const Color(0xFF4E342E);
      case 'Décoration / Intérieur':   return const Color(0xFFAD1457);
      case 'Déménagement / Transport': return const Color(0xFF00695C);
      case 'Assurance':                return const Color(0xFF0277BD);
      default:                         return const Color(0xFF546E7A);
    }
  }

  // ── Lancement du lien ─────────────────────────────────────────────────────
  Future<void> _handleTap() async {
    _ds.recordAdClick(ad.id);
    // Nettoyer tous les espaces/caractères invisibles (espace normal, NBSP, ZWS, BOM)
    final raw = ad.linkValue.replaceAll(RegExp(r'[\s\u00A0\u200B\uFEFF]'), '');
    Uri? uri;
    try {
      switch (ad.linkType) {
        case 'whatsapp':
          final number = raw.replaceAll(RegExp(r'[^\d+]'), '');
          uri = Uri.parse('https://wa.me/$number');
          break;
        case 'phone':
          uri = Uri.parse('tel:$raw');
          break;
        default:
          // Forcer https:// si pas de scheme, puis construire proprement
          final withScheme = (raw.startsWith('http://') || raw.startsWith('https://'))
              ? raw
              : 'https://$raw';
          uri = Uri.tryParse(withScheme);
          if (uri == null || uri.host.isEmpty) {
            throw FormatException('URL invalide : $withScheme');
          }
      }
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Impossible d'ouvrir le lien.",
              style: TextStyle(fontFamily: 'Poppins')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lien invalide : $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Rendu de l'image (base64 ou URL réseau ou placeholder) ────────────────
  Widget _buildImage() {
    final src = ad.imageUrl;
    if (src.isEmpty) {
      return Container(
        color: _accentColor.withValues(alpha: 0.12),
        child: Center(
          child: Icon(Icons.campaign_rounded,
              color: _accentColor.withValues(alpha: 0.5), size: 48),
        ),
      );
    }
    if (src.startsWith('data:image') ||
        (src.length > 200 && !src.startsWith('http'))) {
      try {
        final b64 = src.contains(',') ? src.split(',').last : src;
        return Image.memory(base64Decode(b64),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _imageFallback());
      } catch (_) {
        return _imageFallback();
      }
    }
    return Image.network(src,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _imageFallback());
  }

  Widget _imageFallback() => Container(
    color: _accentColor.withValues(alpha: 0.10),
    child: Center(
      child: Icon(Icons.broken_image_outlined,
          color: _accentColor.withValues(alpha: 0.4), size: 40),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isGrid = widget.gridMode;
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        // gridMode : pas de margin (la grille gère l'espacement via mainAxisSpacing/crossAxisSpacing)
        // standalone : margin horizontal pour s'aligner avec les grilles autour
        margin: isGrid
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _accentColor.withValues(alpha: 0.20),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        // ── Stack : image en fond + overlay bas ─────────────────────────────
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          // gridMode : taille imposée par le slot GridView (400×450 via childAspectRatio)
          // standalone : hauteur fixe 230px, largeur infinie
          child: SizedBox(
            width: double.infinity,
            height: isGrid ? double.infinity : 230,
            child: Stack(
              fit: StackFit.expand,
              children: [
              // ── Image couvre tout le slot ──────────────────────────────────
              Positioned.fill(
                child: _buildImage(),
              ),

              // ── Dégradé sombre en bas pour lisibilité du texte ───────────
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Ligne basse : "Sponsorisé" + bouton Visiter ──────────────
              Positioned(
                left: 12, right: 12, bottom: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Badge "Sponsorisé"
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign_rounded,
                              size: 11, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Sponsorisé',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Bouton "→ Visiter"
                    GestureDetector(
                      onTap: _handleTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(ad.ctaLabel.isNotEmpty ? ad.ctaLabel : 'Visiter',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _accentColor)),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded,
                                size: 13, color: _accentColor),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Titre en haut-gauche (si image présente) ─────────────────
              if (ad.title.isNotEmpty)
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      ad.title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 1)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            ), // Stack
          ), // SizedBox
        ),   // ClipRRect
      ),     // Container
    );       // GestureDetector
  }
}
