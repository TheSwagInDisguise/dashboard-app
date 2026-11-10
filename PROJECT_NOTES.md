# PROJECT_NOTES.md — DayDeck

Working notes for DayDeck (a.k.a. the dashboard app). **Read this first** in every new session.
The GitHub repos are the source of truth — workspace snapshots of `/home/user` strip
`.git/` directories and executable bits, and exclude hidden dot-folders, so local copies may
look broken but the pushed repos are never affected.

_Last updated: 2026-11-10 (v0.8.0 — AMOLED + task reminders + roadmap features 1–12)_

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
- [x] Phase 3 — sync to `dashboard-data` (Contents API, LWW + conflicts.json); sync status in header + Settings
- [x] Phase 4 — view-only Google Calendar (iCal on Android; hourly `calendar.json` Action for web); cache + auto-refresh on resume
- [x] Phase 5 — local events (PRIVATE/SHARED, notes+location, all-day) on Today; SHARED queue; 20:30 evening local notification; SHARED auto-hides once seen in gcal
- [x] Phase 6 — habit tracker (daily/weekly, current week dots, streaks) on Today + HABITS tab; syncs like everything else
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

### 2026-11-10 — Phase 3 (sync to GitHub data repo)
- **Storage of record**: `TheSwagInDisguise/dashboard-data` — `tasks.json`, `conflicts.json`,
  `manifest.json` (all seeded 2026-11-10 with pristine empty documents).
- **Verified live against the real repo** (via API, using the build token): 404-on-fresh → create,
  base64 round-trip, correct-sha PUT → 200, **stale-sha PUT → 409** (the exact precondition the
  retry-once path depends on), manifest/conflicts seeding. Repo restored to pristine empty seed.
- Engine: `lib/sync/github_client.dart` (Contents API, no dart:io → web-safe), `lib/sync/merger.dart`
  (pure LWW, deterministic tiebreak, losers tagged local/remote), `lib/sync/sync_service.dart`
  (orchestration). Merge rule: per-item LWW on `updatedAt`; any semantic loser is parked —
  **both** in repo `conflicts.json` and an on-device pending queue (`sync_conflicts_pending`) that
  retries until the remote write succeeds. Losers can exceed the 200-entry cap? capped to newest
  200 remote / 500 local.
- Cadence: on app open (unawaited, never blocks UI), on resume via debounce after ANY mutation
  (4s), manual SYNC NOW. Concurrent calls coalesce (single queued rerun). No background service.
- UX: Today status strip shows `⇡ synced HH:MM` / `⇡ syncing…` / `⚠ sync paused` / `⇡ offline`
  (tap for explanation). Settings → SYNC shows live status + SYNC NOW + inline guidance when the
  token is rejected. **Shell-level persistent banner** when GitHub rejects the token (401/403),
  one tap jumps to Settings to paste a new one. Token removed → sync turns off cleanly.
- Conflict detection granularity: only semantically-differing items are parked (LWW applies).
- Widget tests provide a SyncService with NO token → inert (no network). Merge logic unit-tested
  (8 tests). **15/15 tests green; analyze clean.**
- Web build compiles ✓; sync is HTTP-header based → works from GitHub Pages origin too (Phase 7).

### 2026-11-10 — Phases 4–6 (calendar, local events + reminder, habits) — v0.6.1
- **iCal sources**: Android/desktop → direct fetch of secret iCal URL (stored in SECURE storage;
  the prefs copy migrates automatically). Web → `calendar.json` in dashboard-data, refreshed hourly
  by the `refresh-calendar` Action (in-repo workflow, created 2026-11-10, verified green with
  ICAL_URL unset — skips cleanly with a notice). Web reads it via the Contents API + sync token.
- **iCal parser** (`lib/data/ics.dart`, hand-rolled, no deps): unfolds lines, TZID-floating/local
  times = device-local, `…Z` = UTC, all-day VALUE=DATE = local midnight; RRULE DAILY/WEEKLY(BYDAY)/
  MONTHLY(BYMONTHDAY)/YEARLY + INTERVAL/UNTIL/COUNT; EXDATE; RECURRENCE-ID overrides; cancelled
  skipped; unbounded series fast-forward to the window. Window: [yesterday, +31 days].
- **Events** (`events.json`): title, start/end or all-day, PRIVATE/SHARED visibility, notes,
  location, tombstoned deletes, LWW sync. SHARED = "I'll add this to Google Calendar myself";
  once the same title (±30 min, or same day for all-day) appears in the feed, it is auto-marked
  done and disappears from Today (owner choice 2026-11-10). The SHARED QUEUE dialog on Today
  (only visible when pending shared events exist on OTHER days) allows one-tap “IN GCAL ✓”.
- **Evening reminder**: 20:30 local notification (owner choice; default moved from 19:00, stored
  19:00 values migrate). flutter_local_notifications + inexactAllowWhileIdle (no exact-alarm
  permission), POST_NOTIFICATIONS + boot receivers declared; web = silent no-op. Asks permission
  once after first frame; reschedules automatically when the time changes in Settings.
- **Habits** (`habits.json` + `habit_logs.json`, ids `habitId|yyyy-mm-dd`): start EMPTY (owner
  choice); daily/weekly cadence; streaks (daily = consecutive days ending today/yesterday; weekly =
  consecutive Mon–Sun weeks with ≥1 check-in); week dots Mon..Sun; tap to toggle today; delete =
  tombstone. Syncs through the same engine.
- **Sync engine generalized**: `_Doc<T>` registry (tasks/events/habits/habit_logs) — ONE code path,
  per-document LWW with the same conflicts.json parking (conflict entries now carry `doc`).
  Local edits made DURING a sync pass now win outright (overlay by updatedAt at apply/push time) —
  closes the old replaceAll clobber race.
- **web cron verified**: dispatched `refresh-calendar` manually → green; converter logic
  (icalendar + recurring-ical-events) validated against a synthetic ICS locally — expands
  weekly-BYDAY with UNTIL, all-day, cancelled-skip, TZID→UTC conversion correctly.
- **v0.6.0 CI failed** (`Build signed release APK`): `flutter_local_notifications` requires
  Android core-library desugaring — fixed by `isCoreLibraryDesugaringEnabled = true` +
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`; released as **v0.6.1**
  (v0.6.0 tag removed, never had a release).
- Widget tests provide all stores + feed (inert without token/URL). **30/30 tests green; analyze clean.**
- iCal gotcha to know: feed DTSTART without Z and with TZID is read as DEVICE-LOCAL time — correct
  when the phone is in the same zone as the calendar (Australia/Sydney). Wrong otherwise (rare).

## v0.8.0 — AMOLED + task reminders + roadmap 1–12 (2026-11-10)

Owner asked to implement everything on the v0.7.0 roadmap, with emphasis on the **AMOLED
palette** and **task reminders**. All 12 roadmap items shipped, plus per-task reminders.

- **AMOLED scheme** (#10): pure-black bg (`000000`), panel `0B0B0D`/`121214`, cyan/magenta
  accents kept, scanlines 0.03. Fifth scheme in APPEARANCE (modern stays default).
- **Per-task reminders** (owner-emphasised): tasks gain nullable `reminderAt` (UTC instant,
  JSON key `reminderAt` — additive, sync-safe). Task sheet: set a due date → "reminder"
  switch + time picker (default 09:00). Fires via a new `daydeck_tasks` channel
  (high importance), id allocated from a persisted seq map (prefs
  `task_reminder_map`/`when`/`seq`), reconciled against the store on every change
  (`ReminderService.syncTaskReminders`) — done/deleted/rescheduled tasks cancel cleanly.
  Tap → deep link opens the TASKS tab. Legacy tasks without `reminderAt` parse fine.
- **Evening reminder upgrades** (#9): notification now carries a `SNOOZE 30 MIN` action
  (one-shot at +30 min, id 2031) and `payload: shared_queue`; tapping opens TODAY and pops
  the SHARED QUEUE dialog (via `DeepLinks.sharedQueueRequests` + an invisible handler in
  `today_screen.dart`). Snooze from a background isolate is handled top-level, no plugins.
- **Home-screen widget** (#1): `home_widget` 0.10.0; native Kotlin
  `DayDeckWidgetReceiver : HomeWidgetProvider` + `daydeck_widget.xml` (open count, up to 4
  agenda lines, updated-stamp) backed by a `HomeWidgetPreferences` push from Flutter
  (`updateDayDeckWidget` — called on first frame + every store change). 30-min system
  refresh, 4×2 cells. Tap opens the app.
- **Share → DayDeck** (#2): MainActivity is now a real Kotlin class — ACTION_SEND text/plain
  intent-filter on the activity; text arrives as `{type:"share",text}` over the
  `daydeck/input` MethodChannel → creates a task (first 500 chars) + snackbar. Cold-start
  shares handled via `getInitialInput` (companion `pendingInput`).
- **One-tap capture routes** (#3 tile + #6 shortcuts): `DayDeckTileService : TileService`
  (BIND_QUICK_SETTINGS_TILE) → opens the app straight into the new-task sheet. Static
  shortcuts in `res/xml/shortcuts.xml`: "New task" / "Sync now". All three ride
  `ACTION_ADD_TASK`/`SYNC_NOW`/`OPEN_TODAY` with explicit component intents — NO new
  intent-filters, tile/shortcuts not exported beyond the component.
- **Search** (#4): `lib/screens/search_screen.dart`, opened from a search icon in Today's
  header. One query matches tasks (open+done), local events, the cached Google feed and
  habits (title/location/notes). Task hit → edit sheet; habit hit → toggle today; gcal hits
  marked read-only.
- **Sync conflicts viewer** (#5): Settings → SYNC CONFLICTS → CHECK reads `conflicts.json`
  (remote via Contents API + local pending queue, merged/deduped) → bottom sheet lists
  losers (doc, losing side, local time) with RESTORE-AS-NEW for tasks/events/habits
  (habit logs intentionally not restored — re-check the habit). Parked entries stay in
  the repo.
- **JSON backup export** (#11): Settings → BACKUP → EXPORT. `share_plus` 12 + `path_provider`;
  `daydeck-backup-YYYYMMDD.json` containing tasks/events/habits/habit_logs (no tokens/iCal
  URL — ever). Web falls back to sharing the JSON as text.
- **Weekly completion** (#12): dim line under Today's header — `this week · habits N% ·
  M tasks done` (habit % = checks this Mon–Sun / 7×daily-habits; tasks = done with
  updatedAt within 7 days).
- **Biometric app lock** (#8): `local_auth` 3.0.2; Settings → APP LOCK switch (Android only,
  biometric + device credential fallback, re-locks on resume after >30 s away, never traps
  the user when biometrics are unavailable). Widget tests unaffected (default off).
- **PWA polish** (#7): manifest gains `id` + `categories`, `color-scheme: dark` meta added;
  icons/maskable/standalone were already in place.
- main.dart keeps a `tasksStore.addListener → syncTaskReminders` reconcile (also covers
  sync merges arriving from the other device).
- **33/33 tests green (3 new for reminderAt); analyze clean; web build rebuilt (port 8090).**

### Kotlin/native gotchas (for the next session)
- `HomeWidgetProvider` (from the `home_widget` plugin) exposes `onUpdate(... , SharedPreferences)`;
  preferences live in `HomeWidgetPreferences`. `saveWidgetData` commits synchronously.
- BottomNavigationBar height-chain lesson from v0.7.0 still applies — widget/tile/shortcut
  code paths must stay intrinsic; TileService/shortcuts open the activity with
  `FLAG_ACTIVITY_NEW_TASK | CLEAR_TOP`.
- share/shortcut/tile inputs all funnel through MainActivity → `daydeck/input` channel
  (`nativeInput` callback + `getInitialInput` for cold starts) → single router in Shell.

## Phase 7 — Z Fold 5 inner-display layout — v0.7.0 (2026-11-10)

Owner uses the app on a **Galaxy Z Fold 5**; the inner 7.6" display was previously rendered
as a stretched phone column. Owner explicitly rejected a side-rail/drawer navigation
("not what I would call good use of the space"), so v0.7.0 is a **density** change, not a
navigation change. Bottom tab bar stays on every screen size.

- **Wide breakpoint**: `MediaQuery.sizeOf(context).width >= 700` (Fold cover ≈ 360dp, inner
  ≈ 800+dp; phone ≤ 450 unaffected). Content cap raised 640 → **1180dp** above the breakpoint.
- **Today**: calendar (flex 7) | tasks+habits (flex 6) two-pane row above 700dp; full-width
  status strip and header in both layouts; below 700dp the original single-column order is
  byte-identical.
- **Tasks**: header/stats full width; open tasks + ADD TASK (flex 7) | DONE column (flex 6);
  DONE panel shows a placeholder instead of vanishing when empty (wide only). Narrow unchanged.
- **Habits**: ≥ 700dp renders a two-column card grid (Wrap, computed card width =
  (w − 28 − 12) / 2) instead of one long list; narrow keeps the TerminalCard list.
- **Settings**: ≥ 700dp splits APPEARANCE+SYNC | EVENING REMINDER+CALENDAR+ABOUT into two
  columns; narrow unchanged. Any one-column-capable section stays untouched.
- **Bottom tab bar**: tab cluster capped at 640dp and centred on wide screens via
  LayoutBuilder + Padding (NOT Center — see gotcha below).
- **Testing gotcha (learned v0.7.0)**: `Center`/`Align` in a bottomNavigationBar's height
  chain EXPANDS to the loose max height, eating the entire body height (IndexedStack → 800×0;
  every screen rendered zero-height; flutter_test caught it as `findsOneWidget` failures).
  Fix: keep the height chain intrinsic (Row/Padding), never Align-class widgets.
- **Testing gotcha #2**: Rows/Columns with `CrossAxisAlignment.stretch` inside scrollables
  need `mainAxisSize: MainAxisSize.min` or intrinsic children — else "unbounded height"
  breaks the whole subtree silently (analyze stays clean).
- Widget tests still tap through the shell; **30/30 green; analyze clean.**
- Web build (`build/web`) rebuilt for v0.7.0 and served on port 8090 for quick review.

## Roadmap — additive features that do NOT bloat DayDeck (ranked by value/effort)

Rule: every item below REUSES existing machinery (tasks/habits/events stores, GitHub sync,
notification stack, iCal feed). Nothing here adds an account, a server, or a social graph.

| # | Feature | Effort | What / why |
|---|---|---|---|
| 1 | **Home-screen widget (Android)** | M | Agenda + open-count + habit quick-check on the cover display. Biggest win for a foldable: at-a-glance without opening. Reuses stores + a couple of quick SQLite reads. |
| 2 | **Share → DayDeck quick capture** (ACTION_SEND) | S–M | Share text/URL from any app → creates a task with the text as title (+ link in notes). One intent-filter; huge capture speedup. |
| 3 | **Quick Settings tile** ("Add task") | S | TileService → one-tap dialog-less capture or jump to the add sheet. Nice for between-meetings capture. |
| 4 | **Search across tasks/events/habits** | S–M | One query box on Today (or a ⌘K-style palette); filters lists client-side; no indexing infra needed. |
| 5 | **Conflict viewer in Settings** | S | `conflicts.json` losers are currently invisible — surface them read-only with a "restore as new task/event" action. Reuses existing conflicts.json. |
| 6 | **App shortcuts (long-press icon)** | S | "New task", "Sync now", "Next event". Static shortcuts XML + intent handling. |
| 7 | **PWA / add-to-homescreen polish** | S | Manifest + theme-color + splash for the web build; one-tap install UX parity with the APK. |
| 8 | **Biometric lock (optional)** | S–M | `local_auth`, off by default; gate app open/resume, not individual screens. App lock for a screen that shows your calendar. |
| 9 | **Evening reminder upgrades** | S | Snooze action on the notification + tap-to-open SHARED-queue (writes intent→tab+dialog). Complements Phase 4–6. |
| 10 | **AMOLED palette + per-scheme tweaks** | S | True-black scheme for the fold panel; reuses palette system. |
| 11 | **One-tap JSON export / share backup** | S | Settings → export tasks/events/habits as a JSON share intent. Cheap disaster-recovery for the data repo. |
| 12 | **Weekly completion % on Today** | S | X% of habits + tasks done this week from existing logs — pure derived metric. |

**Deliberately rejected (bloat):** social/sharing of tasks, cloud AI summaries, multiple
accounts/calendars, gcal write-back sync loops, in-app browser, avatars/gamification,
per-habit notifications, dark-mode scheduling. Each adds ongoing complexity or permissions
for zero daily value to a single-user dashboard.

**Suggested order:** 2 → 3 → 1 → 4 → 5 (capture loop first, then visibility), rest on demand.

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
4. ~~Phase 3~~ shipped v0.3.0. ~~Phases 4–6~~ shipped v0.6.0 (see Phase 4–6 log).
   Owner to: (a) enter sync token in Settings (already done? then nothing), (b) create the app
   sync token if not yet, (c) paste the secret iCal URL in Settings → CALENDAR (in-app guide),
   (d) on the web build: add repo secret ICAL_URL in dashboard-data (guide in Settings), then run
   “refresh-calendar” once manually, (e) test phone↔web with tasks/events/habits.
