# PROJECT_NOTES.md — DayDeck

Working notes for DayDeck (a.k.a. the dashboard app). **Read this first** in every new session.
The GitHub repos are the source of truth — workspace snapshots of `/home/user` strip
`.git/` directories and executable bits, and exclude hidden dot-folders, so local copies may
look broken but the pushed repos are never affected.

_Last updated: 2026-11-10 (Phase 2 implemented & released as v0.2.0)_

---

## 1. What DayDeck is

Single-user, terminal-styled **daily dashboard** for Android (sideloaded APK) + a web build
(GitHub Pages, Phase 7). Offline-first, no self-hosted server, no Google OAuth.

- **Today view** — Google Calendar events + tasks + habits
- **Tasks** — add / edit / complete, due dates, simple priority (P1–P3)
- **Local events** — `private` (stays on device) and `shared` (queued → evening notification
  → one-tap prefilled Google Calendar “create event” link → auto-marked done when the iCal feed
  shows it)
- **Google Calendar** — view-only via the calendar’s secret iCal URL
- **Habits** — short daily list, tick off, current streak

Design: dark by default; near-black background; JetBrains Mono for headings/times/counts/streaks;
readable sans (system) for body text; bright terminal accents; subtle scanlines + blinking
block cursor; 4 schemes in Settings (`modern` default — user pick 2026-11-10 —, `classic green`,
`amber`, `light` fallback). Time/date: 24h + DD/MM/YYYY.

## 2. Repos & where things live

| Repo | Visibility | Purpose |
|---|---|---|
| `TheSwagInDisguise/dashboard-app` | **public** | Code, CI, Releases (installable APKs). **No secrets, no personal data, ever.** |
| `TheSwagInDisguise/dashboard-data` | **private** | Sync store (JSON) + `calendar.json` cache for the web build. No code. |

- Release downloads (on the phone): <https://github.com/TheSwagInDisguise/dashboard-app/releases>
- Data repo holds: `tasks.json`, `events.json`, `habits.json`, `conflicts.json`, `calendar.json` (Phases 3–6)

## 3. Tokens & secrets (inventory — names only, never values)

| Secret name | Where | Purpose |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | repo secret on **dashboard-app** | base64 of the PKCS12 release keystore |
| `ANDROID_KEYSTORE_PASSWORD` | repo secret on **dashboard-app** | keystore password |
| `ANDROID_KEY_ALIAS` | repo secret on **dashboard-app** | `daydeck` |
| `ANDROID_KEY_PASSWORD` | repo secret on **dashboard-app** | key password (same as store password) |
| `ICAL_URL` | repo secret on **dashboard-data** (Phase 4) | Google Calendar secret iCal address; used by the hourly Action |

Two fine-grained personal access tokens exist:

1. **Build/deploy token** (“daydeck-build”, provided 2026-11-10) — for the agent. Scope:
   *only* `dashboard-app` + `dashboard-data`; permissions Contents/Workflows/Actions/Secrets: R&W.
   It was pasted into chat by the owner at their choice; treat as semi-exposed — recommend
   revoking and minting a fresh one when convenient (or rotate after Phase 1). It is stored at
   `/home/user/daydeck-private/github-token` (workspace, `chmod 600`) and used only via
   env-var + `GIT_ASKPASS` — **never** echoed, logged, committed or embedded in files that leave
   the machine.
2. **App token** (“daydeck-app”, to be created by the owner following the in-app guide or the
   steps below) — lives **only in the app** on each device (secure/local storage). Scope:
   `dashboard-data` only, Contents: Read & write, Metadata: Read-only. Used for GitHub Contents API.

### Creating the app (sync) token — same steps ship inside the app (Settings → SYNC)
1. github.com → avatar → **Settings** → **Developer settings** → **Personal access tokens** →
   **Fine-grained tokens** → **Generate new token**
2. Name: `daydeck-app`; pick the longest expiry you’re comfortable with (note the date — expired
   token = banner in app + paste-new-token flow)
3. Repository access → **Only select repositories** → tick **dashboard-data** only
4. Repository permissions → **Contents: Read and write** (Metadata stays Read-only); nothing else
5. **Generate token**, copy the `github_pat_…` value once, paste it in DayDeck →
   **Settings → SYNC → SAVE TOKEN**. It never leaves that device.

> ✅ Done 2026-11-10: owner created both repos (empty) and provided the build token; keystore
> generated 2026-11-10 (PKCS12, alias `daydeck`, validity to 2054, SHA-256
> `95:23:D2:ED:1F:4A:EF:FD:84:EE:30:F8:28:21:C4:7D:8E:B9:15:CC:D8:67:F5:88:0D:5C:08:02:60:5B:CD:17`).

### Keystore handling
- The keystore and its password live at `/home/user/daydeck-private/` **until the first green
  Release build**, then they will be **deleted from this machine** — from then on the keystore
  exists only as GitHub repo secrets.
- `.gitignore` blocks `*.p12`, `**/key.properties`, `daydeck-private/` defensively.

## 4. Session log

### 2026-11-10 — Phase 1 kickoff ("hello world" APK + pipeline + theme)
Done locally (all verified):
- Flutter SDK **3.47.9** stable (Dart 3.13.7) installed at `/home/user/flutter-sdk`
  (see *Environment gotchas* — needs re-hydration after snapshots).
- App scaffolded: `flutter create --org io.github.theswagindisguise --project-name daydeck`
  → `io.github.theswagindisguise.daydeck`; version `0.1.0+1`.
- **Theme system** implemented: 4 palettes (`modern` default; `classicGreen`; `amber`; `light`),
  Material 3 ThemeData builder, JetBrains Mono **bundled** (assets/fonts, SIL OFL) → works offline.
- Today view (preview): wordmark + blinking cursor, live clock, date block, `// CALENDAR` /
  `// TASKS` / `// HABITS` sections with sample data (GCAL / SHARED ⧗ / LOCAL chips, P1–P3
  chips, 7-day habit dots, streak counts), scanline overlay, bottom nav (TODAY/TASKS/HABITS/SETTINGS).
- Tasks/Habits tabs: honest "ARRIVES IN PHASE N" stubs with interface previews.
- Settings screen: working scheme picker; **in-app guide for creating the app’s sync token**
  (user request 2026-11-10); token paste/save/remove via `flutter_secure_storage` (never logged);
  evening reminder time picker (default **19:00**, persisted); iCal URL field (persisted); ABOUT with links.
- Android: `android:label=DayDeck`, `INTERNET` permission, release signing config wired to
  `android/key.properties` + `android/app/keystore.p12` (created only in CI from repo secrets;
  local falls back to debug signing — never published).
- Web: `index.html` title/`theme-color` dark; manifest dark; icons/favicon regenerated from
  DayDeck icon (no Flutter branding anywhere).
- App icon: PIL-rendered `>_` cyan glyph + glow on near-black; adaptive icon for Android.
- `flutter analyze` clean; `flutter test` **2/2 green** (note: tests must use
  `AppState.inMemory()` — `flutter_secure_storage` deadlocks the test harness).
- `flutter build web --release` started but **local dart2js is extremely slow on this 2-core /
  2 GB VM** (timed out at ~277 s once; restarted in background). Not blocking: the phone-facing
  deliverable is the APK, built by CI. (Web deploy is Phase 7 regardless; CI runners are fast.)

Pushed & shipped (this same session):
- Secrets `ANDROID_KEYSTORE_BASE64` / `_PASSWORD` / `ANDROID_KEY_ALIAS`=daydeck / `_PASSWORD`
  set via GitHub API (sealed-box). **Values were never printed or written to disk.**
- `main` pushed; tag `v0.1.0` → workflow run **42790236151 — all jobs GREEN on first try**.
- Release published: https://github.com/TheSwagInDisguise/dashboard-app/releases/tag/v0.1.0
  — asset `app-release.apk` (52.5 MB)
  — direct link: https://github.com/TheSwagInDisguise/dashboard-app/releases/download/v0.1.0/app-release.apk
- 2026-11-10 09:30 UTC: **local keystore + password deleted** — GitHub repo secrets are now the
  only copies. (Rebuilds work unchanged; the signing identity is preserved.)
- A live web preview of this build is being served on port 8090 of this machine.

Outstanding for the owner: install v0.2.0 APK on phone and run the Phase-2 checklist
(in the session report): add/complete/edit/delete/persist-across-restart/due dates/priority/
today view shows live tasks.

### 2026-11-10 — Phase 2 (tasks, local storage)
- **Storage decision locked**: single JSON document in `shared_preferences` (key `tasks_json`)
  with the previous good copy rotated to `tasks_json_backup` on every save; corrupt main →
  transparent restore from backup + an in-app recovery banner (`TasksStore.recoveryNotice`).
  No SQL engine; model already carries `updatedAt` + soft-delete tombstones for Phase 3 LWW.
- Model: `lib/models/task.dart` (`id`, `title`, `done`, `priority` P1–P3, `dueDate` `YYYY-MM-DD`,
  `createdAt/updatedAt/deletedAt`). Store: `lib/state/tasks_store.dart` (ChangeNotifier;
  atomic rotate-then-write; `openTasks` sort = due-first → priority → newest; tombstoned deletes).
- UI: Tasks tab is fully live (add/edit/complete/delete; due chips today/tomorrow/DD-MM(+YYYY);
  overdue in red; `CLEAR DONE` with confirm; empty state; recovery banner). Today view tasks
  section now renders the live store (top 4 open); ghost row opens the sheet; sysbar shows
  real open/overdue counts. Add/Edit via bottom sheet (`lib/widgets/task_sheet.dart`) with
  priority segmented control + due quick-chips (none/today/tomorrow/pick) and date picker.
- Dates: `lib/utils/dates.dart` — AU 24-h, DD/MM/YYYY display, day-granularity keys.
- Version const file: `lib/version.dart` (`kAppVersion = '0.2.0'`, keep in sync with pubspec).
- Verified: `flutter analyze` clean · **7/7 tests green** (store logic incl. corrupt-backup
  recovery + 3 widget tests). Released as **v0.2.0** (tag pushed; CI publishes Release).

## 5. Environment gotchas (this Arena workspace)

- **Snapshots strip `.git/` directories and executable bits**, and exclude **hidden dot-folders**
  entirely (a `/home/user/.secrets` directory vanished between turns on 2026-11-10 — everything
  had to be re-created under the non-hidden `/home/user/daydeck-private/`).
- **GitHub is the source of truth.** If the local checkout is broken: fresh `git clone`.
- Flutter re-hydration after each restore: `bash /home/user/daydeck-private/ensure-flutter.sh`
  (re-clones if `.git` missing; re-fetches tag `3.47.9`; restores exec bits by magic bytes),
  then `export PATH="/home/user/flutter-sdk/bin:$PATH"`.
- `flutter --version` fails with *“requires Git”* when `.git` is missing; and `pub get` reports
  **“The current Flutter SDK version is 0.0.0-unknown”** until the `3.47.9` tag exists — that’s why
  the ensure script fetches it.
- `flutter test` hangs if app code touches platform plugins at load time; keep widget tests on
  `AppState.inMemory()`.
- Don’t `pkill -f <pattern>` where the pattern matches your own bash command line.
- GitHub token goes in the environment only; use an `askpass` helper in `/tmp` for git over HTTPS
  (remote URL stays token-free, `.git/config` stays clean).

## 6. Sync architecture (decided 2026-11-10 — build in Phases 3–5)

- **Format**: JSON files in `dashboard-data` (`tasks.json`, `events.json`, `habits.json`,
  `conflicts.json`). Per-item `updatedAt` (ISO-8601, UTC) + `deletedAt` tombstones where needed.
  Every item LWW on `updatedAt`; **conflicts are parked in `conflicts.json`, never silently
  dropped**; every sync write is a git commit (free undo/history/audit).
- **API**: GitHub Contents REST API (`GET/PUT /repos/{owner}/repo/contents/{path}` with `sha`
  precondition). 409 sha-mismatch → re-fetch, merge, retry; still conflicting → `conflicts.json`.
- **Web**: same API from the browser with the app token (Pages is public; data is not).
- **iCal**: secret address stays out of the web bundle. A scheduled Action in `dashboard-data`
  (hourly cron) fetches the iCal feed (URL in repo secret `ICAL_URL`), converts to JSON, commits
  `calendar.json` (only when changed). Web reads `calendar.json` with the app token; Android
  fetches the feed **directly** (fallback: `calendar.json`). Expect Google-side latency of hours.
- **Auto-mark shared events**: match on normalised title + start time (±30 min); when matched,
  set `done: true` with `completedAt` timestamp; surfaced as `SHARED ✓`.
- **Sync cadence**: on app open + pull/button + after every mutation (debounced). No background
  service (battery + complexity). Delta-sync is overkill at this scale — full file round-trip is fine.
- **Schema version**: `manifest.json` with `schemaVersion` for future migrations.

## 7. Phase roadmap

- [x] Phase 0 — decisions, questions answered (2026-11-10): name DayDeck · modern scheme default ·
      24h/DD-MM-YYYY · keystore generate-and-hand-off-via-secrets · MIT licence
- [ ] Phase 1 — repo + CI + signed APK + theme **(this session — verify install on phone)**
- [x] Phase 2 — tasks: local storage (JSON + backup), add/edit/complete/due/priority
- [ ] Phase 3 — sync to `dashboard-data` (Contents API, LWW + conflicts.json); sync status in header
- [ ] Phase 4 — iCal fetch (Android direct + data-repo hourly Action → `calendar.json`); Today view;
      token-expired banner + paste-new-token flow
- [ ] Phase 5 — local events; shared/private split; evening reminder notification (inexact alarm,
      `POST_NOTIFICATIONS`, runtime request); prefilled `calendar.google.com/calendar/render?action=TEMPLATE`
      links; auto-mark done via feed match
- [ ] Phase 6 — habits + streaks on Today view
- [ ] Phase 7 — web `flutter build web` → GitHub Pages (enable Pages: Settings → Pages →
      Source: **GitHub Actions**, 2 clicks the owner must do); web reads data with app token

## 8. Open decisions (bring up with owner)

1. ~~Phase 2 storage engine~~ — decided 2026-11-10: JSON document + automatic backup (see Phase 2 log).
2. **Icon** — PIL-rendered candidate; owner hasn’t signed off yet (can swap later, cheap).
3. **Theme sign-off** — `modern` default chosen 2026-11-10 from preview; owner may still tweak
   hues/density ("tell me what to change").
4. **Keystore fingerprint** — confirm owner is OK that only GitHub secrets hold it (local copies
   deleted after first green release).
5. **Rotate build token?** — paste-into-chat exposure was owner’s call; suggest rotating when
   Phase 1 is verified.

## 9. Command cheat sheet

```bash
bash /home/user/daydeck-private/ensure-flutter.sh     # re-hydrate SDK after restore
export PATH="/home/user/flutter-sdk/bin:$PATH"
cd /home/user/dashboard-app
flutter pub get && flutter analyze && flutter test
grep -R "github_pat_" .                               # must print NOTHING before pushing
# git push without persisting the token:
printf '#!/bin/sh\ncase "$1" in *Username*) printf "x-access-token";; *Password*) printf "$GITHUB_TOKEN";; esac\n' > /tmp/askpass && chmod 700 /tmp/askpass
GIT_ASKPASS=/tmp/askpass GIT_TERMINAL_PROMPT=0 GITHUB_TOKEN=$(cat /home/user/daydeck-private/github-token) git push origin main
```

## 10. Immediate next steps

1. ~~Phase 1~~ shipped 2026-11-10 (v0.1.0, CI green, local keystore deleted).
2. ~~Phase 2~~ shipped 2026-11-10 (v0.2.0). Owner to install + checklist.
3. Collect any theme tweaks; if behaviour changes are requested, cut `v0.2.1`.
4. Phase 3 kickoff: sync to `dashboard-data` (Contents API, LWW + conflicts.json, schemaVersion
   manifest); start with read-only pull + push of tasks; conflict UI minimal; token-expired banner.
