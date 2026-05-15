import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/property_provider.dart';
import 'providers/message_provider.dart';
import 'services/data_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/public/home/public_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await DataService().init();

  runApp(const ImmoZoneApp());
}

class ImmoZoneApp extends StatelessWidget {
  const ImmoZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PropertyProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
      ],
      child: MaterialApp(
        title: 'ImmoZone',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/admin': (context) => const AdminHomeScreen(),
          '/public': (context) => const PublicHomeScreen(),
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut),
    );
    _animCtrl.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    await auth.checkAuth();
    if (!mounted) return;
    if (auth.isLoggedIn) {
      if (auth.isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else {
        Navigator.of(context).pushReplacementNamed('/public');
      }
    } else {
      // Unauthenticated users go to the public home to browse freely
      Navigator.of(context).pushReplacementNamed('/public');
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: Stack(
        children: [
          // Fond dégradé bleu nuit
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryDark, AppTheme.primaryColor, AppTheme.primaryLight],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Bordure dorée subtile en haut
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(height: 3, color: AppTheme.accentColor),
          ),
          // Contenu centré
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo IZ (image réelle) ──────────────────────
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: AppTheme.accentColor,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentColor.withValues(alpha: 0.35),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.primaryColor,
                            child: const Icon(
                              Icons.home_work,
                              size: 70,
                              color: AppTheme.accentColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Nom app ────────────────────────────────────
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          letterSpacing: 1.5,
                        ),
                        children: [
                          TextSpan(
                            text: 'Immo',
                            style: TextStyle(color: Colors.white),
                          ),
                          TextSpan(
                            text: 'Zone',
                            style: TextStyle(color: AppTheme.accentColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Slogan ─────────────────────────────────────
                    const Text(
                      'Votre partenaire immobilier',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white60,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 70),

                    // ── Indicateur de chargement doré ──────────────
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        color: AppTheme.accentColor,
                        strokeWidth: 2.5,
                        backgroundColor: AppTheme.accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Chargement...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white38,
                        fontFamily: 'Poppins',
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bordure dorée subtile en bas
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(height: 3, color: AppTheme.accentColor),
          ),
        ],
      ),
    );
  }
}
