import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
        _emailCtrl.text.trim(), _passwordCtrl.text.trim());
    if (!mounted) return;
    if (success) {
      if (auth.isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else {
        Navigator.of(context).pushReplacementNamed('/public');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Identifiants incorrects'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // ── Logo officiel ImmoZone ─────────────────────────────
              Image.asset(
                'assets/images/immozone_logo.png',
                width: 220,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => RichText(
                  text: const TextSpan(
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 30, fontWeight: FontWeight.w800),
                    children: [
                      TextSpan(text: 'Immo',
                          style: TextStyle(color: AppTheme.primaryColor)),
                      TextSpan(text: 'Zone',
                          style: TextStyle(color: AppTheme.accentColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Formulaire ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.accentColor.withValues(alpha: 0.15)),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connexion',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Connectez-vous à votre compte',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined,
                              color: AppTheme.accentColor),
                          hintText: 'votre@email.com',
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Email requis' : null,
                      ),
                      const SizedBox(height: 16),
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
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.length < 4
                            ? 'Mot de passe trop court'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: auth.isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
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
                                      strokeWidth: 2),
                                )
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Comptes démo ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.accentColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppTheme.accentColor, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Comptes de démonstration',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.accentColor,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _demoBtn('Admin',
                              Icons.admin_panel_settings,
                              () => _fillDemo('admin')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _demoBtn('Annonceur',
                              Icons.home_outlined,
                              () => _fillDemo('annonceur')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _demoBtn('Demandeur', Icons.search,
                              () => _fillDemo('demandeur')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Pas encore de compte ? ',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                    child: const Text('S\'inscrire'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _demoBtn(String label, IconData icon, VoidCallback onTap) {
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
        child: Column(
          children: [
            Icon(icon, color: AppTheme.accentColor, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.accentColor,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
