import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// auth_ui.dart — Styles partagés des écrans d'authentification
// Design « Premium bandeau marque » (Option B) :
//   - aucune carte bordée, aucun contour superflu
//   - champs soulignés d'un trait fin 1.5px (focus bleu, erreur rouge)
//   - bouton pilule dégradé bleu avec ombre colorée
//   - accents orange marque (AppTheme.orangeColor)
// ─────────────────────────────────────────────────────────────────────────────

/// Dégradé bleu marque utilisé pour bandeaux et boutons.
const kAuthGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xFF082F75),
    AppTheme.primaryColor,
    Color(0xFF1656C9),
  ],
);

/// Petit label au-dessus d'un champ souligné.
Widget authFieldLabel(String text) => Text(text,
    style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.2));

/// Décoration « souligné fin » pour TextFormField / TextField.
InputDecoration authUnderlineDecoration({
  String? hintText,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) {
  const enabled = UnderlineInputBorder(
      borderSide: BorderSide(color: AppTheme.dividerColor, width: 1.5));
  const focused = UnderlineInputBorder(
      borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5));
  const error = UnderlineInputBorder(
      borderSide: BorderSide(color: AppTheme.errorColor, width: 1.5));
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(
        fontFamily: 'Poppins', color: AppTheme.textHint, fontSize: 12.5),
    filled: false,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 15),
    border: enabled,
    enabledBorder: enabled,
    focusedBorder: focused,
    errorBorder: error,
    focusedErrorBorder: error,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
  );
}

/// Bouton pilule dégradé bleu (style « Se connecter » du login).
class AuthPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? trailingIcon;
  final Gradient? gradient;
  final Color? shadowColor;

  const AuthPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.trailingIcon = Icons.arrow_forward_rounded,
    this.gradient,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final g = gradient ?? kAuthGradient;
    final sc = shadowColor ?? AppTheme.primaryColor;
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: Container(
          decoration: BoxDecoration(
            gradient: g,
            borderRadius: BorderRadius.circular(27),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: sc.withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27)),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white)),
                      if (trailingIcon != null) ...[
                        const SizedBox(width: 8),
                        Icon(trailingIcon, size: 18, color: Colors.white),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
