import 'package:flutter/material.dart';

const primaryRed = Color(0xFFEC0901);
const coral = Color(0xFFFF525B);
const canvas = Color(0xFFF8FAFB);
const mutedGray = Color(0xFFBDBDBD);
const softBorder = Color(0xFFE5EAED);
const slate = Color(0xFF556E78);
const deepSlate = Color(0xFF263D48);
const deviceReady = Color(0xFF2E9A63);

final appTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Nunito',
  colorScheme: const ColorScheme.light(
    primary: primaryRed,
    onPrimary: Colors.white,
    secondary: slate,
    onSecondary: Colors.white,
    tertiary: coral,
    onTertiary: Colors.white,
    surface: Colors.white,
    onSurface: deepSlate,
    error: primaryRed,
    onError: Colors.white,
    outline: softBorder,
  ),
  scaffoldBackgroundColor: canvas,
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: deepSlate,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    prefixIconColor: slate,
    suffixIconColor: slate,
    floatingLabelStyle: const TextStyle(color: primaryRed),
    errorStyle: const TextStyle(
      color: primaryRed,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: mutedGray),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: mutedGray),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: primaryRed, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: primaryRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: primaryRed, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: softBorder),
    ),
  ),
  dividerColor: softBorder,
  navigationBarTheme: NavigationBarThemeData(
    height: 70,
    indicatorColor: Colors.transparent,
    backgroundColor: Colors.white,
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? primaryRed : slate,
        size: 24,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.selected) ? primaryRed : slate,
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
      ),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryRed,
      foregroundColor: Colors.white,
      disabledBackgroundColor: primaryRed.withValues(alpha: 0.65),
      disabledForegroundColor: Colors.white,
      overlayColor: slate.withValues(alpha: 0.18),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
);
