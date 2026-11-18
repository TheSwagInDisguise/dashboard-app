import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daydeck/theme/palettes.dart';
import 'package:daydeck/state/app_state.dart';

void main() {
  test('PersonalTerminal theme families expose a dark and light palette', () {
    expect(kPersonalTerminalThemeFamilies, hasLength(15));
    expect(kPersonalTerminalPalettes, hasLength(30));

    for (final family in kPersonalTerminalThemeFamilies) {
      final dark = paletteOf(family.darkScheme);
      final light = paletteOf(family.lightScheme);
      expect(dark.brightness, Brightness.dark, reason: family.label);
      expect(light.brightness, Brightness.light, reason: family.label);
      expect(dark.label, isNotEmpty, reason: family.label);
      expect(light.label, isNotEmpty, reason: family.label);
    }
  });

  test('selecting a PersonalTerminal light variant updates the active palette', () async {
    final app = AppState.inMemory();
    await app.setScheme(DayDeckScheme.nordLight);
    expect(app.palette.label, 'Nord Light');
    expect(app.palette.brightness, Brightness.light);
  });

  test('all requested PersonalTerminal families are present', () {
    expect(
      kPersonalTerminalThemeFamilies.map((family) => family.label),
      containsAll([
        'Dracula',
        'Nord',
        'Solarized',
        'Gruvbox',
        'Monokai',
        'Catppuccin',
        'Tokyo Night',
        'One Dark',
        'Rosé Pine',
        'Everforest',
        'Amber CRT',
        'Matrix',
        'Hacker',
        'Synthwave ’84',
        'Signal',
      ]),
    );
  });
}
