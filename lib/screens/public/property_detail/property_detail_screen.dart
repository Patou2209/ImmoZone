import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
        title: Image.asset(
          'assets/images/immozone_logo.png',
          height: 44,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => RichText(
            text: const TextSpan(
              style: TextStyle(fontFamily: 'Poppins', fontSize: 17),
              children: [
                TextSpan(text: 'Immo',
                    style: TextStyle(fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                TextSpan(text: 'Zone',
                    style: TextStyle(fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor)),
              ],
            ),
          ),
        ),
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
            icon: const Icon(Icons.ios_share_rounded, color: AppTheme.textSecondary),
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
            // PHOTO GALLERY  (height 280 — starts immediately below the AppBar)
            // ----------------------------------------------------------------
            SizedBox(
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
                      return GestureDetector(
                        onTap: () => _openImageFullscreen(context, p.images, i),
                        child: _buildPropertyImage(img),
                      );
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
                        child: GestureDetector(
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
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8, top: 0, bottom: 0,
                      child: Center(
                        child: GestureDetector(
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
                        ),
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
            ),

            // ----------------------------------------------------------------
            // SCROLLABLE CONTENT  (all cards, margin: symmetric(horizontal:16))
            // ----------------------------------------------------------------

            // Message officiel ImmoZone
            if (_officialMessage.isNotEmpty) ...[  
              const SizedBox(height: 16),
              GestureDetector(
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
              ),

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
                               p.type == 'Salle Polyvalente')
                                ? 'par jour'
                                : 'par mois',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontFamily: 'Poppins')),
                      if (p.type != 'Chambre d\'hôtel' &&
                          p.type != 'Salle de Fêtes' &&
                          p.type != 'Espace Funéraire' &&
                          p.type != 'Salle Polyvalente') ...[  
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
                          p.type != 'Salle Polyvalente') ...[  
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

                  // ── Nom + Téléphone (Expanded) ───────────────────────────
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
                        GestureDetector(
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
                        ),
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

  /// Native share sheet — partage uniquement le lien deep-link
  Future<void> _shareProperty(PropertyModel p) async {
    final link = 'https://immozone.app/property/${p.id}';
    await SharePlus.instance.share(
      ShareParams(text: link),
    );
  }

  /// Fullscreen zoom viewer on image tap
  void _openImageFullscreen(BuildContext context, List<String> images, int initialIndex) {
    if (images.isEmpty) return;
    final pageCtrl = PageController(initialPage: initialIndex);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            PageView.builder(
              controller: pageCtrl,
              itemCount: images.length,
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Center(child: _buildPropertyImage(images[i])),
              ),
            ),
            Positioned(
              top: 40, right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ]),
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
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final number = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
    if (number.isEmpty) {
      _showCopyFallback(phone);
      return;
    }
    final message = Uri.encodeComponent(
        'Bonjour, je suis int\u00e9ress\u00e9(e) par votre annonce "${p.title}" \u00e0 ${p.city}. '
        'Est-elle toujours disponible ?');
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
