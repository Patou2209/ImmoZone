import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/property_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';
import '../../../core/utils/web_url_helper.dart';

class PropertyDetailScreen extends StatefulWidget {
  final PropertyModel property;
  const PropertyDetailScreen({super.key, required this.property});

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  bool _isFavorite = false;
  final DataService _ds = DataService();
  int _currentImageIndex = 0;
  final PageController _pageCtrl = PageController();
  String _officialMessage = '';
  bool _messageExpanded = false;
  String _ownerSince = '';
  bool _ownerSinceLoaded = false; // true une fois la requête terminée
  // Compteur de vues local — mis à jour après incrément Firestore
  late int _views;

  @override
  void initState() {
    super.initState();
    // Initialiser avec la valeur cachée puis mettre à jour après incrément
    _views = widget.property.views;
    _checkFavorite();
    _loadOfficialMessage();
    _loadOwnerSince();
    _incrementAndRefreshViews();
    // ── Synchroniser l'URL du navigateur web ──────────────────────────────
    WebUrlHelper.setPropertyUrl(widget.property.id);
  }

  /// Incrémente les vues dans Firestore puis relit la valeur réelle
  /// Incrémente les vues — optimiste (+1 immédiat) puis confirme via Firestore
  Future<void> _incrementAndRefreshViews() async {
    // Affichage optimiste : +1 tout de suite pour UX fluide
    if (mounted) setState(() => _views = _views + 1);
    // Incrément Firestore (retourne la valeur réelle ou null si échec)
    final newViews = await _ds.incrementPropertyViews(widget.property.id);
    if (newViews != null && mounted) {
      setState(() => _views = newViews);
    }
  }

  // ── Charge l'ancienneté de l'annonceur depuis Firestore ──────────────────
  // Lit le champ brut 'createdAt' (Timestamp Firestore OU String ISO8601)
  // directement depuis le document, sans passer par UserModel.fromMap,
  // pour éviter les problèmes de parsing sur les anciens documents.
  Future<void> _loadOwnerSince() async {
    final ownerId = widget.property.ownerId;
    if (ownerId.isEmpty) return;

    DateTime? createdAt;

    // ── Tentative 1 : lecture directe Firestore (champ brut) ─────────────────
    try {
      final snap = await _ds.usersCollection.doc(ownerId).get();
      if (snap.exists) {
        final raw = (snap.data() as Map<String, dynamic>?)?['createdAt'];
        debugPrint('[ancienneté] ownerId=$ownerId  raw=$raw  type=${raw?.runtimeType}');
        if (raw != null) {
          if (raw is DateTime) {
            createdAt = raw;
          } else {
            // Timestamp Firestore (duck-typing)
            try { createdAt = (raw as dynamic).toDate() as DateTime; } catch (_) {}
            // String ISO8601
            if (createdAt == null) {
              try { createdAt = DateTime.parse(raw.toString()); } catch (_) {}
            }
          }
        }
      } else {
        debugPrint('[ancienneté] document inexistant pour ownerId=$ownerId');
      }
    } catch (e) {
      debugPrint('[ancienneté] erreur lecture Firestore: $e');
    }

    // ── Tentative 2 : via getUserById (fallback) ──────────────────────────────
    if (createdAt == null) {
      try {
        final owner = await _ds.getUserById(ownerId);
        // N'utiliser que si la date est significative (pas DateTime.now() de fallback)
        if (owner != null) {
          final diff = DateTime.now().difference(owner.createdAt).inDays;
          if (diff > 0) createdAt = owner.createdAt;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    // ── Calcul du label ────────────────────────────────────────────────────────
    if (createdAt == null) {
      // Impossible de déterminer la date → ne rien afficher, mais marquer comme chargé
      if (mounted) setState(() => _ownerSinceLoaded = true);
      return;
    }

    final totalMonths = (DateTime.now().difference(createdAt).inDays / 30.44).floor();
    // Labels courts pour le badge inline (max ~12 caractères)
    final String label;
    if (totalMonths < 1) {
      label = 'Nouveau';
    } else if (totalMonths < 12) {
      label = '$totalMonths mois';
    } else {
      final years  = totalMonths ~/ 12;
      final months = totalMonths % 12;
      final yStr   = '$years an${years > 1 ? 's' : ''}';
      final mStr   = months > 0 ? ' $months m.' : '';
      label = '$yStr$mStr';
    }

    setState(() {
      _ownerSince = label;
      _ownerSinceLoaded = true;
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    // ── Remettre l'URL sur /public quand on quitte l'annonce ─────────────
    WebUrlHelper.setPublicUrl();
    super.dispose();
  }

  Future<void> _checkFavorite() async {
    final fav = await _ds.isFavorite(widget.property.id);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    await _ds.toggleFavorite(widget.property.id);
    await _checkFavorite();
  }

  Future<void> _loadOfficialMessage() async {
    final msg = _ds.officialMessage;
    if (mounted) setState(() => _officialMessage = msg);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Actif': return AppTheme.statusActive;
      case 'En attente': return AppTheme.statusPending;
      case 'Vendu': return AppTheme.statusSold;
      case 'Loue': return AppTheme.statusRented;
      default: return Colors.grey;
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copie dans le presse-papiers',
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.currentUser?.id == p.ownerId;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      // Fixed AppBar — never transparent, never scrolls, photo starts BELOW it
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
          onTap: () {
            // Logo → accueil : pop toute la pile puis go /public
            Navigator.of(context).popUntil((route) => route.isFirst);
            context.go('/public');
          },
          child: LayoutBuilder(builder: (ctx, _) {
            final w = MediaQuery.of(ctx).size.width;
            final h = w < 480 ? 26.0 : w < 768 ? 30.0 : w < 1024 ? 36.0 : 42.0;
            return Image.asset(
              'assets/images/immozone_logo_text.png',
              height: h,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => RichText(
                text: TextSpan(
                  style: TextStyle(fontFamily: 'Poppins', fontSize: h * 0.55),
                  children: const [
                    TextSpan(text: 'Immo',
                        style: TextStyle(fontWeight: FontWeight.w800,
                            color: Color(0xFF2B5BE8))),
                    TextSpan(text: 'Zone',
                        style: TextStyle(fontWeight: FontWeight.w800,
                            color: Color(0xFFED5C1F))),
                  ],
                ),
              ),
            );
          }),
        )),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE9EBF0)),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _isFavorite ? Colors.redAccent : AppTheme.textSecondary,
            ),
            onPressed: _toggleFavorite,
            tooltip: 'Ajouter aux favoris',
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: AppTheme.textSecondary),
            onPressed: () => _shareProperty(p),
            tooltip: 'Partager',
          ),
        ],
      ),

      body: SafeArea(
        top: false, // AppBar gere deja la status bar
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // ----------------------------------------------------------------
            // PHOTO GALLERY — responsive:
            //   mobile (<768px)  : slideshow pleine largeur h=280
            //   desktop (≥768px) : grille centrée max 900px (1 grande + 2 petites)
            // ----------------------------------------------------------------
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 768;
              if (isWide) {
                // ── WIDE SCREEN: grille centrée ─────────────────────────────
                return _buildWidePhotoGrid(p);
              }
              // ── MOBILE: slideshow classique ─────────────────────────────
              return SizedBox(
              height: 280,
              child: Stack(
                children: [
                  // PageView images
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: p.images.isNotEmpty ? p.images.length : 1,
                    onPageChanged: (i) => setState(() => _currentImageIndex = i),
                    itemBuilder: (_, i) {
                      final img = p.images.isNotEmpty
                          ? p.images[i]
                          : AppConstants.placeholderProperty;
                      return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                        onTap: () => _openImageFullscreen(context, p.images, i),
                        child: _buildPropertyImage(img),
                      ));
                    },
                  ),

                  // Bottom gradient
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Prev / Next buttons
                  if (p.images.length > 1) ...[
                    Positioned(
                      left: 8, top: 0, bottom: 0,
                      child: Center(
                        child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                          onTap: () {
                            if (_currentImageIndex > 0) {
                              _pageCtrl.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            }
                          },
                          child: AnimatedOpacity(
                            opacity: _currentImageIndex > 0 ? 1.0 : 0.3,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        )),
                      ),
                    ),
                    Positioned(
                      right: 8, top: 0, bottom: 0,
                      child: Center(
                        child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                          onTap: () {
                            if (_currentImageIndex < p.images.length - 1) {
                              _pageCtrl.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            }
                          },
                          child: AnimatedOpacity(
                            opacity: _currentImageIndex < p.images.length - 1 ? 1.0 : 0.3,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        )),
                      ),
                    ),
                  ],

                  // Dot indicators
                  if (p.images.length > 1)
                    Positioned(
                      bottom: 12, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          p.images.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _currentImageIndex == i ? 22 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: _currentImageIndex == i
                                  ? AppTheme.accentColor
                                  : Colors.white60,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Transaction badge
                  Positioned(
                    bottom: 40, left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.transactionType == 'Vente'
                            ? AppTheme.primaryColor
                            : AppTheme.successColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Text(p.transactionType,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins')),
                    ),
                  ),

                  // Photo count badge
                  if (p.images.length > 1)
                    Positioned(
                      bottom: 40, right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.photo_library_outlined,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${_currentImageIndex + 1}/${p.images.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ); // end mobile slideshow
            }), // end LayoutBuilder

            // ----------------------------------------------------------------
            // SCROLLABLE CONTENT  (all cards, margin: symmetric(horizontal:16))
            // ----------------------------------------------------------------

            // Message officiel ImmoZone
            if (_officialMessage.isNotEmpty) ...[  
              const SizedBox(height: 16),
              MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                onTap: () => setState(() => _messageExpanded = !_messageExpanded),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppTheme.accentColor.withValues(alpha: 0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF57C00).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.verified_rounded,
                            color: Color(0xFFF57C00), size: 16),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Message Officiel ImmoZone',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Colors.white)),
                      ),
                      Icon(
                        _messageExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ]),
                    if (_messageExpanded) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 10),
                      Text(_officialMessage,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.white70,
                              height: 1.6)),
                    ],
                    if (!_messageExpanded) ...[
                      const SizedBox(height: 6),
                      Text(
                        _officialMessage.length > 80
                            ? '${_officialMessage.substring(0, 80)}...'
                            : _officialMessage,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white54,
                            height: 1.4),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ]),
                ),
              )),

            ],

            // ── Description (juste après le message officiel) ─────────────────
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Description',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  Text(p.description,
                      style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Poppins',
                          height: 1.7)),
                ]),
              ),
            ],

            // Main info card
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title + Status
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(p.title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                            color: AppTheme.textPrimary)),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(p.status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _statusColor(p.status).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                        p.status == 'Actif' ? 'Disponible' : p.status,
                        style: TextStyle(
                            fontSize: 11,
                            color: _statusColor(p.status),
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins')),
                  ),
                ]),
                const SizedBox(height: 10),

                // Location
                Row(children: [
                  const Icon(Icons.location_on_rounded,
                      size: 15, color: AppTheme.accentColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${p.address.isNotEmpty ? "${p.address}, " : ""}${p.commune}, ${p.city}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Poppins'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Price + Views
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Pour Appartement avec les deux tarifs, affichage spécial
                    if (p.type.contains('Appartement') &&
                        p.transactionType == 'Location' &&
                        p.pricePeriod == 'both' &&
                        p.pricePerDay != null) ...[
                      // Tarif mensuel
                      RichText(text: TextSpan(children: [
                        TextSpan(
                            text: p.formattedPrice,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800,
                                color: AppTheme.accentColor, fontFamily: 'Poppins')),
                        const TextSpan(
                            text: ' / mois',
                            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary,
                                fontFamily: 'Poppins')),
                      ])),
                      const SizedBox(height: 2),
                      // Tarif journalier
                      RichText(text: TextSpan(children: [
                        TextSpan(
                            text: '${p.pricePerDay!.toInt()} ${p.currency}',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700,
                                color: Colors.orange.shade600, fontFamily: 'Poppins')),
                        const TextSpan(
                            text: ' / jour',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                                fontFamily: 'Poppins')),
                      ])),
                    ] else ...[
                    Text(p.formattedPrice,
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentColor,
                            fontFamily: 'Poppins')),
                    if (p.transactionType == 'Location') ...[
                      Text(
                        p.type == 'Chambre d\'hôtel'
                            ? 'par nuitée'
                            : (p.type == 'Salle de Fêtes' ||
                               p.type == 'Espace Funéraire' ||
                               p.type == 'Salle polyvalente')
                                ? 'par jour'
                                : p.type.contains('Appartement')
                                    ? (p.pricePeriod == 'journalier' ? 'par jour' : 'par mois')
                                    : 'par mois',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontFamily: 'Poppins')),
                      if (p.type != 'Chambre d\'hôtel' &&
                          p.type != 'Salle de Fêtes' &&
                          p.type != 'Espace Funéraire' &&
                          p.type != 'Salle polyvalente') ...[  
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (p.garantieMois != null && p.garantieMois! > 0)
                                ? AppTheme.accentColor.withValues(alpha: 0.08)
                                : AppTheme.textHint.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (p.garantieMois != null && p.garantieMois! > 0)
                                  ? AppTheme.accentColor.withValues(alpha: 0.3)
                                  : AppTheme.textHint.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.security_rounded,
                                size: 12,
                                color: (p.garantieMois != null && p.garantieMois! > 0)
                                    ? AppTheme.accentColor
                                    : AppTheme.textHint),
                            const SizedBox(width: 4),
                            Text(
                              (p.garantieMois != null && p.garantieMois! > 0)
                                  ? '${p.garantieMois} mois de garantie'
                                  : '0 mois de garantie',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (p.garantieMois != null && p.garantieMois! > 0)
                                    ? AppTheme.accentColor
                                    : AppTheme.textHint,
                              ),
                            ),
                          ]),
                        ),
                      ],
                      if (p.hasCommission &&
                          p.type != 'Chambre d\'hôtel' &&
                          p.type != 'Salle de Fêtes' &&
                          p.type != 'Espace Funéraire' &&
                          p.type != 'Salle polyvalente') ...[  
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF6A1B9A).withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.handshake_rounded,
                                size: 12, color: Color(0xFF6A1B9A)),
                            const SizedBox(width: 4),
                            Text(
                              p.commissionPct != null
                                  ? 'Commission : ${p.commissionPct!.toStringAsFixed(0)} % du loyer'
                                  : 'Commission incluse',
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6A1B9A)),
                            ),
                          ]),
                        ),
                      ],
                    ],
                    ], // ferme le bloc else du prix appartement both
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(children: [
                      const Icon(Icons.visibility_outlined,
                          size: 14, color: AppTheme.textHint),
                      const SizedBox(width: 4),
                      Text('$_views vue${_views != 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textHint,
                              fontFamily: 'Poppins')),
                    ]),
                    const SizedBox(height: 3),
                    Text(_formatDate(p.createdAt),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textHint,
                            fontFamily: 'Poppins')),
                  ]),
                ]),
              ]),
            ),

            // Caractéristiques
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Caractéristiques',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _featureTile(Icons.category_outlined, 'Type', p.type),
                    _featureTile(Icons.swap_horiz_rounded, 'Transaction', p.transactionType),
                    if (p.surface != null)
                      _featureTile(Icons.square_foot_rounded, 'Surface',
                          '${p.surface!.toInt()} m\u00b2'),
                    if (p.bedrooms != null && p.bedrooms! > 0)
                      _featureTile(Icons.bed_outlined, 'Chambres', '${p.bedrooms}'),
                    if (p.bathrooms != null && p.bathrooms! > 0)
                      _featureTile(Icons.bathtub_outlined, 'Salles de bain', '${p.bathrooms}'),
                    if (p.floors != null)
                      _featureTile(Icons.layers_outlined, 'Etages', '${p.floors}'),
                    if (p.numberOfBeds != null && p.numberOfBeds! > 0)
                      _featureTile(Icons.single_bed_rounded, 'Lits', '${p.numberOfBeds}'),
                    if (p.capacity != null && p.capacity! > 0)
                      _featureTile(Icons.event_seat_rounded, 'Capacite',
                          '${p.capacity} places'),
                    _featureTile(Icons.local_parking_rounded, 'Parking',
                        p.hasParking ? 'Oui' : 'Non'),
                    _featureTile(Icons.electric_bolt_rounded, 'Groupe \u00c9lectrog\u00e8ne',
                        p.hasElectricity ? 'Oui' : 'Non'),
                    _featureTile(Icons.security_rounded, 'S\u00e9curit\u00e9 24h/24',
                        p.hasWater ? 'Oui' : 'Non'),
                    if (p.garantieMois != null && p.garantieMois! > 0)
                      _featureTile(Icons.security_rounded, 'Garantie',
                          '${p.garantieMois} mois'),
                    if (p.hasCommission)
                      _featureTile(Icons.handshake_rounded, 'Commission',
                          p.commissionPct != null
                              ? '${p.commissionPct!.toStringAsFixed(0)} % du loyer'
                              : 'Oui'),
                  ],
                ),

                // ── Équipements & Services déclarés par l'annonceur ──────────
                if (p.amenities.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 14),
                  const Text('Équipements & Services',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: p.amenities
                        .map((a) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppTheme.accentColor.withValues(alpha: 0.2)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.check_circle_rounded,
                                    size: 13, color: AppTheme.accentColor),
                                const SizedBox(width: 5),
                                Text(a,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Poppins')),
                              ]),
                            ))
                        .toList(),
                  ),
                ],
              ]),
            ),

            // Annonceur + contact buttons
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Annonceur',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // ── Avatar initiale ──────────────────────────────────────
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.accentColor.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        p.ownerName.isNotEmpty ? p.ownerName[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentColor,
                            fontFamily: 'Poppins',
                            fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // ── Nom + Téléphone + Badge catégorie (Expanded) ──────────
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.ownerName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                              color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      if (p.ownerPhone.isNotEmpty)
                        MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                          onTap: () => _copyToClipboard(p.ownerPhone, 'Numero'),
                          child: Row(children: [
                            const Icon(Icons.phone_rounded,
                                size: 13, color: AppTheme.accentColor),
                            const SizedBox(width: 4),
                            Text(p.ownerPhone,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.accentColor,
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600)),
                          ]),
                        )),
                      // ── Badge catégorie annonceur ──────────────────────────
                      if (p.ownerCategory.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Builder(builder: (ctx) {
                          Color badgeColor;
                          IconData badgeIcon;
                          switch (p.ownerCategory) {
                            case 'Agence Immobilière':
                              badgeColor = const Color(0xFF1565C0);
                              badgeIcon = Icons.business_rounded;
                            case 'Commissionnaire':
                              badgeColor = const Color(0xFF6A1B9A);
                              badgeIcon = Icons.handshake_rounded;
                            default: // Propriétaire
                              badgeColor = const Color(0xFF2E7D32);
                              badgeIcon = Icons.person_rounded;
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(badgeIcon, size: 11, color: badgeColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  p.ownerCategory,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: badgeColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                          );
                        }),
                      ],
                    ]),
                  ),

                  // ── Badge ancienneté — trailing à droite ─────────────────
                  const SizedBox(width: 10),
                  if (!_ownerSinceLoaded)
                    // Skeleton pendant le chargement
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.textHint.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.textHint),
                        ),
                      ),
                    )
                  else if (_ownerSince.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.25),
                            width: 1.2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.verified_rounded,
                            size: 11, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          _ownerSince,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor),
                        ),
                      ]),
                    ),
                ]),

                // WhatsApp + Call buttons (non-owner only)
                if (!isOwner) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppTheme.dividerColor),
                  const SizedBox(height: 14),
                  _buildContactButtons(
                    phone: p.ownerPhone,
                    whatsapp: p.ownerWhatsApp,
                  ),
                ],
              ]),
            ),

            // Expiry info (owner only)
            if (isOwner && p.expiresAt != null) ...[
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded,
                      color: AppTheme.accentColor, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    'Annonce valide jusqu\'au ${_formatDate(p.expiresAt!)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppTheme.accentColor,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 30),
            ],
          ),
        ),
      ),

    );
  }

  // -------------------------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------------------------

  /// Native share sheet — partage le lien web de l'annonce avec titre et référence
  Future<void> _shareProperty(PropertyModel p) async {
    final ref = 'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final text = '${p.title} — Réf. $ref\n$link';
    await SharePlus.instance.share(
      ShareParams(text: text),
    );
  }

  /// Fullscreen zoom viewer — image centrée, nav prev/next, zoom pinch, compteur
  void _openImageFullscreen(BuildContext context, List<String> images, int initialIndex) {
    if (images.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenGallery(
          images: images,
          initialIndex: initialIndex,
          buildImage: _buildPropertyImage,
        ),
      ),
    );
  }

  /// Dual contact buttons: WhatsApp (green) + Call (primary color)
  Widget _buildContactButtons({required String phone, required String whatsapp}) {
    final effectivePhone = phone.isNotEmpty ? phone : '';
    final effectiveWa = whatsapp.isNotEmpty ? whatsapp : phone;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: effectiveWa.isNotEmpty ? () => _openWhatsApp(effectiveWa) : null,
            icon: const Icon(Icons.chat_rounded, size: 18, color: Colors.white),
            label: const Text('WhatsApp',
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              shadowColor: const Color(0xFF25D366).withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: effectivePhone.isNotEmpty ? () => _callPhone(effectivePhone) : null,
            icon: const Icon(Icons.phone_rounded, size: 18, color: Colors.white),
            label: const Text('Appeler',
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              shadowColor: AppTheme.primaryColor.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }

  /// Open WhatsApp with pre-filled message
  Future<void> _openWhatsApp(String phone) async {
    final p = widget.property;
    // ── Log du clic WhatsApp dans Firestore ──────────────────────────
    final auth = context.read<AuthProvider>();
    _ds.logContactClick(
      propertyId:    p.id,
      propertyTitle: p.title,
      ownerId:       p.ownerId,
      type:          'whatsapp',
      visitorId:     auth.currentUser?.id,
    );
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final number = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
    if (number.isEmpty) {
      _showCopyFallback(phone);
      return;
    }
    final ref = 'IZ${p.id.length >= 4 ? p.id.substring(p.id.length - 4).toUpperCase() : p.id.toUpperCase()}';
    final link = '${AppConstants.webBaseUrl}/property/${p.id}';
    final message = Uri.encodeComponent(
        'Bonjour, je suis int\u00e9ress\u00e9(e) par votre annonce r\u00e9f. $ref '
        '"${p.title}" \u00e0 ${p.city}.\n'
        'Est-elle toujours disponible ?\n\n'
        'Voir l\u2019annonce : $link');
    final nativeUri = Uri.parse('whatsapp://send?phone=$number&text=$message');
    try {
      await launchUrl(nativeUri, mode: LaunchMode.externalNonBrowserApplication);
      return;
    } catch (_) {}
    try {
      await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
    final webUri = Uri.parse('https://wa.me/$number?text=$message');
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}
    _showCopyFallback(phone);
  }

  void _showCopyFallback(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('WhatsApp indisponible \u2014 Num\u00e9ro copi\u00e9 : $phone',
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFF25D366),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// Phone call with clipboard fallback
  Future<void> _callPhone(String phone) async {
    // ── Log du clic Appel dans Firestore ─────────────────────────────
    final auth = context.read<AuthProvider>();
    final p = widget.property;
    _ds.logContactClick(
      propertyId:    p.id,
      propertyTitle: p.title,
      ownerId:       p.ownerId,
      type:          'call',
      visitorId:     auth.currentUser?.id,
    );
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!cleaned.startsWith('+') && !cleaned.startsWith('00')) {
      cleaned = '+$cleaned';
    }
    final uri = Uri.parse('tel:$cleaned');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _copyToClipboard(phone, 'Num\u00e9ro');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Appel impossible \u2014 Num\u00e9ro copi\u00e9 : $phone',
            style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  /// Compact chip for each property characteristic
  Widget _featureTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppTheme.accentColor),
        const SizedBox(width: 5),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 10, color: AppTheme.textHint, fontFamily: 'Poppins')),
        Text(value,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
                color: AppTheme.textPrimary)),
      ]),
    );
  }

  /// Render a property image from base64, local file, or network URL
  // ── Wide screen photo grid (≥768px) ────────────────────────────────────────
  // Grille centrée max 900px : 1 grande photo à gauche + 2 petites à droite
  // Fond blanc + marges latérales — image complète sans distorsion
  Widget _buildWidePhotoGrid(PropertyModel p) {
    final images = p.images.isNotEmpty ? p.images : <String>[];
    final total = images.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: total == 0
                  // ── Aucune image ───────────────────────────────────────────
                  ? Container(
                      height: 340,
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      child: const Center(
                        child: Icon(Icons.home_work_outlined,
                            size: 80, color: AppTheme.accentColor),
                      ),
                    )
                  : total == 1
                      // ── Une seule image: centrée, ratio préservé ───────────
                      ? MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                          onTap: () => _openImageFullscreen(context, images, 0),
                          child: SizedBox(
                            height: 340,
                            width: double.infinity,
                            child: _buildPropertyImageContained(images[0]),
                          ),
                        ))
                      // ── 2+ images: grande à gauche + 1 ou 2 petites à droite
                      : SizedBox(
                          height: 340,
                          child: Stack(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Grande image gauche (60% de la largeur)
                                  Expanded(
                                    flex: 60,
                                    child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                                      onTap: () => _openImageFullscreen(context, images, 0),
                                      child: _buildPropertyImageCover(images[0]),
                                    )),
                                  ),
                                  const SizedBox(width: 4),
                                  // Colonne droite (40% de la largeur)
                                  Expanded(
                                    flex: 40,
                                    child: Column(
                                      children: [
                                        // Petite image haute
                                        Expanded(
                                          child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                                            onTap: () => _openImageFullscreen(context, images, 1),
                                            child: _buildPropertyImageCover(images[1]),
                                          )),
                                        ),
                                        if (total >= 3) ...[
                                          const SizedBox(height: 4),
                                          // Petite image basse
                                          Expanded(
                                            child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                                              onTap: () => _openImageFullscreen(context, images, 2),
                                              child: _buildPropertyImageCover(images[2]),
                                            )),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Badge transaction (Vente / Location)
                              Positioned(
                                top: 12, left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: p.transactionType == 'Vente'
                                        ? AppTheme.primaryColor
                                        : AppTheme.successColor,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Text(p.transactionType,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'Poppins')),
                                ),
                              ),
                              // Badge "Voir toutes les photos"
                              if (total > 3)
                                Positioned(
                                  bottom: 12, right: 12,
                                  child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                                    onTap: () => _openImageFullscreen(context, images, 0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.72),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.photo_library_outlined,
                                            size: 14, color: Colors.white),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Voir les $total photos',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ]),
                                    ),
                                  )),
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

  /// Image avec BoxFit.cover (pour remplir une cellule de la grille)
  Widget _buildPropertyImageCover(String src) {
    final placeholder = Container(
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.home_work_outlined, size: 48, color: AppTheme.accentColor),
      ),
    );
    if (src.startsWith('data:image/')) {
      try {
        final ci = src.indexOf(',');
        if (ci == -1) return placeholder;
        final bytes = base64Decode(src.substring(ci + 1));
        return Image.memory(bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => placeholder);
      } catch (_) { return placeholder; }
    }
    if (!kIsWeb && !src.startsWith('http')) {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => placeholder);
      }
      return placeholder;
    }
    return Image.network(src,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            child: const Center(child: CircularProgressIndicator(
                color: AppTheme.accentColor, strokeWidth: 2)),
          );
        });
  }

  /// Image avec BoxFit.contain (pour image unique, ratio préservé, fond blanc)
  Widget _buildPropertyImageContained(String src) {
    final placeholder = Container(
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.home_work_outlined, size: 80, color: AppTheme.accentColor),
      ),
    );
    if (src.startsWith('data:image/')) {
      try {
        final ci = src.indexOf(',');
        if (ci == -1) return placeholder;
        final bytes = base64Decode(src.substring(ci + 1));
        return Image.memory(bytes,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => placeholder);
      } catch (_) { return placeholder; }
    }
    if (!kIsWeb && !src.startsWith('http')) {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(file,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => placeholder);
      }
      return placeholder;
    }
    return Image.network(src,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            child: const Center(child: CircularProgressIndicator(
                color: AppTheme.accentColor, strokeWidth: 2)),
          );
        });
  }

  Widget _buildPropertyImage(String src) {
    final placeholder = Container(
      color: AppTheme.primaryColor,
      child: const Center(
        child: Icon(Icons.home_work_outlined, size: 80, color: AppTheme.accentColor),
      ),
    );

    if (src.startsWith('data:image/')) {
      try {
        final commaIndex = src.indexOf(',');
        if (commaIndex == -1) return placeholder;
        final bytes = base64Decode(src.substring(commaIndex + 1));
        return Image.memory(bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => placeholder);
      } catch (_) {
        return placeholder;
      }
    }

    if (!kIsWeb && !src.startsWith('http')) {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(file,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => placeholder);
      }
      return placeholder;
    }

    return Image.network(
      src,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppTheme.primaryColor,
          child: const Center(
            child: CircularProgressIndicator(
                color: AppTheme.accentColor, strokeWidth: 2),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

}

// ═══════════════════════════════════════════════════════════════════════════
// FULLSCREEN GALLERY — image centrée sur fond noir, nav prev/next, zoom
// ═══════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
// FULLSCREEN GALLERY
//  • BoxFit.contain → image JAMAIS coupée, fond noir remplit les vides
//  • Barre zoom +/- avec pourcentage (100% → 400%) en bas au centre
//  • Prev / Next arrows, compteur N/Total, bouton X fermer
// ═══════════════════════════════════════════════════════════════════════════
class _FullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final Widget Function(String) buildImage;

  const _FullscreenGallery({
    required this.images,
    required this.initialIndex,
    required this.buildImage,
  });

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _current;
  late PageController _ctrl;
  // Niveau de zoom courant (1.0 = 100%)
  double _zoomLevel = 1.0;
  static const double _zoomMin = 1.0;
  static const double _zoomMax = 4.0;
  static const double _zoomStep = 0.5;

  // Taille du viewport capturée via LayoutBuilder — nécessaire pour centrer le zoom
  Size _viewportSize = Size.zero;

  // TransformationController par page pour appliquer le zoom programmatiquement
  final List<TransformationController> _transforms = [];

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
    for (int i = 0; i < widget.images.length; i++) {
      _transforms.add(TransformationController());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    for (final t in _transforms) t.dispose();
    super.dispose();
  }

  /// Applique le zoom centré sur le milieu du viewport.
  /// Technique : T(center) × Scale(s) × T(-center)
  /// Cela étire/rétracte l'image également dans toutes les directions.
  void _applyZoom(double level) {
    final scale = level.clamp(_zoomMin, _zoomMax);
    setState(() => _zoomLevel = scale);

    // Centre du viewport en coordonnées scene (au niveau de zoom 1.0)
    final cx = _viewportSize.width / 2.0;
    final cy = _viewportSize.height / 2.0;

    // Matrice : T(center) × Scale × T(-center) — zoom centré sur le milieu de l'écran
    // Chaque coin s'éloigne de façon équitable vers l'extérieur.
    // On compose les 3 matrices sans utiliser les méthodes dépréciées (.translate/.scale).
    final tPlus  = Matrix4.translationValues(cx, cy, 0);
    final tMinus = Matrix4.translationValues(-cx, -cy, 0);
    final scaleM = Matrix4.diagonal3Values(scale, scale, 1.0);
    final matrix = tPlus * scaleM * tMinus;

    _transforms[_current].value = matrix;
  }

  void _resetZoom() {
    setState(() => _zoomLevel = 1.0);
    _transforms[_current].value = Matrix4.identity();
  }

  void _zoomIn() => _applyZoom(_zoomLevel + _zoomStep);
  void _zoomOut() => _applyZoom(_zoomLevel - _zoomStep);

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;
    final zoomPct = (_zoomLevel * 100).round();
    final atMin = _zoomLevel <= _zoomMin;
    final atMax = _zoomLevel >= _zoomMax;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, constraints) {
        // Capturer la taille du viewport pour centrer le zoom correctement
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final newSize = Size(constraints.maxWidth, constraints.maxHeight);
          if (newSize != _viewportSize) {
            _viewportSize = newSize;
          }
        });
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(children: [

        // ── PageView — image centrée, BoxFit.contain via _buildContainImage ──
        PageView.builder(
          controller: _ctrl,
          itemCount: total,
          // Désactiver le scroll lateral quand on est zoomé (évite conflit)
          physics: _zoomLevel > 1.0 ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          onPageChanged: (i) {
            _resetZoom();
            setState(() => _current = i);
          },
          // pageSnapping + scroll custom pour une transition smooth
          pageSnapping: true,
          itemBuilder: (_, i) => InteractiveViewer(
            transformationController: _transforms[i],
            minScale: _zoomMin,
            maxScale: _zoomMax,
            // Désactiver le zoom pinch — géré par les boutons +/-
            panEnabled: _zoomLevel > 1.0,
            scaleEnabled: false,
            clipBehavior: Clip.none,
            child: SizedBox.expand(
              child: Center(
                // ── BoxFit.contain : image complète, jamais coupée ──────────
                child: _buildContainImage(widget.images[i]),
              ),
            ),
          ),
        ),

        // ── Close button (top-right) ──────────────────────────────────────
        Positioned(
          top: 44, right: 16,
          child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.70),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 1),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          )),
        ),

        // ── Page counter (top-left) ────────────────────────────────────────
        if (total > 1)
          Positioned(
            top: 48, left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Text(
                '${_current + 1} / $total',
                style: const TextStyle(
                  color: Colors.white, fontFamily: 'Poppins',
                  fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        // ── Prev arrow ────────────────────────────────────────────────────
        if (total > 1 && _current > 0)
          Positioned(
            left: 8, top: 0, bottom: 80,
            child: Center(
              child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                onTap: () {
                  _ctrl.animateToPage(
                    _current - 1,
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeInOutCubic,
                  );
                },
                child: Container(
                  width: 40, height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 32),
                ),
              )),
            ),
          ),

        // ── Next arrow ────────────────────────────────────────────────────
        if (total > 1 && _current < total - 1)
          Positioned(
            right: 8, top: 0, bottom: 80,
            child: Center(
              child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                onTap: () {
                  _ctrl.animateToPage(
                    _current + 1,
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeInOutCubic,
                  );
                },
                child: Container(
                  width: 40, height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 32),
                ),
              )),
            ),
          ),

        // ── Barre zoom +/- avec pourcentage (bas, centrée) ───────────────
        Positioned(
          bottom: 20, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // Bouton —
                MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                  onTap: atMin ? null : _zoomOut,
                  child: AnimatedOpacity(
                    opacity: atMin ? 0.35 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: atMin
                            ? Colors.white10
                            : AppTheme.primaryColor.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.remove_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                )),
                const SizedBox(width: 10),
                // Label pourcentage
                SizedBox(
                  width: 56,
                  child: Text(
                    '$zoomPct%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Bouton +
                MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                  onTap: atMax ? null : _zoomIn,
                  child: AnimatedOpacity(
                    opacity: atMax ? 0.35 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: atMax
                            ? Colors.white10
                            : AppTheme.primaryColor.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                )),
                // Bouton reset (visible seulement si zoomé)
                if (_zoomLevel > 1.0) ...[
                  const SizedBox(width: 8),
                  MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                    onTap: _resetZoom,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(
                        child: Text('Reset', style: TextStyle(
                          color: Colors.white, fontFamily: 'Poppins',
                          fontSize: 11, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  )),
                ],
              ]),
            ),
          ),
        ),
      ]);   // fin Stack
      }), // fin LayoutBuilder
    );
  }

  /// Construit l'image avec BoxFit.contain — jamais coupée, fond noir
  Widget _buildContainImage(String src) {
    final placeholder = Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.broken_image_outlined, size: 64, color: Colors.white24),
      ),
    );

    if (src.startsWith('data:image/')) {
      try {
        final ci = src.indexOf(',');
        if (ci == -1) return placeholder;
        final bytes = base64Decode(src.substring(ci + 1));
        return Image.memory(bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => placeholder);
      } catch (_) {
        return placeholder;
      }
    }

    if (!kIsWeb && !src.startsWith('http')) {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => placeholder);
      }
      return placeholder;
    }

    return Image.network(src,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(
                  color: Colors.white38, strokeWidth: 2),
            ),
          );
        });
  }
}
