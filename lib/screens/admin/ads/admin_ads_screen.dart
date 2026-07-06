import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_model.dart';
import '../../../services/data_service.dart';

class AdminAdsScreen extends StatefulWidget {
  const AdminAdsScreen({super.key});
  @override
  State<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends State<AdminAdsScreen> {
  final DataService _ds = DataService();
  List<AdModel> _ads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ads = await _ds.getAllAds();
    if (mounted) setState(() { _ads = ads; _loading = false; });
  }

  // ── Stats globales ────────────────────────────────────────────────────────
  int get _totalClicks => _ads.fold(0, (s, a) => s + a.clicks);
  int get _totalImpressions => _ads.fold(0, (s, a) => s + a.impressions);
  int get _liveCount => _ads.where((a) => a.isLive).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Publicités',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdForm(context),
        backgroundColor: const Color(0xFFE65100),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle pub',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : Column(children: [
              // ── Bandeau stats globales ─────────────────────────────────
              _buildStatsHeader(),
              // ── Liste des pubs ─────────────────────────────────────────
              Expanded(
                child: _ads.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accentColor,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _ads.length,
                          itemBuilder: (_, i) => _AdTile(
                            ad: _ads[i],
                            onToggle: (v) async {
                              await _ds.toggleAdStatus(_ads[i].id, v);
                              _load();
                            },
                            onEdit: () => _openAdForm(context, ad: _ads[i]),
                            onDelete: () => _confirmDelete(context, _ads[i]),
                          ),
                        ),
                      ),
              ),
            ]),
    );
  }

  Widget _buildStatsHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        _statChip(Icons.campaign_rounded, '$_liveCount active${_liveCount > 1 ? 's' : ''}',
            const Color(0xFF2E7D32)),
        const SizedBox(width: 10),
        _statChip(Icons.touch_app_rounded, '$_totalClicks clics',
            const Color(0xFFE65100)),
        const SizedBox(width: 10),
        _statChip(Icons.visibility_rounded, '$_totalImpressions vues',
            AppTheme.accentColor),
      ]),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.campaign_outlined, size: 72,
            color: AppTheme.textHint.withValues(alpha: 0.4)),
        const SizedBox(height: 16),
        const Text('Aucune publicité créée',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        const Text('Appuyez sur "Nouvelle pub" pour commencer.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textHint)),
      ]),
    );
  }

  // ── Formulaire création / édition ─────────────────────────────────────────
  void _openAdForm(BuildContext context, {AdModel? ad}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdFormSheet(
        ad: ad,
        onSave: (data) async {
          if (ad == null) {
            // Création
            final newAd = AdModel(
              id: '',
              title: data['title'],
              subtitle: data['subtitle'],
              imageUrl: data['imageUrl'],
              linkType: data['linkType'],
              linkValue: data['linkValue'],
              ctaLabel: data['ctaLabel'],
              category: data['category'],
              isActive: data['isActive'],
              startDate: data['startDate'],
              endDate: data['endDate'],
              position: data['position'],
              createdAt: DateTime.now(),
            );
            await _ds.createAd(newAd);
          } else {
            // Édition
            await _ds.updateAd(ad.id, {
              'title': data['title'],
              'subtitle': data['subtitle'],
              'imageUrl': data['imageUrl'],
              'linkType': data['linkType'],
              'linkValue': data['linkValue'],
              'ctaLabel': data['ctaLabel'],
              'category': data['category'],
              'isActive': data['isActive'],
              'startDate': (data['startDate'] as DateTime).toIso8601String(),
              'endDate': (data['endDate'] as DateTime).toIso8601String(),
              'position': data['position'],
            });
          }
          if (mounted) _load();
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AdModel ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la pub',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Supprimer « ${ad.title} » définitivement ?',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Poppins', color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Supprimer',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _ds.deleteAd(ad.id);
      _load();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Tile pub dans la liste admin ──────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════
class _AdTile extends StatelessWidget {
  final AdModel ad;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AdTile({
    required this.ad,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _statusColor => ad.isLive
      ? const Color(0xFF2E7D32)
      : ad.isActive
          ? Colors.orange
          : Colors.grey;

  String get _statusLabel => ad.isLive
      ? 'En ligne'
      : ad.isActive
          ? 'Hors période'
          : 'Désactivée';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ad.isLive
              ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
              : const Color(0xFFE4E8F0),
          width: ad.isLive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_statusLabel,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w700, color: _statusColor)),
            ),
            const SizedBox(width: 8),
            Text(ad.category,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: AppTheme.textSecondary)),
            const Spacer(),
            // Switch activer/désactiver
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: ad.isActive,
                onChanged: onToggle,
                activeColor: const Color(0xFF2E7D32),
              ),
            ),
          ]),
        ),

        // ── Corps ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Miniature image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 70, height: 70,
                child: _buildThumb(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(ad.title,
                  style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: AppTheme.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              if (ad.subtitle.isNotEmpty)
                Text(ad.subtitle,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: AppTheme.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              // Période
              Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 11,
                    color: AppTheme.textHint),
                const SizedBox(width: 4),
                Text(
                  '${_fmt(ad.startDate)} → ${_fmt(ad.endDate)}'
                  '  (${ad.daysLeft}j restants)',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      color: AppTheme.textHint),
                ),
              ]),
              const SizedBox(height: 4),
              // Position
              Row(children: [
                const Icon(Icons.format_list_numbered_rounded, size: 11,
                    color: AppTheme.textHint),
                const SizedBox(width: 4),
                Text('Toutes les ${ad.position} annonces',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        color: AppTheme.textHint)),
              ]),
            ])),
          ]),
        ),

        // ── Stats + Actions ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FC),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
          ),
          child: Row(children: [
            // Stats
            _miniStat(Icons.touch_app_rounded, '${ad.clicks}', 'clics',
                const Color(0xFFE65100)),
            const SizedBox(width: 14),
            _miniStat(Icons.visibility_rounded, '${ad.impressions}', 'vues',
                AppTheme.accentColor),
            const SizedBox(width: 8),
            if (ad.impressions > 0) ...[
              Text('CTR ${ad.ctr.toStringAsFixed(1)}%',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      color: AppTheme.textHint, fontWeight: FontWeight.w600)),
            ],
            const Spacer(),
            // Bouton éditer
            MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_rounded, size: 13, color: AppTheme.accentColor),
                  SizedBox(width: 4),
                  Text('Éditer', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppTheme.accentColor)),
                ]),
              ),
            )),
            const SizedBox(width: 8),
            // Bouton supprimer
            MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_rounded, size: 13, color: AppTheme.errorColor),
                  SizedBox(width: 4),
                  Text('Suppr.', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppTheme.errorColor)),
                ]),
              ),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _miniStat(IconData icon, String val, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text('$val $label',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
              fontWeight: FontWeight.w700, color: color)),
    ]);
  }

  Widget _buildThumb() {
    final src = ad.imageUrl;
    if (src.isEmpty) {
      return Container(
        color: const Color(0xFFF0F4FF),
        child: const Icon(Icons.image_outlined, color: AppTheme.textHint),
      );
    }
    if (src.startsWith('data:image') ||
        (src.length > 200 && !src.startsWith('http'))) {
      try {
        final b64 = src.contains(',') ? src.split(',').last : src;
        return Image.memory(base64Decode(b64), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _thumbFallback());
      } catch (_) {
        return _thumbFallback();
      }
    }
    return Image.network(src, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbFallback());
  }

  Widget _thumbFallback() => Container(
    color: const Color(0xFFF0F4FF),
    child: const Icon(Icons.broken_image_outlined, color: AppTheme.textHint),
  );

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Formulaire de création / édition ─────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════
class _AdFormSheet extends StatefulWidget {
  final AdModel? ad;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const _AdFormSheet({this.ad, required this.onSave});

  @override
  State<_AdFormSheet> createState() => _AdFormSheetState();
}

class _AdFormSheetState extends State<_AdFormSheet> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _linkValueCtrl;
  late final TextEditingController _ctaCtrl;

  // Image locale — null = aucune sélection, sinon base64
  String _imageBase64 = '';
  // Aperçu en mémoire pour affichage
  XFile? _pickedImage;
  final _imagePicker = ImagePicker();

  late String _linkType;
  late String _category;
  late bool _isActive;
  late DateTime _startDate;
  late DateTime _endDate;
  late int _position;

  @override
  void initState() {
    super.initState();
    final a = widget.ad;
    _titleCtrl    = TextEditingController(text: a?.title ?? '');
    _subtitleCtrl = TextEditingController(text: a?.subtitle ?? '');
    _linkValueCtrl = TextEditingController(text: a?.linkValue ?? '');
    _ctaCtrl      = TextEditingController(text: a?.ctaLabel ?? 'En savoir plus');
    _linkType  = a?.linkType ?? 'url';
    _category  = a?.category ?? AdModel.categories.first;
    _isActive  = a?.isActive ?? false;
    _startDate = a?.startDate ?? DateTime.now();
    _endDate   = a?.endDate ?? DateTime.now().add(const Duration(days: 30));
    _position  = a?.position ?? 5;
    // Récupérer image existante (base64) si édition
    _imageBase64 = a?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _subtitleCtrl.dispose();
    _linkValueCtrl.dispose(); _ctaCtrl.dispose();
    super.dispose();
  }

  /// Ouvre la galerie et convertit l'image sélectionnée en base64
  Future<void> _pickImageFromGallery() async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 600,
        imageQuality: 75,
      );
      if (xfile == null || !mounted) return;
      final bytes = await xfile.readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      setState(() {
        _pickedImage = xfile;
        _imageBase64 = b64;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur lors du chargement de l\'image : $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    }
  }

  void _removeImage() => setState(() {
    _pickedImage = null;
    _imageBase64 = '';
  });

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startDate = picked;
        else _endDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave({
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        'imageUrl': _imageBase64,
        'linkType': _linkType,
        // Nettoyer tous les espaces invisibles avant sauvegarde
        'linkValue': _linkValueCtrl.text.replaceAll(RegExp(r'[\s\u00A0\u200B\uFEFF]'), ''),
        'ctaLabel': _ctaCtrl.text.trim().isEmpty ? 'En savoir plus' : _ctaCtrl.text.trim(),
        'category': _category,
        'isActive': _isActive,
        'startDate': _startDate,
        'endDate': _endDate,
        'position': _position,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.ad != null;
    final mq = MediaQuery.of(context);
    // SafeArea bottom = hauteur du clavier + inset système (home indicator, etc.)
    final bottomPadding = mq.viewInsets.bottom + mq.padding.bottom + 16;
    return SafeArea(
      top: false, // Le haut est géré par le borderRadius
      child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Poignée + titre ──────────────────────────────────────────
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(isEdit ? 'Modifier la publicité' : 'Nouvelle publicité',
                style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 17,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 20),

            // ── Titre ────────────────────────────────────────────────────
            _label('Titre *'),
            _textField(_titleCtrl, 'Ex : Banque XYZ — Financement immobilier',
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null),
            const SizedBox(height: 14),

            // ── Sous-titre ───────────────────────────────────────────────
            _label('Sous-titre / accroche'),
            _textField(_subtitleCtrl, 'Ex : Taux préférentiel pour l\'achat immobilier'),
            const SizedBox(height: 14),

            // ── Catégorie ────────────────────────────────────────────────
            _label('Catégorie'),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: _inputDeco(hint: ''),
              isExpanded: true,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: AppTheme.textPrimary),
              items: AdModel.categories.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              )).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 14),

            // ── Image locale ──────────────────────────────────────────────
            _label('Image (optionnel)'),
            _buildImagePicker(),
            const SizedBox(height: 14),

            // ── Lien / Action ────────────────────────────────────────────
            _label('Type de lien *'),
            Row(children: [
              _linkTypeBtn('url',       Icons.link_rounded,      'URL web'),
              const SizedBox(width: 8),
              _linkTypeBtn('whatsapp',  Icons.chat_rounded,      'WhatsApp'),
              const SizedBox(width: 8),
              _linkTypeBtn('phone',     Icons.phone_rounded,     'Téléphone'),
            ]),
            const SizedBox(height: 10),
            _label(_linkType == 'url'
                ? 'URL (ex: https://monsite.com) *'
                : _linkType == 'whatsapp'
                    ? 'Numéro WhatsApp (ex: +243812345678) *'
                    : 'Numéro de téléphone *'),
            _textField(_linkValueCtrl,
                _linkType == 'url' ? 'https://' : '+243...',
                keyboardType: _linkType == 'url'
                    ? TextInputType.url
                    : TextInputType.phone,
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null),
            const SizedBox(height: 14),

            // ── Label bouton CTA ─────────────────────────────────────────
            _label('Texte du bouton'),
            _textField(_ctaCtrl, 'En savoir plus'),
            const SizedBox(height: 14),

            // ── Position (toutes les N annonces) ─────────────────────────
            _label('Afficher toutes les $_position annonces'),
            Slider(
              value: _position.toDouble(),
              min: 3, max: 15, divisions: 12,
              activeColor: const Color(0xFFE65100),
              label: '$_position annonces',
              onChanged: (v) => setState(() => _position = v.round()),
            ),
            const SizedBox(height: 14),

            // ── Dates ────────────────────────────────────────────────────
            _label('Période de diffusion'),
            Row(children: [
              Expanded(child: _dateTile('Début', _startDate,
                  () => _pickDate(true))),
              const SizedBox(width: 10),
              Expanded(child: _dateTile('Fin', _endDate,
                  () => _pickDate(false))),
            ]),
            const SizedBox(height: 14),

            // ── Activer immédiatement ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E8F0)),
              ),
              child: Row(children: [
                const Icon(Icons.toggle_on_rounded, color: Color(0xFF2E7D32), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Activer immédiatement',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                ),
                Switch(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  activeColor: const Color(0xFF2E7D32),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Bouton sauvegarder ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: Colors.white))
                    : Icon(isEdit ? Icons.save_rounded : Icons.add_rounded,
                        size: 18),
                label: Text(isEdit ? 'Enregistrer les modifications' : 'Créer la publicité',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ),
    ), // Container
    ); // SafeArea
  }

  /// Widget sélecteur d'image depuis la galerie
  Widget _buildImagePicker() {
    final hasImage = _imageBase64.isNotEmpty;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: hasImage ? null : _pickImageFromGallery,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasImage
                ? AppTheme.accentColor.withValues(alpha: 0.5)
                : const Color(0xFFE4E8F0),
            width: hasImage ? 1.5 : 1,
          ),
        ),
        child: hasImage
            ? Stack(children: [
                // Aperçu de l'image
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: _buildPreviewImage(),
                ),
                // Bouton supprimer (coin haut-droit)
                Positioned(
                  top: 6, right: 6,
                  child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                    onTap: _removeImage,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: Colors.white),
                    ),
                  )),
                ),
                // Bouton changer (coin bas-gauche)
                Positioned(
                  bottom: 6, left: 6,
                  child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
                    onTap: _pickImageFromGallery,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.photo_library_rounded,
                            size: 12, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Changer',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ]),
                    ),
                  )),
                ),
              ])
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Icon(Icons.add_photo_alternate_rounded,
                      size: 36,
                      color: AppTheme.accentColor.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  const Text('Appuyer pour choisir une image',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  const Text('Depuis la galerie (optionnel)',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: AppTheme.)textHint)),
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  /// Affiche l'aperçu de l'image sélectionnée (base64 ou fichier local)
  Widget _buildPreviewImage() {
    // Sur web on ne peut pas utiliser File — on lit depuis le base64
    if (_imageBase64.isNotEmpty) {
      try {
        final b64 = _imageBase64.contains(',')
            ? _imageBase64.split(',').last
            : _imageBase64;
        return Image.memory(
          base64Decode(b64),
          width: double.infinity,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _previewFallback(),
        );
      } catch (_) {
        return _previewFallback();
      }
    }
    // Fallback : afficher depuis le fichier natif (Android/iOS)
    if (_pickedImage != null && !kIsWeb) {
      return Image.file(
        File(_pickedImage!.path),
        width: double.infinity,
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _previewFallback(),
      );
    }
    return _previewFallback();
  }

  Widget _previewFallback() => Container(
    height: 160,
    color: const Color(0xFFF0F4FF),
    child: const Center(
      child: Icon(Icons.broken_image_outlined,
          size: 40, color: AppTheme.textHint),
    ),
  );

  Widget _linkTypeBtn(String type, IconData icon, String label) {
    final selected = _linkType == type;
    return Expanded(
      child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
        onTap: () => setState(() => _linkType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE65100) : const Color(0xFFF8F9FC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFFE65100) : const Color(0xFFE4E8F0),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18,
                color: selected ? Colors.white : AppTheme.textSecondary),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.textSecondary)),
          ]),
        ),
      )),
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E8F0)),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 14,
              color: AppTheme.accentColor),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    color: AppTheme.textHint)),
            Text(
              '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
          ]),
        ]),
      ),
    ));
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
  );

  Widget _textField(TextEditingController ctrl, String hint,
      {TextInputType? keyboardType,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: _inputDeco(hint: hint),
    );
  }

  InputDecoration _inputDeco({required String hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
        color: AppTheme.textHint),
    filled: true,
    fillColor: const Color(0xFFF8F9FC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE4E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE4E8F0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.accentColor, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.errorColor)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.5)),
  );
}
