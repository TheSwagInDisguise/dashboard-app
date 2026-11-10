import 'package:flutter/material.dart';

/// The four DayDeck colour schemes. `modern` is the default; `light` is the
/// accessibility fallback. Schemes are intentionally just colour tokens — no
/// other design decisions leak in.
enum DayDeckScheme { modern, classicGreen, amber, light, amoled }

class TerminalPalette {
  const TerminalPalette({
    required this.scheme,
    required this.label,
    required this.descriptor,
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.border,
    required this.text,
    required this.dim,
    required this.accent,
    required this.accent2,
    required this.good,
    required this.warn,
    required this.bad,
    required this.brightness,
    required this.scanlineAlpha,
  });

  final DayDeckScheme scheme;
  final String label;
  final String descriptor;

  // Surfaces
  final Color bg;
  final Color panel;
  final Color panel2;
  final Color border;

  // Content
  final Color text;
  final Color dim;
  final Color accent;
  final Color accent2;
  final Color good;
  final Color warn;
  final Color bad;

  final Brightness brightness;

  /// Opacity of the subtle CRT scanline texture painted over the UI.
  final double scanlineAlpha;

  bool get isLight => brightness == Brightness.light;
}

const Map<DayDeckScheme, TerminalPalette> kPalettes = {
  DayDeckScheme.modern: TerminalPalette(
    scheme: DayDeckScheme.modern,
    label: 'modern',
    descriptor: 'cyan + magenta on near-black charcoal',
    bg: Color(0xFF0F1117),
    panel: Color(0xFF151824),
    panel2: Color(0xFF1B1F2E),
    border: Color(0xFF252B3F),
    text: Color(0xFFD7DBE8),
    dim: Color(0xFF7E86A3),
    accent: Color(0xFF22D3EE),
    accent2: Color(0xFFE879F9),
    good: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    bad: Color(0xFFF87171),
    brightness: Brightness.dark,
    scanlineAlpha: 0.05,
  ),
  DayDeckScheme.classicGreen: TerminalPalette(
    scheme: DayDeckScheme.classicGreen,
    label: 'classic green',
    descriptor: 'phosphor green on black — the signature look',
    bg: Color(0xFF061009),
    panel: Color(0xFF0B1A10),
    panel2: Color(0xFF102313),
    border: Color(0xFF1D3423),
    text: Color(0xFFC4F2CD),
    dim: Color(0xFF5E916D),
    accent: Color(0xFF3DF07A),
    accent2: Color(0xFFFFD866),
    good: Color(0xFF3DF07A),
    warn: Color(0xFFFFD866),
    bad: Color(0xFFFF6E6E),
    brightness: Brightness.dark,
    scanlineAlpha: 0.055,
  ),
  DayDeckScheme.amber: TerminalPalette(
    scheme: DayDeckScheme.amber,
    label: 'amber',
    descriptor: 'warm amber on soft black — retro CRT',
    bg: Color(0xFF110B03),
    panel: Color(0xFF1A1206),
    panel2: Color(0xFF221809),
    border: Color(0xFF332413),
    text: Color(0xFFF4E3BD),
    dim: Color(0xFFA3804E),
    accent: Color(0xFFFFB000),
    accent2: Color(0xFF8EC07C),
    good: Color(0xFF8EC07C),
    warn: Color(0xFFFFB000),
    bad: Color(0xFFFF6B4A),
    brightness: Brightness.dark,
    scanlineAlpha: 0.055,
  ),
  DayDeckScheme.amoled: TerminalPalette(
    scheme: DayDeckScheme.amoled,
    label: 'amoled',
    descriptor: 'true black — made for the fold panel',
    bg: Color(0xFF000000),
    panel: Color(0xFF0B0B0D),
    panel2: Color(0xFF121214),
    border: Color(0xFF222226),
    text: Color(0xFFE9E9ED),
    dim: Color(0xFF71717A),
    accent: Color(0xFF22D3EE),
    accent2: Color(0xFFE879F9),
    good: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    bad: Color(0xFFF87171),
    brightness: Brightness.dark,
    scanlineAlpha: 0.03,
  ),
  DayDeckScheme.light: TerminalPalette(
    scheme: DayDeckScheme.light,
    label: 'light',
    descriptor: 'terminal-ink on paper — the fallback scheme',
    bg: Color(0xFFEEF0F4),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF2F3F7),
    border: Color(0xFFD5D8E0),
    text: Color(0xFF22262F),
    dim: Color(0xFF6D7488),
    accent: Color(0xFF0E7490),
    accent2: Color(0xFFBE185D),
    good: Color(0xFF15803D),
    warn: Color(0xFFB45309),
    bad: Color(0xFFB91C1C),
    brightness: Brightness.light,
    scanlineAlpha: 0.03,
  ),
};

TerminalPalette paletteOf(DayDeckScheme scheme) => kPalettes[scheme]!;
