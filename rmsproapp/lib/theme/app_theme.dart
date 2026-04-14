import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary brand colors
  static const primary = Color(0xFF00C47D);
  static const primaryDark = Color(0xFF009960);
  static const primaryLight = Color(0xFFE6FFF5);

  // Backgrounds - WHITE THEME
  static const bg = Color(0xFFF8FAFC);
  static const bgDeep = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const side = Color(0xFFF1F5F9);

  // Accent colors
  static const yellow = Color(0xFFF59E0B);
  static const yellowLight = Color(0xFFFEF3C7);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFFDBEAFE);
  static const red = Color(0xFFEF4444);
  static const redDark = Color(0xFFDC2626);
  static const redLight = Color(0xFFFEE2E2);
  static const green = Color(0xFF10B981);
  static const greenLight = Color(0xFFD1FAE5);
  static const cyan = Color(0xFF06B6D4);
  static const orange = Color(0xFFF97316);
  static const orangeLight = Color(0xFFFED7AA);

  // Text colors - LIGHT THEME
  static const textPrimary = Color(0xFF0F172A);
  static const textSub = Color(0xFF334155);
  static const textMuted = Color(0xFF64748B);
  static const textDim = Color(0xFF94A3B8);

  // Border colors - LIGHT THEME
  static const border = Color(0xFFE2E8F0);
  static const borderMed = Color(0xFFCBD5E1);
  static const borderLight = Color(0xFFF1F5F9);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.yellow,
        surface: AppColors.card,
        error: AppColors.red,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgDeep,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800),
        hintStyle: const TextStyle(color: AppColors.textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
          elevation: 2,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Keep darkTheme for backward compatibility but redirect to light
  static ThemeData get darkTheme => lightTheme;
}
