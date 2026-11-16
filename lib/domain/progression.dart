// XP & level rules — port of PersonalTerminal domain/Progression.

import 'dart:math' as math;

class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.xp,
    required this.xpIntoLevel,
    required this.xpForNext,
    required this.fraction,
  });

  final int level;
  final int xp;
  final int xpIntoLevel;
  final int xpForNext;
  final double fraction;
}

class Progression {
  static const int xpComplete = 10;
  static const int xpStreakWeek = 25;
  static const int xpPerfectDay = 20;

  /// Minimum version reached (half a completion).
  static const int xpMinimum = 5;

  /// Challenge stake multiplier.
  static const int challengeXpWin = 10;
  static const int challengeXpLose = 5;

  /// Total XP required to *reach* [level] (level 1 = 0 XP).
  static int xpForLevel(int level) => level <= 1 ? 0 : 50 * (level - 1) * level;

  static int levelForXp(int xp) {
    if (xp <= 0) return 1;
    final l = ((-1 + math.sqrt(1.0 + 4.0 * xp / 50.0)) / 2.0).floor();
    return l + 1;
  }

  static LevelProgress progress(int xp) {
    final level = levelForXp(xp);
    final base = xpForLevel(level);
    final next = xpForLevel(level + 1);
    final into = xp - base;
    final span = math.max(1, next - base);
    return LevelProgress(
      level: level,
      xp: xp,
      xpIntoLevel: into,
      xpForNext: span,
      fraction: (into / span).clamp(0.0, 1.0),
    );
  }

  /// Terminal-flavoured titles per level bracket.
  static String title(int level) {
    if (level >= 50) return 'kernel';
    if (level >= 40) return 'root';
    if (level >= 30) return 'sysadmin';
    if (level >= 20) return 'daemon';
    if (level >= 15) return 'maintainer';
    if (level >= 10) return 'contributor';
    if (level >= 5) return 'committer';
    if (level >= 2) return 'user';
    return 'guest';
  }

  // Shields: earned every 10 completions, capped at 3 held at once.
  static const int shieldEvery = 10;
  static const int maxShields = 3;

  static int shieldsEarned(int totalCompletions) => totalCompletions ~/ shieldEvery;

  static int shieldsAvailable(int totalCompletions, int shieldsUsed) =>
      (shieldsEarned(totalCompletions) - shieldsUsed).clamp(0, maxShields);
}
