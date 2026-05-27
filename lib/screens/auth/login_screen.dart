import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import 'register_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _phoneCtrl   = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool  _obscure     = true;

  // Indicatif pays sélectionné
  String _countryCode = '+243';

  String get _fullPhone =>
      '$_countryCode${_phoneCtrl.text.trim()}';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Connexion ─────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithPhone(
        _fullPhone, _passwordCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      if (auth.isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else {
        Navigator.of(context).pushReplacementNamed('/public');
      }
    } else {
      _showError(auth.error ?? 'Numéro ou mot de passe incorrect.');
    }
  }

  // ── Mot de passe oublié ───────────────────────────────────────────────────
  Future<void> _forgotPassword() async {
    // Pré-remplir avec le numéro déjà saisi
    final phoneCtrl =
        TextEditingController(text: _phoneCtrl.text.trim());
    String selectedCode = _countryCode;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Mot de passe oublié',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saisissez votre numéro de téléphone. Un lien de réinitialisation sera envoyé à l\'adresse e-mail de récupération associée à ce compte.',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: 14),
              // Sélecteur + champ numéro
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(children: [
                  _codeButton(selectedCode, () async {
                    final picked =
                        await _pickCountryCode(ctx2);
                    if (picked != null) {
                      setS(() => selectedCode = picked);
                    }
                  }),
                  Expanded(
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Numéro (ex : 812345678)',
                        hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppTheme.textHint),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final number = phoneCtrl.text.trim();
                if (number.isEmpty) {
                  // Afficher une erreur visible dans le dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Veuillez saisir votre numéro de téléphone.',
                          style: TextStyle(fontFamily: 'Poppins')),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                // Normalisation : si l'utilisateur a tapé le numéro complet
                // avec indicatif (ex: +243823854273), on évite la duplication
                final String full;
                if (number.startsWith('+') || number.startsWith('00')) {
                  // Numéro complet saisi directement → on l'utilise tel quel
                  full = number.replaceAll(RegExp(r'^00'), '+');
                } else {
                  full = '$selectedCode$number';
                }
                Navigator.of(ctx).pop();
                final auth =
                    context.read<AuthProvider>();
                final ok = await auth
                    .sendPasswordResetByPhone(full);
                if (!mounted) return;
                if (ok) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(
                    content: Text(
                      'Lien de réinitialisation envoyé à votre adresse e-mail de récupération.',
                      style: TextStyle(
                          fontFamily: 'Poppins'),
                    ),
                    backgroundColor:
                        AppTheme.successColor,
                    behavior:
                        SnackBarBehavior.floating,
                  ));
                } else {
                  _showError(auth.error ??
                      'Numéro introuvable.');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(10)),
              ),
              child: const Text('Envoyer',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    phoneCtrl.dispose();
  }

  // ── Sélecteur d'indicatif pays ────────────────────────────────────────────
  Future<String?> _pickCountryCode(
      BuildContext parentCtx) async {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered =
        List.from(AppConstants.countryCodes);
    String? picked;

    await showModalBottomSheet(
      context: parentCtx,
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
                          BorderRadius.circular(2)),
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
                      final isSel =
                          c['code'] == _countryCode;
                      return ListTile(
                        onTap: () {
                          picked = c['code'];
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
                                .withValues(alpha: 0.07)
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
    return picked;
  }

  void _showCountryPicker() async {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered =
        List.from(AppConstants.countryCodes);

    await showModalBottomSheet(
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
                          BorderRadius.circular(2)),
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
                      final isSel =
                          c['code'] == _countryCode;
                      return ListTile(
                        onTap: () {
                          setState(() =>
                              _countryCode = c['code']!);
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
                                .withValues(alpha: 0.07)
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
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _countryCode,
      orElse: () => AppConstants.countryCodes.first,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 16),
          child: Column(children: [
            const SizedBox(height: 32),

            // ── Logo ───────────────────────────────────────────────────
            Image.asset(
              'assets/images/immozone_logo.png',
              width: 210,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => RichText(
                text: const TextSpan(
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 30,
                      fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(
                        text: 'Immo',
                        style: TextStyle(
                            color: AppTheme.primaryColor)),
                    TextSpan(
                        text: 'Zone',
                        style: TextStyle(
                            color: AppTheme.accentColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Carte formulaire ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.accentColor
                        .withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                  const Text('Connexion',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 4),
                  const Text(
                      'Connectez-vous avec votre numéro de téléphone',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 22),

                  // ── Champ Téléphone ─────────────────────────────────
                  const Text('Numéro de téléphone',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.dividerColor),
                    ),
                    child: Row(children: [
                      // Bouton indicatif
                      GestureDetector(
                        onTap: _showCountryPicker,
                        child: _codeButton(
                            _countryCode, null,
                            flag: selected['flag']),
                      ),
                      // Numéro sans indicatif
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType:
                              TextInputType.phone,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13),
                          decoration: const InputDecoration(
                            hintText:
                                'Numéro (ex : 812345678)',
                            hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                color: AppTheme.textHint,
                                fontSize: 12),
                            border: InputBorder.none,
                            enabledBorder:
                                InputBorder.none,
                            focusedBorder:
                                InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty
                                  ? 'Numéro requis'
                                  : null,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),

                  // ── Champ Mot de passe ──────────────────────────────
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: AppTheme.accentColor),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.textSecondary,
                            size: 20),
                        onPressed: () => setState(
                            () => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.length < 4
                            ? 'Mot de passe trop court'
                            : null,
                  ),

                  // ── Mot de passe oublié ─────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize:
                            MaterialTapTargetSize
                                .shrinkWrap,
                      ),
                      child: const Text(
                          'Mot de passe oublié ?',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Bouton Se connecter ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          auth.isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          side: const BorderSide(
                              color: AppTheme.accentColor,
                              width: 1.5),
                        ),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(
                                      color: AppTheme
                                          .accentColor,
                                      strokeWidth: 2))
                          : const Text('Se connecter',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight:
                                      FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),

            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              const Text('Pas encore de compte ? ',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Poppins')),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const RegisterScreen())),
                child: const Text('S\'inscrire',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  // ── Bouton indicatif pays ─────────────────────────────────────────────────
  Widget _codeButton(String code, VoidCallback? onTap,
      {String? flag}) {
    final entry = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == code,
      orElse: () => AppConstants.countryCodes.first,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
              right:
                  BorderSide(color: AppTheme.dividerColor)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(flag ?? entry['flag'] ?? '',
              style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 4),
          Text(code,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.accentColor)),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down,
              color: AppTheme.accentColor, size: 18),
        ]),
      ),
    );
  }


}
