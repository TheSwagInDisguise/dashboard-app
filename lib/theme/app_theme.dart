import 'package:flutter/material.dart';

import 'palettes.dart';

/// Builds a Material 3 ThemeData from a [TerminalPalette]. Everything colour-
/// related derives from the palette so schemes stay perfectly in sync.
ThemeData buildDayDeckTheme(TerminalPalette p) {
  final colorScheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.bg,
    primaryContainer: p.panel2,
    onPrimaryContainer: p.accent,
    secondary: p.accent2,
    onSecondary: p.bg,
    secondaryContainer: p.panel2,
    onSecondaryContainer: p.accent2,
    tertiary: p.good,
    onTertiary: p.bg,
    error: p.bad,
    onError: p.bg,
    surface: p.panel,
    onSurface: p.text,
    surfaceContainerHighest: p.panel2,
    onSurfaceVariant: p.dim,
    outline: p.border,
    outlineVariant: p.border,
    shadow: const Color(0x55000000),
  );

  final base = p.isLight ? ThemeData.light().textTheme : ThemeData.dark().textTheme;
  final textTheme = base.apply(bodyColor: p.text, displayColor: p.text);

  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: 1),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    cardColor: p.panel,
    dividerColor: p.border,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    splashColor: p.accent.withValues(alpha: 0.08),
    highlightColor: p.accent.withValues(alpha: 0.05),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.panel2,
      hintStyle: TextStyle(color: p.dim),
      labelStyle: TextStyle(color: p.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: border(p.border),
      enabledBorder: border(p.border),
      focusedBorder: border(p.accent),
      errorBorder: border(p.bad),
      focusedErrorBorder: border(p.bad),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.panel2,
      contentTextStyle: TextStyle(color: p.text, fontSize: 13),
      actionTextColor: p.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel2,
      titleTextStyle: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.w700,
        color: p.accent,
        fontSize: 16,
        letterSpacing: 1.2,
      ),
      contentTextStyle: TextStyle(color: p.text, fontSize: 13, height: 1.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.border),
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: p.panel,
      collapsedBackgroundColor: p.panel,
      textColor: p.text,
      iconColor: p.accent,
      collapsedTextColor: p.text,
      collapsedIconColor: p.dim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: p.text,
      iconColor: p.dim,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStatePropertyAll(p.accent),
      checkColor: WidgetStatePropertyAll(p.bg),
      side: BorderSide(color: p.dim),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStatePropertyAll(p.accent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(p.accent),
      trackColor: WidgetStatePropertyAll(p.panel2),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.panel2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      textStyle: TextStyle(color: p.text, fontSize: 12),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
  );
}

/// Short, opinionated monospace style helper for the terminal look.
TextStyle mono(
  BuildContext context, {
  double size = 12,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double letterSpacing = 0,
}) {
  return TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    fontWeight: weight,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    letterSpacing: letterSpacing,
  );
}
