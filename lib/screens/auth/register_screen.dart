import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController(); // e-mail de récupération
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();

  String _phoneCountryCode = '+243';
  bool   _obscure          = true;
  bool   _obscureConfirm   = true;
  bool   _phoneWarningRead = false; // l'utilisateur a lu l'avertissement

  String? _selectedCategory;

  String get _fullPhone =>
      '$_phoneCountryCode${_phoneNumberCtrl.text.trim()}';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Inscription ───────────────────────────────────────────────────────────
  Future<void> _register() async {
    // 1. Catégorie obligatoire
    if (_selectedCategory == null) {
      _showError('Veuillez sélectionner votre catégorie.');
      return;
    }
    // 2. Validation du formulaire
    if (!_formKey.currentState!.validate()) return;
    // 3. Numéro de téléphone
    if (_phoneNumberCtrl.text.trim().isEmpty) {
      _showError('Veuillez saisir votre numéro de téléphone.');
      return;
    }
    // 4. L'utilisateur doit avoir lu l'avertissement téléphone
    if (!_phoneWarningRead) {
      // Montrer l'alerte et attendre confirmation
      final confirmed = await _showPhoneWarningDialog();
      if (!confirmed) return;
      setState(() => _phoneWarningRead = true);
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.register(
      name:          _nameCtrl.text.trim(),
      phone:         _fullPhone,
      password:      _passwordCtrl.text.trim(),
      recoveryEmail: _emailCtrl.text.trim(),
      role:          AppConstants.roleAnnonceur,
      category:      _selectedCategory,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacementNamed('/public');
    } else {
      _showError(auth.error ?? 'Erreur lors de l\'inscription.');
    }
  }

  // ── Dialogue d'avertissement téléphone ────────────────────────────────────
  Future<bool> _showPhoneWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF57C00)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_in_talk_rounded,
                    color: Color(0xFFF57C00), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Important — Numéro public',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF57C00)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF57C00)
                            .withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Le numéro de téléphone que vous utilisez pour créer votre compte sera affiché publiquement sur toutes vos annonces.\n\n'
                    'Les chercheurs de biens pourront vous contacter directement via ce numéro (appel ou WhatsApp).\n\n'
                    'Assurez-vous d\'utiliser un numéro actif et accessible.',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF7B4A00),
                        height: 1.6),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(false),
                child: const Text('Modifier le numéro',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFF57C00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(10)),
                ),
                child: const Text('J\'ai compris, continuer',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Créer un compte',
            style: TextStyle(fontFamily: 'Poppins')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rejoignez ImmoZone',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 4),
                const Text(
                    'Créez votre compte gratuitement • 3 annonces offertes',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 22),

                // ── Sélection catégorie ─────────────────────────────────
                Row(children: [
                  const Text('Je suis :',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          fontFamily: 'Poppins')),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppTheme.errorColor
                              .withValues(alpha: 0.4)),
                    ),
                    child: const Text('obligatoire',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.errorColor)),
                  ),
                ]),
                const SizedBox(height: 12),
                Column(
                    children: AppConstants.annonceurCategories
                        .map((cat) => Padding(
                              padding: const EdgeInsets.only(
                                  bottom: 10),
                              child: _categoryCard(cat),
                            ))
                        .toList()),
                if (_selectedCategory == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          size: 13,
                          color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                          'Sélectionnez votre catégorie ci-dessus',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.8))),
                    ]),
                  ),
                const SizedBox(height: 8),

                // ── Nom complet ─────────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(Icons.person_outline,
                        color: AppTheme.accentColor),
                    hintText: 'Votre nom et prénom',
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Nom requis'
                      : null,
                ),
                const SizedBox(height: 14),

                // ── Téléphone (= identifiant de connexion) ──────────────
                _phoneField(),
                const SizedBox(height: 6),

                // ⚠️ Bannière d'avertissement numéro public ─────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF57C00)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFF57C00)
                            .withValues(alpha: 0.4)),
                  ),
                  child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    const Icon(Icons.campaign_rounded,
                        color: Color(0xFFF57C00), size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Ce numéro sera votre identifiant de connexion ET sera affiché publiquement sur vos annonces pour que les chercheurs puissent vous contacter.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Color(0xFF7B4A00),
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── E-mail de récupération ──────────────────────────────
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail de récupération',
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppTheme.accentColor),
                    hintText: 'votre@email.com',
                    helperText:
                        'Utilisé uniquement pour récupérer votre mot de passe.',
                    helperStyle: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'E-mail de récupération requis';
                    }
                    if (!v.contains('@') ||
                        !v.contains('.')) {
                      return 'E-mail invalide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ────────────────────────────────────────
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppTheme.accentColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () => setState(
                          () => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Mot de passe requis';
                    }
                    if (v.length < 6) {
                      return 'Minimum 6 caractères';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Confirmation mot de passe ───────────────────────────
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppTheme.accentColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () => setState(
                          () => _obscureConfirm =
                              !_obscureConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != _passwordCtrl.text
                          ? 'Les mots de passe ne correspondent pas'
                          : null,
                ),
                const SizedBox(height: 24),

                // ── Bannière 3 annonces gratuites ───────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.successColor
                            .withValues(alpha: 0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.card_giftcard,
                        color: AppTheme.successColor,
                        size: 20),
                    SizedBox(width: 10),
                    Expanded(
                        child: Text(
                      '3 annonces gratuites offertes à l\'inscription !',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.successColor),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Bouton Créer mon compte ─────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        auth.isLoading ? null : _register,
                    child: auth.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2))
                        : const Text('Créer mon compte',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                  const Text('Déjà un compte ? ',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontFamily: 'Poppins')),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context),
                    child: const Text('Se connecter',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Champ téléphone avec sélecteur pays ───────────────────────────────────
  Widget _phoneField() {
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _phoneCountryCode,
      orElse: () => AppConstants.countryCodes.first,
    );
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(children: [
        const Text('Numéro de téléphone *',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: AppTheme.primaryColor
                    .withValues(alpha: 0.3)),
          ),
          child: const Text('identifiant de connexion',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor)),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(children: [
          // Sélecteur indicatif
          GestureDetector(
            onTap: _showPhoneCountryPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 15),
              decoration: BoxDecoration(
                border: Border(
                    right: BorderSide(
                        color: AppTheme.dividerColor)),
              ),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(selected['flag'] ?? '',
                    style:
                        const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(_phoneCountryCode,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.accentColor)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down,
                    color: AppTheme.accentColor,
                    size: 18),
              ]),
            ),
          ),
          // Numéro sans indicatif
          Expanded(
            child: TextField(
              controller: _phoneNumberCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Numéro (ex : 812345678)',
                hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppTheme.textHint,
                    fontSize: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 12, vertical: 15),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Sélecteur pays avec recherche ─────────────────────────────────────────
  void _showPhoneCountryPicker() {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered =
        List.from(AppConstants.countryCodes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          void onSearch(String q) {
            setModal(() {
              filtered = AppConstants.countryCodes
                  .where((c) =>
                      (c['country'] ?? '')
                          .toLowerCase()
                          .contains(q.toLowerCase()) ||
                      (c['code'] ?? '').contains(q))
                  .toList();
            });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.70,
            maxChildSize: 0.92,
            minChildSize: 0.40,
            builder: (_, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20)),
              ),
              child: Column(children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius:
                        BorderRadius.circular(2),
                  ),
                ),
                const Text('Indicatif pays',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un pays…',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13),
                      prefixIcon: const Icon(
                          Icons.search,
                          color: AppTheme.accentColor),
                      suffixIcon:
                          searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: AppTheme
                                          .textSecondary),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    onSearch('');
                                  },
                                )
                              : null,
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final isSel = c['code'] ==
                          _phoneCountryCode;
                      return ListTile(
                        onTap: () {
                          setState(() =>
                              _phoneCountryCode =
                                  c['code']!);
                          Navigator.pop(ctx);
                        },
                        leading: Text(c['flag'] ?? '',
                            style: const TextStyle(
                                fontSize: 24)),
                        title: Text(c['country'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 14,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme
                                        .textPrimary)),
                        trailing: Text(c['code'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight:
                                    FontWeight.w700,
                                fontSize: 13,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme
                                        .textSecondary)),
                        tileColor: isSel
                            ? AppTheme.accentColor
                                .withValues(alpha: 0.06)
                            : null,
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Carte de catégorie ────────────────────────────────────────────────────
  Widget _categoryCard(String category) {
    final isSelected = _selectedCategory == category;
    IconData icon;
    Color color;
    String subtitle;

    switch (category) {
      case AppConstants.categoryAgence:
        icon = Icons.business_rounded;
        color = const Color(0xFF1565C0);
        subtitle = 'Je gère plusieurs biens pour des clients';
        break;
      case AppConstants.categoryCommissionnaire:
        icon = Icons.handshake_rounded;
        color = const Color(0xFF6A1B9A);
        subtitle = 'Je mets en relation acheteurs et vendeurs';
        break;
      case AppConstants.categoryProprietaire:
      default:
        icon = Icons.home_rounded;
        color = const Color(0xFF2E7D32);
        subtitle = 'Je publie mon propre bien';
        break;
    }

    return GestureDetector(
      onTap: () =>
          setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? color
                : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color:
                          color.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : [
                  BoxShadow(
                      color: Colors.black
                          .withValues(alpha: 0.04),
                      blurRadius: 4)
                ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.2)
                  : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: isSelected
                    ? Colors.white
                    : color,
                size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
            Text(category,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    color: isSelected
                        ? Colors.white
                        : AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Poppins',
                    color: isSelected
                        ? Colors.white
                            .withValues(alpha: 0.85)
                        : AppTheme.textSecondary)),
          ])),
          if (isSelected)
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 22),
        ]),
      ),
    );
  }
}
