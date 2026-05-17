import 'package:flutter/material.dart';

class AppTheme {
  // ═══════════════════════════════════════════════════════════════════════
  // Palette ImmoZone — Bleu Marine #0A3A8F (maquette v1.2.22)
  // ═══════════════════════════════════════════════════════════════════════

  // Primary — Bleu marine maquette image 2
  static const Color primaryColor   = Color(0xFF0A3A8F); // Bleu marine principal
  static const Color primaryLight   = Color(0xFF1A52B0); // Bleu marine clair
  static const Color primaryDark    = Color(0xFF062A70); // Bleu marine très foncé
  static const Color accentColor    = Color(0xFF0A3A8F); // Même bleu marine

  // Couleur secondaire (vert Location badge)
  static const Color successColor   = Color(0xFF2E9E5B); // Vert badge Location
  static const Color secondaryColor = Color(0xFF2E9E5B);

  // Status Colors
  static const Color warningColor   = Color(0xFFF57F17);
  static const Color errorColor     = Color(0xFFC62828);
  static const Color infoColor      = Color(0xFF0A3A8F);

  // Surfaces / Backgrounds
  static const Color backgroundColor = Color(0xFFF4F6FB); // Fond app bleu-gris très léger
  static const Color surfaceColor    = Colors.white;
  static const Color cardColor       = Colors.white;
  static const Color dividerColor    = Color(0xFFE4E8F0);

  // Text
  static const Color textPrimary    = Color(0xFF1A1D2E); // Charcoal foncé
  static const Color textSecondary  = Color(0xFF6B7080); // Gris moyen
  static const Color textHint       = Color(0xFFA0A5B0); // Gris clair
  static const Color textOnPrimary  = Colors.white;

  // Property Status
  static const Color statusPending  = Color(0xFFF57F17);
  static const Color statusActive   = Color(0xFF2E9E5B);
  static const Color statusSold     = Color(0xFF0A3A8F);
  static const Color statusRented   = Color(0xFF2E9E5B);
  static const Color statusRejected = Color(0xFFC62828);

  // ═══════════════════════════════════════════════════════════════════════
  // Gradients
  // ═══════════════════════════════════════════════════════════════════════
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryDark, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Hero gradient: bleu marine → blanc → bleu très léger
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFD6E4FF), Color(0xFFEEF3FF), Color(0xFFF4F6FB)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFF1A52B0), Color(0xFF0A3A8F), Color(0xFF062A70)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ═══════════════════════════════════════════════════════════════════════
  // Light Theme
  // ═══════════════════════════════════════════════════════════════════════
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: successColor,
        surface: surfaceColor,
        error: errorColor,
      ),
      scaffoldBackgroundColor: backgroundColor,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      // Card
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 3,
        shadowColor: Color(0x1A0A3A8F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),

      // Elevated Button — taille uniforme, moins haute
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEEF2FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        hintStyle: const TextStyle(
          color: textHint,
          fontFamily: 'Poppins',
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontFamily: 'Poppins',
          fontSize: 14,
        ),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF9098A9),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEEF2FA),
        selectedColor: primaryColor,
        labelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
      ),

      // FloatingActionButton
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 6,
      ),

      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
    );
  }
}
