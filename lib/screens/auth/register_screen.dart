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
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  // Téléphone : indicatif pays + numéro
  String _phoneCountryCode = '+243';
  final _phoneNumberCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;

  // Catégorie obligatoire — pas de valeur par défaut
  String? _selectedCategory;

  /// Numéro complet = indicatif + chiffres
  String get _fullPhone => '$_phoneCountryCode${_phoneNumberCtrl.text.trim()}';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // Valider la catégorie en premier
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner votre catégorie',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    if (_phoneNumberCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez saisir votre numéro de téléphone',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _fullPhone,
      password: _passwordCtrl.text.trim(),
      role: AppConstants.roleAnnonceur,
      category: _selectedCategory,
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacementNamed('/public');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Erreur lors de l\'inscription',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Créer un compte'),
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
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary, fontFamily: 'Poppins')),
                const SizedBox(height: 4),
                const Text('Créez votre compte gratuitement • 3 annonces offertes',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 24),

                // ── Sélection de catégorie (OBLIGATOIRE) ────────────────────
                Row(children: [
                  const Text('Je suis :',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary, fontFamily: 'Poppins')),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.4)),
                    ),
                    child: const Text('obligatoire',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
                  ),
                ]),
                const SizedBox(height: 12),

                // 3 cartes de catégorie
                Column(children: AppConstants.annonceurCategories.map((cat) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _categoryCard(cat),
                  ),
                ).toList()),

                // Message si aucune catégorie sélectionnée
                if (_selectedCategory == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 13, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text('Sélectionnez votre catégorie ci-dessus',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              color: AppTheme.textSecondary.withValues(alpha: 0.8))),
                    ]),
                  ),

                const SizedBox(height: 8),

                // ── Champs du formulaire ─────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(Icons.person_outline, color: AppTheme.accentColor),
                    hintText: 'Votre nom et prénom',
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Nom requis' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined, color: AppTheme.accentColor),
                    hintText: 'votre@email.com',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email requis';
                    if (!v.contains('@')) return 'Email invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _phoneField(),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.accentColor),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Mot de passe requis';
                    if (v.length < 6) return 'Minimum 6 caractères';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.accentColor),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondary),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != _passwordCtrl.text ? 'Les mots de passe ne correspondent pas' : null,
                ),
                const SizedBox(height: 28),

                // ── Banner 3 annonces gratuites ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.card_giftcard, color: AppTheme.successColor, size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      '3 annonces gratuites offertes à l\'inscription !',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w600, color: AppTheme.successColor),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _register,
                    child: auth.isLoading
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Créer mon compte'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Déjà un compte ? ',
                        style: TextStyle(color: AppTheme.textSecondary,
                            fontSize: 13, fontFamily: 'Poppins')),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Se connecter'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Champ téléphone avec indicatif pays ──────────────────────────────────
  Widget _phoneField() {
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _phoneCountryCode,
      orElse: () => AppConstants.countryCodes.first,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Téléphone / WhatsApp *',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
              fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: AppTheme.dividerColor)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(selected['flag'] ?? '', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(_phoneCountryCode,
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700, fontSize: 13,
                        color: AppTheme.accentColor)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: AppTheme.accentColor, size: 18),
              ]),
            ),
          ),
          // Numéro (sans l'indicatif)
          Expanded(
            child: TextField(
              controller: _phoneNumberCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Numéro (ex: 812345678)',
                hintStyle: TextStyle(fontFamily: 'Poppins',
                    color: AppTheme.textHint, fontSize: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  void _showPhoneCountryPicker() {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered =
        List.from(AppConstants.countryCodes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void onSearch(String q) {
            setModalState(() {
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
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(children: [
                // Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text('Indicatif pays',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                // Barre de recherche
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un pays…',
                      hintStyle: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13),
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.accentColor),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  size: 18,
                                  color: AppTheme.textSecondary),
                              onPressed: () {
                                searchCtrl.clear();
                                onSearch('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
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
                      final isSel = c['code'] == _phoneCountryCode;
                      return ListTile(
                        onTap: () {
                          setState(
                              () => _phoneCountryCode = c['code']!);
                          Navigator.pop(ctx);
                        },
                        leading: Text(c['flag'] ?? '',
                            style:
                                const TextStyle(fontSize: 24)),
                        title: Text(c['country'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 14,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme.textPrimary)),
                        trailing: Text(c['code'] ?? '',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isSel
                                    ? AppTheme.accentColor
                                    : AppTheme.textSecondary)),
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

  Widget _categoryCard(String category) {
    final isSelected = _selectedCategory == category;

    // Icône et couleur selon la catégorie
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
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.25),
                  blurRadius: 10, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4)],
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
                color: isSelected ? Colors.white : color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 11, fontFamily: 'Poppins',
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppTheme.textSecondary,
                  )),
            ],
          )),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
        ]),
      ),
    );
  }
}
