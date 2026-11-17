# DayDeck

`daydeck` — a single-user, **terminal-styled daily dashboard** for Android (sideloaded APK) and iPhone (unsigned IPA re-signed on-device via Signulous), plus a web build for the desktop. Offline-first, no server of your own, no Google sign-in.

> Today's view · tasks · local events (private or queued for Google Calendar) · habits with streaks

![release](https://github.com/TheSwagInDisguise/dashboard-app/actions/workflows/release.yml/badge.svg)

---

## Status

**v0.11.0** — Android APK via releases; iPhone via unsigned IPA + Signulous; habits v2 (XP, levels, shields, streaks), watches wear-tracking, pomodoro focus timer, profile. Sync to a private `dashboard-data` repo; web build on GitHub Pages. See [PROJECT_NOTES.md](PROJECT_NOTES.md) for the full phase log.

## Install (iPhone)

1. Open the [Releases](https://github.com/TheSwagInDisguise/dashboard-app/releases) page on your phone or computer.
2. Download `DayDeck-unsigned.ipa` from the latest release (it is an *unsigned* build — CI never touches Apple signing credentials).
3. Upload the IPA at [signulous.com](https://www.signulous.com/); their signing platform re-signs it with its own certificate and gives you an install link for your iPhone.
4. Install from that link, then trust the certificate on the phone: **Settings → General → VPN & Device Management**.

No Xcode, no Mac, no Apple Developer membership required. Signing happens on Signulous' side — check their docs for certificate lifetimes and re-install when it expires.

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

Releases are cut by pushing a tag `vX.Y.Z`; the [release workflow](.github/workflows/release.yml) builds the signed APK **and** the unsigned IPA, and publishes both to a GitHub Release.

## Layout

```
lib/
  theme/     palette tokens (4 schemes) + ThemeData builder + JetBrains Mono
  state/     app-wide state (scheme, reminder time, iCal URL, sync token)
  data/      sample data (Phase 1 only — replaced by real stores later)
  screens/   today / tasks / habits / settings + bottom-nav shell
  widgets/   scanline overlay, blinking cursor, section rules, chips
.github/workflows/release.yml   tag-driven signed-APK + unsigned-IPA build → GitHub Releases
assets/      icon + OFL-licensed JetBrains Mono (assets/fonts/OFL.txt)
```

## License

MIT — see [LICENSE](LICENSE). Font: JetBrains Mono, SIL Open Font License 1.1.
