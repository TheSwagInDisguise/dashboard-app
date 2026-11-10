# DayDeck

`daydeck` — a single-user, **terminal-styled daily dashboard** for Android (sideloaded APK) with a web build for the desktop. Offline-first, no server of your own, no Google sign-in.

> Today's view · tasks · local events (private or queued for Google Calendar) · habits with streaks

![release](https://github.com/TheSwagInDisguise/dashboard-app/actions/workflows/release.yml/badge.svg)

---

## Status

**Phase 1 — scaffold & signed APK pipeline.** The app boots to the terminal-styled Today view with *sample* data (clearly labelled). Features land phase by phase — see [PROJECT_NOTES.md](PROJECT_NOTES.md) for the full roadmap and design decisions.

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Repos, CI, signed release APK, terminal theme | ✅ in progress |
| 2 | Tasks with on-device storage (offline) | planned |
| 3 | Sync to private `dashboard-data` repo (JSON, last-write-wins) | planned |
| 4 | Google Calendar feed (view-only iCal), Today view | planned |
| 5 | Local events, shared/private queue, evening reminder | planned |
| 6 | Habit tracker with streaks | planned |
| 7 | Web build on GitHub Pages | planned |

## Install (Android)

1. Open the [Releases](https://github.com/TheSwagInDisguise/dashboard-app/releases) page on your phone.
2. Download `app-release.apk` from the latest release.
3. Tap it; allow “install unknown apps” for your browser/file manager if prompted (one-time system dialog).
4. DayDeck appears in your launcher. Future APKs install over the top of older ones.

## Privacy & secrets

- This repository contains **code only — no tokens, no calendar data, no personal content, ever.**
- At runtime the app asks you for a GitHub token (created for you in **Settings → how to create your sync token**) and stores it **only on that device**, in platform secure storage. It is never synced, never logged, never shown again.
- Google Calendar is read **view-only** through your calendar's secret iCal address. DayDeck never signs in to Google and never writes to your calendar except via explicit one-tap “create event” links you open yourself.
- Shared/queued state lives in your **private** `dashboard-data` repo as plain JSON files (it is a data store, not a server).

## Build from source

```bash
flutter --version   # 3.47.9 stable
flutter pub get
flutter analyze
flutter test
flutter build apk --release   # signed if android/key.properties exists (CI only)
flutter build web --release
```

Releases are cut by pushing a tag `vX.Y.Z`; the [release workflow](.github/workflows/release.yml) builds the signed APK and publishes a GitHub Release.

## Layout

```
lib/
  theme/     palette tokens (4 schemes) + ThemeData builder + JetBrains Mono
  state/     app-wide state (scheme, reminder time, iCal URL, sync token)
  data/      sample data (Phase 1 only — replaced by real stores later)
  screens/   today / tasks / habits / settings + bottom-nav shell
  widgets/   scanline overlay, blinking cursor, section rules, chips
.github/workflows/release.yml   tag-driven signed-APK build → GitHub Releases
assets/      icon + OFL-licensed JetBrains Mono (assets/fonts/OFL.txt)
```

## License

MIT — see [LICENSE](LICENSE). Font: JetBrains Mono, SIL Open Font License 1.1.
