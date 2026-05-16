import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../../models/property_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/data_service.dart';
import '../../auth/login_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _checkFavorite();
    _loadOfficialMessage();
    _loadOwnerSince();
  }

  Future<void> _loadOwnerSince() async {
    final owner = await _ds.getUserById(widget.property.ownerId);
    if (owner == null || !mounted) return;
    final now = DateTime.now();
    final diff = now.difference(owner.createdAt);
    final totalMonths = (diff.inDays / 30.44).floor();
    String label;
    if (totalMonths < 1) {
      label = 'Nouveau';
    } else if (totalMonths < 12) {
      label = '$totalMonths mois';
    } else {
      final years = totalMonths ~/ 12;
      final months = totalMonths % 12;
      label = months > 0 ? '$years an${years > 1 ? 's' : ''} $months mois' : '$years an${years > 1 ? 's' : ''}';
    }
    setState(() => _ownerSince = label);
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
      body: CustomScrollView(
        slivers: [
          // ── Image Sliver AppBar ───────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(_isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isFavorite ? Colors.redAccent : Colors.white),
                onPressed: _toggleFavorite,
                tooltip: 'Ajouter aux favoris',
              ),
              IconButton(
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => _copyToClipboard(
                    'ImmoZone — ${p.title} | ${p.formattedPrice} | ${p.city}',
                    'Lien de l\'annonce'),
                tooltip: 'Partager',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // Images PageView
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: p.images.isNotEmpty ? p.images.length : 1,
                    onPageChanged: (i) => setState(() => _currentImageIndex = i),
                    itemBuilder: (_, i) {
                      final img = p.images.isNotEmpty
                          ? p.images[i]
                          : AppConstants.placeholderProperty;
                      return InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: _buildPropertyImage(img),
                      );
                    },
                  ),
                  // Gradient bas
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  // Image indicators
                  if (p.images.length > 1)
                    Positioned(
                      bottom: 12, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(p.images.length, (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _currentImageIndex == i ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _currentImageIndex == i ? AppTheme.accentColor : Colors.white60,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
                      ),
                    ),
                  // Transaction Badge
                  Positioned(
                    bottom: 40, left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.transactionType == 'Vente'
                            ? AppTheme.primaryColor : AppTheme.successColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6)],
                      ),
                      child: Text(p.transactionType,
                          style: const TextStyle(color: Colors.white, fontSize: 12,
                              fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
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
                          const Icon(Icons.photo_library_outlined, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('${_currentImageIndex + 1}/${p.images.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 11,
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(children: [

              // ── MESSAGE OFFICIEL IMMOZONE ───────────────────────────────
              if (_officialMessage.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _messageExpanded = !_messageExpanded),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.5), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2),
                            blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.verified_rounded,
                              color: AppTheme.accentColor, size: 16),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Message Officiel ImmoZone',
                              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                                  fontSize: 12, color: AppTheme.accentColor)),
                        ),
                        Icon(_messageExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                            color: Colors.white54, size: 18),
                      ]),
                      if (_messageExpanded) ...[
                        const SizedBox(height: 10),
                        const Divider(color: Colors.white12, height: 1),
                        const SizedBox(height: 10),
                        Text(_officialMessage,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                color: Colors.white70, height: 1.6)),
                      ],
                      if (!_messageExpanded) ...[
                        const SizedBox(height: 6),
                        Text(
                          _officialMessage.length > 80
                              ? '${_officialMessage.substring(0, 80)}...'
                              : _officialMessage,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              color: Colors.white54, height: 1.4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ]),
                  ),
                ),

              // ── MAIN INFO CARD ──────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Title + Status
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(p.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins', color: AppTheme.textPrimary)),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(p.status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _statusColor(p.status).withValues(alpha: 0.3)),
                      ),
                      child: Text(p.status,
                          style: TextStyle(fontSize: 11, color: _statusColor(p.status),
                              fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                    ),
                  ]),
                  const SizedBox(height: 10),

                  // Location
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: AppTheme.accentColor),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('${p.address.isNotEmpty ? "${p.address}, " : ""}${p.commune}, ${p.city}',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary,
                              fontFamily: 'Poppins')),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // Price + Views
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.formattedPrice,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                              color: AppTheme.accentColor, fontFamily: 'Poppins')),
                      if (p.transactionType == 'Location') ...[  
                        const Text('par mois',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                                fontFamily: 'Poppins')),
                        ...[  
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
                              Icon(Icons.security_rounded, size: 12,
                                  color: (p.garantieMois != null && p.garantieMois! > 0)
                                      ? AppTheme.accentColor
                                      : AppTheme.textHint),
                              const SizedBox(width: 4),
                              Text(
                                (p.garantieMois != null && p.garantieMois! > 0)
                                    ? '${p.garantieMois} mois de garantie'
                                    : '0 mois de garantie',
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: (p.garantieMois != null && p.garantieMois! > 0)
                                      ? AppTheme.accentColor
                                      : AppTheme.textHint,
                                ),
                              ),
                            ]),
                          ),
                        ],
                        if (p.hasCommission) ...[  
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.handshake_rounded, size: 12, color: Color(0xFF6A1B9A)),
                              const SizedBox(width: 4),
                              Text(
                                p.commissionPct != null
                                    ? 'Commission : ${p.commissionPct!.toStringAsFixed(0)} % du loyer'
                                    : 'Commission incluse',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                                    fontWeight: FontWeight.w600, color: Color(0xFF6A1B9A)),
                              ),
                            ]),
                          ),
                        ],
                      ],
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Row(children: [
                        const Icon(Icons.visibility_outlined, size: 14, color: AppTheme.textHint),
                        const SizedBox(width: 4),
                        Text('${p.views} vues',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textHint,
                                fontFamily: 'Poppins')),
                      ]),
                      const SizedBox(height: 3),
                      Text(_formatDate(p.createdAt),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textHint,
                              fontFamily: 'Poppins')),
                    ]),
                  ]),
                ]),
              ),

              // ── CARACTERISTIQUES ────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Caracteristiques',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins', color: AppTheme.textPrimary)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _featureTile(Icons.category_outlined, 'Type', p.type),
                      _featureTile(Icons.swap_horiz_rounded, 'Transaction', p.transactionType),
                      if (p.surface != null)
                        _featureTile(Icons.square_foot_rounded, 'Surface', '${p.surface!.toInt()} m²'),
                      if (p.bedrooms != null && p.bedrooms! > 0)
                        _featureTile(Icons.bed_outlined, 'Chambres', '${p.bedrooms}'),
                      if (p.bathrooms != null && p.bathrooms! > 0)
                        _featureTile(Icons.bathtub_outlined, 'Salles de bain', '${p.bathrooms}'),
                      if (p.floors != null)
                        _featureTile(Icons.layers_outlined, 'Etages', '${p.floors}'),
                      if (p.numberOfBeds != null && p.numberOfBeds! > 0)
                        _featureTile(Icons.single_bed_rounded, 'Lits', '${p.numberOfBeds}'),
                      if (p.capacity != null && p.capacity! > 0)
                        _featureTile(Icons.event_seat_rounded, 'Capacite', '${p.capacity} places'),
                      _featureTile(Icons.local_parking_rounded, 'Parking',
                          p.hasParking ? 'Oui' : 'Non'),
                      _featureTile(Icons.electric_bolt_rounded, 'Groupe Électrogène',
                          p.hasElectricity ? 'Oui' : 'Non'),
                      _featureTile(Icons.security_rounded, 'Sécurité 24h/24',
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
                ]),
              ),
              const SizedBox(height: 12),

              // ── DESCRIPTION ─────────────────────────────────────────────
              if (p.description.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Description',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins', color: AppTheme.textPrimary)),
                    const SizedBox(height: 10),
                    Text(p.description,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary,
                            fontFamily: 'Poppins', height: 1.7)),
                  ]),
                ),

              // ── EQUIPEMENTS ─────────────────────────────────────────────
              if (p.amenities.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Equipements & Services',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins', color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: p.amenities.map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.accentColor),
                          const SizedBox(width: 5),
                          Text(a, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w500, fontFamily: 'Poppins')),
                        ]),
                      )).toList(),
                    ),
                  ]),
                ),
              ],

              // ── ANNONCEUR / CONTACT ─────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Annonceur',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins', color: AppTheme.textPrimary)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.4), width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          p.ownerName.isNotEmpty ? p.ownerName[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w800,
                              color: AppTheme.accentColor, fontFamily: 'Poppins', fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(p.ownerName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                    fontFamily: 'Poppins', color: AppTheme.textPrimary),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (_ownerSince.isNotEmpty) ...
                            [
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.verified_user_rounded,
                                      size: 10, color: AppTheme.accentColor),
                                  const SizedBox(width: 3),
                                  Text(_ownerSince,
                                      style: const TextStyle(
                                          fontFamily: 'Poppins', fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.accentColor)),
                                ]),
                              ),
                            ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      if (p.ownerPhone.isNotEmpty)
                        GestureDetector(
                          onTap: () => _copyToClipboard(p.ownerPhone, 'Numero'),
                          child: Row(children: [
                            const Icon(Icons.phone_rounded, size: 13, color: AppTheme.accentColor),
                            const SizedBox(width: 4),
                            Text(p.ownerPhone,
                                style: const TextStyle(fontSize: 12, color: AppTheme.accentColor,
                                    fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                          ]),
                        ),
                    ])),
                  ]),

                  // Bouton WhatsApp unique
                  if (!isOwner) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: AppTheme.dividerColor),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: _whatsappButton(
                        p.ownerWhatsApp.isNotEmpty ? p.ownerWhatsApp : p.ownerPhone,
                      ),
                    ),
                  ],
                ]),
              ),

              // ── INFORMATIONS COMPLEMENTAIRES (visible propriétaire uniquement) ─
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
                    const Icon(Icons.schedule_rounded, color: AppTheme.accentColor, size: 16),
                    const SizedBox(width: 10),
                    Text('Annonce valide jusqu\'au ${_formatDate(p.expiresAt!)}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],

              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),

      // ── BOTTOM BAR ─────────────────────────────────────────────────────────
      // Non-propriétaires : le bouton WhatsApp est dans le contenu défilant,
      // pas besoin d'une barre fixe en bas.
      // Propriétaires : panneau informatif seulement.
      bottomNavigationBar: isOwner
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12, offset: const Offset(0, -3))],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.person_pin_rounded, color: AppTheme.accentColor, size: 18),
                  SizedBox(width: 8),
                  Text('Votre annonce — gérable depuis votre tableau de bord',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                ]),
              ),
            )
          : null,
    );
  }

  /// Ouvre WhatsApp avec le numéro du propriétaire
  Future<void> _openWhatsApp(String phone) async {
    final p = widget.property;

    // ── Nettoyage du numéro ──────────────────────────────────────────────────
    // Supprimer espaces, tirets, parenthèses, garder le +
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Pour wa.me et whatsapp:// le numéro doit être SANS le + (ex: 243812345678)
    final number = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;

    if (number.isEmpty) {
      _showCopyFallback(phone);
      return;
    }

    final message = Uri.encodeComponent(
        'Bonjour, je suis intéressé(e) par votre annonce "${p.title}" à ${p.city}. '
        'Est-elle toujours disponible ?');

    // ── Essai 1 : Intent natif whatsapp:// ───────────────────────────────────
    // Sur Android, c'est le plus fiable — ouvre directement WhatsApp sans browser
    final nativeUri = Uri.parse('whatsapp://send?phone=$number&text=$message');
    try {
      // On tente directement sans canLaunchUrl (qui retourne false sur certains ROM)
      await launchUrl(nativeUri, mode: LaunchMode.externalNonBrowserApplication);
      return;
    } catch (_) {}

    // ── Essai 2 : whatsapp:// avec externalApplication ───────────────────────
    try {
      await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}

    // ── Essai 3 : wa.me via navigateur (fonctionne même sans WhatsApp installé)
    final webUri = Uri.parse('https://wa.me/$number?text=$message');
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}

    // ── Fallback final : copier le numéro ────────────────────────────────────
    _showCopyFallback(phone);
  }

  void _showCopyFallback(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'WhatsApp indisponible — Numéro copié : $phone',
        style: const TextStyle(fontFamily: 'Poppins'),
      ),
      backgroundColor: const Color(0xFF25D366),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _whatsappButton(String phone, {bool fullWidth = false}) {
    if (phone.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton.icon(
        onPressed: () => _openWhatsApp(phone),
        icon: const Icon(Icons.chat_rounded, size: 20, color: Colors.white),
        label: const Text('Contacter sur WhatsApp',
            style: TextStyle(fontSize: 14, fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// Chip compact horizontal — toutes les caractéristiques sur la même ligne
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
            style: const TextStyle(fontSize: 10, color: AppTheme.textHint,
                fontFamily: 'Poppins')),
        Text(value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                fontFamily: 'Poppins', color: AppTheme.textPrimary)),
      ]),
    );
  }

  /// Affiche image : base64 (data URI), URL réseau, ou fichier local
  Widget _buildPropertyImage(String src) {
    final _placeholder = Container(
      color: AppTheme.primaryColor,
      child: const Center(
        child: Icon(Icons.home_work_outlined,
            size: 80, color: AppTheme.accentColor),
      ),
    );

    // ── Base64 (stocké dans Firestore, visible sur tous les appareils) ──────
    if (src.startsWith('data:image/')) {
      try {
        final commaIndex = src.indexOf(',');
        if (commaIndex == -1) return _placeholder;
        final b64str = src.substring(commaIndex + 1);
        final bytes = base64Decode(b64str);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _placeholder,
        );
      } catch (_) {
        return _placeholder;
      }
    }

    // ── Fichier local (uniquement sur l'appareil de l'annonceur) ─────────────
    if (!kIsWeb && !src.startsWith('http')) {
      final file = File(src);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _placeholder,
        );
      }
      return _placeholder;
    }

    // ── URL réseau (Unsplash, etc.) ───────────────────────────────────────────
    return Image.network(
      src,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, __, ___) => _placeholder,
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

  void _showLoginRequired(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.lock_outline_rounded, color: AppTheme.accentColor, size: 22),
          SizedBox(width: 10),
          Text('Connexion requise',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  fontSize: 15, color: AppTheme.textPrimary)),
        ]),
        content: const Text(
          'Vous devez creer un compte ou vous connecter pour contacter un annonceur.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Se connecter',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
