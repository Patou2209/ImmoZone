import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Onglet Email ──────────────────────────────────────────────────────────
  final _emailFormKey = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool  _obscure      = true;

  // ── Onglet Téléphone ──────────────────────────────────────────────────────
  String _phoneCountryCode = '+243';
  final _phoneNumberCtrl   = TextEditingController();
  final _otpCtrl           = TextEditingController();

  String get _fullPhone => '$_phoneCountryCode${_phoneNumberCtrl.text.trim()}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── Connexion email/mot de passe ─────────────────────────────────────────
  Future<void> _loginEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success =
        await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
    if (!mounted) return;
    if (success) {
      _navigateAfterLogin(auth);
    } else {
      _showError(auth.error ?? 'Identifiants incorrects');
    }
  }

  // ── Connexion téléphone — envoi OTP ──────────────────────────────────────
  Future<void> _sendOtp() async {
    final number = _phoneNumberCtrl.text.trim();
    if (number.isEmpty) {
      _showError('Veuillez saisir votre numéro de téléphone');
      return;
    }
    final auth = context.read<AuthProvider>();
    await auth.sendPhoneOtp(_fullPhone);
    if (!mounted) return;
    if (auth.error != null) _showError(auth.error!);
  }

  // ── Connexion téléphone — vérification OTP ───────────────────────────────
  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.length < 4) {
      _showError('Veuillez saisir le code SMS reçu');
      return;
    }
    final auth = context.read<AuthProvider>();
    final success = await auth.verifyPhoneOtp(code);
    if (!mounted) return;
    if (success) {
      _navigateAfterLogin(auth);
    } else {
      _showError(auth.error ?? 'Code SMS incorrect');
    }
  }

  void _navigateAfterLogin(AuthProvider auth) {
    if (auth.isAdmin) {
      Navigator.of(context).pushReplacementNamed('/admin');
    } else {
      Navigator.of(context).pushReplacementNamed('/public');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Mot de passe oublié ───────────────────────────────────────────────────
  Future<void> _showForgotPassword() async {
    final emailCtrl =
        TextEditingController(text: _emailCtrl.text.trim());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mot de passe oublié',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saisissez votre adresse e-mail pour recevoir un lien de réinitialisation.',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.email_outlined,
                    color: AppTheme.accentColor),
                hintText: 'votre@email.com',
              ),
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
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await fb_auth.FirebaseAuth.instance
                    .sendPasswordResetEmail(email: email);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'E-mail de réinitialisation envoyé à $email',
                      style: const TextStyle(fontFamily: 'Poppins')),
                  backgroundColor: AppTheme.successColor,
                ));
              } on fb_auth.FirebaseAuthException catch (e) {
                if (!mounted) return;
                final msg = e.code == 'user-not-found'
                    ? 'Aucun compte trouvé avec cet e-mail.'
                    : 'Erreur : ${e.message}';
                _showError(msg);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Envoyer',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    emailCtrl.dispose();
  }

  // ── Sélecteur indicatif pays ─────────────────────────────────────────────
  void _showCountryPicker() {
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
                          setState(() =>
                              _phoneCountryCode = c['code']!);
                          Navigator.pop(ctx);
                        },
                        leading: Text(c['flag'] ?? '',
                            style: const TextStyle(fontSize: 24)),
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

  void _fillDemo(String role) {
    if (role == 'admin') {
      _emailCtrl.text = 'admin@immozone.cd';
      _passwordCtrl.text = 'admin1234';
    } else if (role == 'annonceur') {
      _emailCtrl.text = 'jp.mukeba@gmail.com';
      _passwordCtrl.text = 'pass1234';
    } else {
      _emailCtrl.text = 'p.mwamba@hotmail.com';
      _passwordCtrl.text = 'pass1234';
    }
    setState(() {});
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            const SizedBox(height: 28),

            // ── Logo ─────────────────────────────────────────────────────
            Image.asset(
              'assets/images/immozone_logo.png',
              width: 200,
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
                        style:
                            TextStyle(color: AppTheme.primaryColor)),
                    TextSpan(
                        text: 'Zone',
                        style:
                            TextStyle(color: AppTheme.accentColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Carte formulaire ─────────────────────────────────────────
            Container(
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
              child: Column(children: [
                // Titre
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Connexion',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              fontFamily: 'Poppins')),
                      SizedBox(height: 4),
                      Text('Connectez-vous à votre compte',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              fontFamily: 'Poppins')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Tabs Email / Téléphone ──────────────────────────────
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                    unselectedLabelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: 13),
                    labelColor: Colors.white,
                    unselectedLabelColor: AppTheme.textSecondary,
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.email_outlined, size: 15),
                            SizedBox(width: 6),
                            Text('E-mail'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_outlined, size: 15),
                            SizedBox(width: 6),
                            Text('Téléphone'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // ── Contenu des onglets ─────────────────────────────────
                SizedBox(
                  height: 260,
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildEmailTab(auth),
                      _buildPhoneTab(auth),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 18),

            // ── Comptes démo ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color:
                        AppTheme.accentColor.withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                const Row(children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.accentColor, size: 16),
                  SizedBox(width: 8),
                  Text('Comptes de démonstration',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.accentColor,
                          fontFamily: 'Poppins')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _demoBtn('Admin',
                          Icons.admin_panel_settings,
                          () => _fillDemo('admin'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _demoBtn('Annonceur',
                          Icons.home_outlined,
                          () => _fillDemo('annonceur'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _demoBtn('Demandeur', Icons.search,
                          () => _fillDemo('demandeur'))),
                ]),
              ]),
            ),
            const SizedBox(height: 18),

            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Pas encore de compte ? ',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Poppins')),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterScreen())),
                child: const Text('S\'inscrire',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Onglet 1 : Email + Mot de passe ──────────────────────────────────────
  Widget _buildEmailTab(AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Form(
        key: _emailFormKey,
        child: Column(children: [
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.email_outlined,
                  color: AppTheme.accentColor),
              hintText: 'votre@email.com',
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'E-mail requis' : null,
          ),
          const SizedBox(height: 12),
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
                    color: AppTheme.textSecondary,
                    size: 20),
                onPressed: () =>
                    setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => v == null || v.length < 4
                ? 'Mot de passe trop court'
                : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Mot de passe oublié ?',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentColor)),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  auth.isLoading ? null : _loginEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                      color: AppTheme.accentColor, width: 1.5),
                ),
              ),
              child: auth.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: AppTheme.accentColor,
                          strokeWidth: 2))
                  : const Text('Se connecter',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Onglet 2 : Téléphone + OTP ───────────────────────────────────────────
  Widget _buildPhoneTab(AuthProvider auth) {
    final codeSent = auth.codeSent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(children: [
        if (!codeSent) ...[
          // Sélecteur pays + numéro
          _phoneInputRow(),
          const SizedBox(height: 12),
          const Text(
            'Un code SMS vous sera envoyé sur ce numéro.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  auth.isLoading ? null : _sendOtp,
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sms_outlined,
                      size: 18, color: Colors.white),
              label: const Text('Recevoir le code SMS',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                      color: AppTheme.accentColor, width: 1.5),
                ),
              ),
            ),
          ),
        ] else ...[
          // Saisie du code OTP
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.successColor
                      .withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline,
                  color: AppTheme.successColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Code envoyé sur $_fullPhone',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppTheme.successColor),
                ),
              ),
              GestureDetector(
                onTap: () {
                  context.read<AuthProvider>().resetPhoneAuth();
                  _otpCtrl.clear();
                },
                child: const Text('Modifier',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentColor)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly
            ],
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '——————',
              hintStyle: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 22,
                  letterSpacing: 8),
              counterText: '',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppTheme.accentColor, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: auth.otpVerifying ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                      color: AppTheme.accentColor, width: 1.5),
                ),
              ),
              child: auth.otpVerifying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: AppTheme.accentColor,
                          strokeWidth: 2))
                  : const Text('Vérifier et se connecter',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Ligne saisie téléphone (indicatif + numéro) ───────────────────────────
  Widget _phoneInputRow() {
    final selected = AppConstants.countryCodes.firstWhere(
      (c) => c['code'] == _phoneCountryCode,
      orElse: () => AppConstants.countryCodes.first,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(children: [
        // Bouton indicatif
        GestureDetector(
          onTap: _showCountryPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                  right: BorderSide(color: AppTheme.dividerColor)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(selected['flag'] ?? '',
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 4),
              Text(_phoneCountryCode,
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
                  horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _demoBtn(
      String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppTheme.accentColor.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Icon(icon, color: AppTheme.accentColor, size: 20),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentColor,
                  fontFamily: 'Poppins')),
        ]),
      ),
    );
  }
}
