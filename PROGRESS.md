# Planner: implementation progress

The single handoff document for this build. Anyone picking the work up in a
new session should read this file first, then `planner-final-handoff/README.md`
(the product spec, the source of truth) and `planner-final-handoff/prototype-logic.js`
(the exact prototype logic). Everything decided so far is recorded here, so
nothing needs to be re-derived.

Last updated: 30 September 2026, day 2 (milestones 1 to 6, 8 and 9 done; milestone 7 done except the real spotter and the live-mic check).

---

## 1. How to resume

1. Read this file, then README sections 6.3 onward for whatever milestone is next (section 4 below).
2. Keep the **core rule**: the repository writes state first; animations only explain it. UI staging maps (`place`, `hold`, `leaving`, `sweeping`, `fresh`) never gate data.
3. Work one milestone at a time. After each: `flutter analyze` (must be clean) and `flutter test` (must be green), check on a device, then commit.
4. Follow the git rules in section 9 exactly (author, no AI attribution, push target).
5. Update this file at the end of every session: status table, backlog, decisions.

Quick start:

```bash
cd planner_app
flutter pub get
flutter analyze
flutter test
flutter run -d <device> --dart-define=PLANNER_SCENARIO=tue
```

`PLANNER_SCENARIO` (debug only) loads one of the prototype's journey steps and pins the clock:
`onboard`, `tue` (Tue 19:40, first evening), `wed` (Wed 21:40, mid-study), `missed` (Wed 23:05),
`week` (Thu, plan the week), `sunday` (Sun 21:00, review), `settings`.
The same steps, plus clock +30 min / 60× / real time, theme, motion, network, demo voice line,
mic allowed/denied and live mic, are in **Settings › Developer** (debug builds only).

While `flutter run` is running in the background, `kill -USR1 <pid>` hot reloads and
`kill -USR2 <pid>` hot restarts (find the pid with `pgrep -f "flutter_tools.snapshot run"`).

---

## 2. Environment

| Item | Value |
|---|---|
| Flutter | 3.44.8 stable (Dart 3.12.2), via fvm default |
| Machine | Intel Mac (x86_64), macOS 26.6 |
| Android phone | Motorola edge 50 pro, Android 16 (API 36), id `ZD222MDN6H`. Screenshots: `adb -s ZD222MDN6H exec-out screencap -p > shot.png`; taps: `adb shell input tap X Y` (physical px, 1220 × 2712, density 450). |
| iOS simulator | iPhone 17 (iOS 26.5), used for all visual checks so far |
| Android emulator | `Medium_Phone` AVD uses an Android 37.2 **beta** 16KB-page x86_64 image and hangs at boot on this Intel Mac. Not usable. Installing a stable image (for example API 35 google_apis x86_64, about 1.5 GB) would fix it; not done. |
| Other | A physical iPad ("Pranay's iPad") is connected to this Mac. It is not ours; never deploy to it. |

Key packages (see `planner_app/pubspec.yaml` for exact versions): `flutter_riverpod` 3.4,
`go_router` 17.5, `drift` 2.35 + `drift_flutter` (sqlite3 3.x via build hooks; the old
`sqlite3_flutter_libs` is end-of-life and not used), `speech_to_text` 7.5, `permission_handler` 13,
`path_provider`, `intl`. Dev: `drift_dev`, `build_runner`, `mocktail`.

Regenerate Drift code after editing tables: `dart run build_runner build`.

---

## 3. Repository layout

```
PROGRESS.md                    this file
planner-final-handoff/         the design handoff (spec, prototype logic, HTML boards). Reference only.
planner_app/
  assets/fonts/                Geist, Geist Mono, Bricolage Grotesque (variable TTFs + OFL licences)
  lib/
    main.dart                  opens Drift, loads data before runApp, optional debug scenario
    app/
      app.dart                 MaterialApp.router, theme mode, MotionPrefs, text scale clamp 1.3
      router.dart              go_router StatefulShellRoute: /today /plan /progress /settings
      shell.dart               phone shell: panes, BottomNav, SheetHost, VoiceOverlay, orb layer, NoteStrip
      theme/                   PlannerColors (ThemeExtension), CategoryStyle, PlannerMotion, PlannerType
      state/
        store.dart             PlannerStore: writes to the repository first, then updates state
        clock.dart             clockProvider (1s tick, debug pin/speed), today/now providers
        derived.dart           routine/tasks/settings, effective+visible tasks, dayLayout(day), capacity(day)
        staging.dart           UI-only staging maps (place, hold, leaving, sweeping, fresh, scan, acks)
        actions.dart           every user action: commit, then stage visuals, then note with Undo
        note.dart              NoteStrip controller (3.6s, 5.2s with an action)
        sequencer.dart         cancellable timers for choreography
        ui_state.dart          Today UI, Plan UI, current tab, sheet state, platform motion, online
      dev/                     scenarios.dart, dev_panel.dart, foundations_page.dart (debug tools)
    domain/                    pure Dart, no Flutter imports
      time.dart                epoch days (weekday0: Mon = 0), fmt/dur/labels, stableSorted
      category.dart            Category enum, guessCat
      routine.dart             DayRule, Commitment, Routine (+ JSON)
      task.dart                Task, Deadline, Series (+ JSON)
      base_day.dart            baseItems (TimelineItem, ItemKind)
      layout.dart              buildDay, rowHeight, nowY
      capacity.dart            capOf, learned weekend cap, over-capacity copy
      scheduler.dart           busyOf, earliestFree, findSlot, snapDrop, ripple, placeMany, Move one,
                               reschedule options, preview slot, fit in, reschedule unfinished, complete
      series.dart              materializeSeries (28-day horizon), endSeries
      intents.dart             voice grammar (parseUtterance) and resolver (resolveIntent)
      onboarding.dart          OnboardingDraft (ranges, cascade, ruler snap, steps), rhythmCopy
      progress.dart            weekProgress aggregates, heat levels, best window, review and Progress copy
    data/
      database.dart            Drift tables: tasks, deadlines, series, kv (routine, settings, meta)
      repository.dart          PlannerRepository, DriftPlannerRepository, MemoryPlannerRepository (tests)
      planner_data.dart        PlannerData snapshot
      settings.dart            Settings (theme, motion, today view, notifications, voice, backup, data)
    features/
      today/                   today_model, today_header, timeline_strip, dial_view, today_page
      tasks/                   task_form, task_sheet, detail_sheet, decision_sheet
      plan/                    plan_board (WeekBoard), plan_page, upcoming
      voice/                   orb_painter (drawOrb port), planner_orb, speech, voice_controller, voice_overlay,
                               wake_word (WakeWordEngine interface, foreground gate, WakeWordHost)
      onboarding/              onboarding_page (steps, assembly, exit), onboarding_widgets (segments,
                               readout, ruler, 24h bar, commitment rows, Add your own, assembly rows)
      progress/                progress_page, ribbon (CategoryRibbon painter + geometry lerp), heatmap
                               (FocusHeatmap), review_page (six-stage weekly review, route /review)
      settings/                Routine section with Edit routine (live) + developer panel; rest is milestone 10
    widgets/                   controls (Pressable, pills, chips, switch, segmented), task_block,
                               capacity_meter, bottom_nav, note_strip, planner_sheet, surfaces, icons
  test/
    flutter_test_config.dart   loads the real fonts so widget tests measure text like the device
    domain/                    scheduler, series, intents tests (README numbers)
    app/                       harness + today, sheets, plan, missed, voice, theme tests
```

---

## 4. Milestone status (README section 11 build order)

| # | Milestone | Status | Verified |
|---|---|---|---|
| 1 | Tokens and theme | **Done** | Tests (contrast, tints, reduced motion). Fonts render on iPhone simulator. |
| 2 | Domain: baseItems, buildDay, capOf, findSlot, earliestFree, ripple, guessCat | **Done** | 39 domain tests with the README numbers (section 6). |
| 3 | Today strip: TaskBlock, NowIndicator, CapacityMeter, completion incl. done early, Dial | **Done** | Widget tests; iPhone simulator light and dark. |
| 4 | TaskSheet and the placement sequence (plus DetailSheet) | **Done** | Widget tests; simulator (sheet, preview, placement window and scan). |
| 5 | Plan board: three zooms, drag with ripple, scan, Upcoming | **Done** | Widget tests incl. a real long-press drag; simulator drag. |
| 6 | Missed flow: DecisionSheet with hold and fly | **Done** | Widget tests; simulator. |
| 7 | Voice: overlay, orb, STT, intents, wake word | **Done except two items** | Grammar: 13 tests. Flow: 4 widget tests with the demo voice. Wake word: gating, `WakeWordEngine` interface, debug "Say Hey Planner" and orb hover are done (2 widget tests with a fake spotter). **Open:** a real spotter (needs a key, section 10) and the first run on the Motorola with the real microphone (the phone was not connected on day 2). |
| 8 | Onboarding with assembly | **Done** | 14 domain tests (ranges, cascade, ruler, steps, 3h 10m / 6h copy, routine reflow) and 4 widget tests (first launch end to end, ruler and no fixed hours, Add your own, Edit routine). iPhone simulator. |
| 9 | Progress (ribbon, heatmap) and weekly review | **Done** | 8 domain tests (Sunday and Wednesday scenarios, heat, carried, copy) and 4 widget tests (empty state, day select and With work, all six review stages with keys and Plan next week, closing). Motorola and iPhone simulator. |
| 10 | Settings, Drive, offline; tablet and desktop; accessibility and reduced-motion pass | **In progress**: 10a Settings + notifications + export/delete done; 10b Drive (stand-in client) + offline done; 10c responsive + keyboard and 10d accessibility pass to do | 10a/10b: 4 domain/data suites (notifications, snapshot, sync) and 4 Settings widget tests; Settings and Export checked on the Motorola. |

Test count on day 2: 115 passing (`flutter test`), analyzer clean. **First Android run done on the Motorola** (Today, Progress, Settings render correctly).

---

## 5. Architecture (as built)

- **State:** Riverpod 3. `PlannerStore` (a `Notifier<PlannerData>`) is the only source of truth. Data is loaded from Drift before `runApp` and passed in via `initialDataProvider`, so the store is synchronous from the first frame. Every mutation awaits the repository write, then updates state; a failed write leaves state unchanged and the note offers "Not saved, tap to retry".
- **Derived, never stored:** timeline items, capacity, missed status, week load. `dayLayoutProvider(day)` and `capacityProvider(day)` are families over `effectiveTasksProvider` (holds applied) and `visibleTasksProvider` (hidden/staged removed, so capacity updates as each block lands).
- **Staging:** `stagingProvider` holds UI-only maps. `actions.dart` sets staging *before* a commit only where needed to avoid a one-frame flash (placement "hidden", sweep "pre"); it never delays a commit.
- **Choreography:** `Sequencer` timers scaled by the motion factor (`M` = 1, or 0.05 reduced; placement uses 0.1, voice 0.35, as in the prototype).
- **Routing:** go_router `StatefulShellRoute` with a custom `PaneSwitcher` (panes slide ±24%, fade and blur; Settings pushes in from the right with the nav visible). Sheets and voice are overlays in the shell, not routes.
- **Persistence:** Drift with typed columns for tasks, deadlines and series; routine, settings and meta as JSON in a key-value table. Tests use `MemoryPlannerRepository`.
- **Days:** epoch-day integers on the local calendar; `weekday0(day) = (day + 3) % 7` gives Monday = 0, matching the prototype's `d % 7`. Minutes are minutes from midnight.
- **Sorting:** JavaScript's sort is stable and Dart's is not; `stableSorted` is used wherever the prototype depends on tie order.

---

## 6. Numbers verified against the README

All in `test/domain/scheduler_test.dart` and `test/app/*`:

- New user weekday realistic evening **3h 10m** (available 5h, protected 1h 30m, buffer 20m). Weekends capped at 6h.
- Tue 19:40 empty evening: "20:00 → 23:30 open".
- Three-task request: Wednesday tasks at **20:00, 22:15, 23:00**, a **22:00 break**, Flutter spills into wind-down; capacity **3h 45m planned vs 2h 55m realistic, 50m over**; "This is 50m more than fits before your wind-down."
- **Move Flutter** → Thu 20:00; the evening fits again.
- Wed 21:40 complete Study polity: end **21:40**, "Study polity done early. 20 min back in your evening.", odometer 1.
- Wed 23:05 Exercise missed; Decide › **This weekend = Sat 09:00** (Tomorrow 21:00, Later today disabled); Rescheduled +1; "Exercise moved to Sat 3 Oct, 09:00."
- Drag Revise polity notes to Sat 10:00: "**3 blocks made room. Saturday is now 2h 45m over what fits.**"
- Voice: all nine demo lines resolve with the prototype's labels and copy (for example "3h 45m planned, 2h 55m realistic.", "Starts Monday 5 October. It repeats until you stop it.").

---

## 7. Decisions and deviations (keep these)

1. **Project location and ids:** Flutter project `planner_app/` inside this repo; org `com.planner` (Android `com.planner.planner_app`, iOS `com.planner.plannerApp`); display name "Planner". Defaults from the brief; the user has not asked for others.
2. **Icons:** README suggests Phosphor. `phosphor_flutter` 2.1.0 (latest, May 2024) does not compile on Flutter 3.44 (`IconData` is now a final class). The eight icons the app needs are drawn from the prototype's own stroke paths in `widgets/icons.dart` (`PlannerIcon`, 1.5 stroke).
3. **Fonts:** Google Fonts only ships variable TTFs for these families. Each weight is declared in `pubspec.yaml` pointing at the same file (so Flutter never synthesises bold), and `PlannerType` sets the `wght` axis (and `opsz` for Bricolage) via `FontVariation`.
4. **Drift:** `drift_flutter` + sqlite3 3.x (native build hooks) instead of the end-of-life `sqlite3_flutter_libs`.
5. **Scheduling uses whole minutes:** actions pass the floor minute to the domain ("finished at 21:40" ends at 21:40; the prototype's fractional clock would give 21:45).
6. **Move one (Plan board):** the prototype always picked the longest block. README asks for the block that *best covers* the overflow, so it takes the shortest block at least as long as the overflow (else the longest), and prefers a target day that stays within its realistic time.
7. **Voice placement "in order":** each spoken task is placed after the previous one on the same day (README 5.4); identical results to the prototype for the demo lines.
8. **Plan my evening:** stops when realistic capacity would be exceeded (README), which the prototype did not check.
9. **Drag counts as a reschedule** when the day changes (movedCount +1), so Progress › Rescheduled reflects it.
10. **Repeats:** a series is materialised as real dated tasks with a `seriesId` on a rolling 28-day horizon (topped up at launch), so occurrences show on Today and the board and every scheduling path works unchanged. The prototype only listed series in Upcoming.
11. **Voice amplitude:** taken from `speech_to_text`'s sound-level stream instead of the `record` package, because Android cannot give the mic to two recorders at once.
12. **Unknown voice requests:** "Planner didn't catch a plan in that. Try "Add gym tomorrow for one hour."" (label NOT SURE). A bare word with no duration, day, time or add-phrase is not turned into a task.
13. **Placement announcement:** after the placement sequence the note says, for example, "Read placed at today, 20:00." (README 9 wants placements announced in the live region; the prototype had no note here).
14. **Orb above the veil, below sheets** (prototype z-order veil 20, orb 30, sheets 50, note 55), so the orb's tap target never steals taps from a sheet.
15. **TaskBlock tall/short** is decided from the laid-out height, not the target height, so blocks growing during placement never overflow.
16. **Debug tooling** (scenarios, developer panel, demo voice, clock pinning) exists only in debug builds (`kDebugMode`).
17. **Git author:** see section 9.
18. **Wake word gate:** armed only when Settings › Voice is on, Today is the current tab, the app is resumed, no sheet is open, nothing covers the shell (`shellCoveredProvider`, set by onboarding and later the review) and voice is idle. `WakeWordHost` starts and stops the engine on every change. Until a real spotter exists, `NoWakeWordEngine` is used and the HEY PLANNER caption shows only in debug builds.
19. **Onboarding commits at "Build my rhythm"** (routine, `onboarded`), not at "Open Today", so the assembly only explains saved state. New installs are no longer auto-marked onboarded; the router's initial location is `/onboarding` until they are.
20. **Edit routine refits the week:** the prototype only swapped the routine. Here `reflowForRoutine` moves every undone task from today on that has not started and now overlaps fixed or protected time (or sits before wake) to the earliest free start after it, like the ripple pass. Done, started and unscheduled tasks never move; a kept overflow may stay in wind-down. This backs up the copy "Planner rebuilt your week around it."
21. **Edit routine has a close button** (top right, "Close, keep the current routine"); the prototype had no way out. System back goes to the previous question, or closes at question 1 when editing.
22. **The assembly builds the first weekday on or after today** (the prototype always used its Tuesday), and the weekend copy uses the first Saturday. The 24h bar also draws the first weekday.
23. **compileSdk 37** in `android/app/build.gradle.kts`: `permission_handler_android` requires it (Flutter's default is 36; platform 37.0 is installed). targetSdk and minSdk still follow Flutter.
24. **Progress uses real data, not the prototype's mock week.** Completed time = finished tasks plus fixed time that has passed (Office, Dinner), from the install day. The dashed envelope = live tasks plus commitments for days up to today ("With work" adds Office). The heatmap counts only focused categories (Study, Build, Self) from actual start/end times; the best window is the 2h (4 cells) with the most focused minutes, and "N days out of M" counts days with any focus in it. The heat summary stays on "Your rhythm appears here…" until 3 days with Planner.
25. **Stats definitions:** planned = this week's tasks up to today, skipped ones only when Settings › Count skipped as missed is on; Rescheduled = tasks with movedCount > 0; Carried forward = still-missed tasks. The Review button shows on Sunday from 18:00. The week starts Monday (the Week starts on Monday setting is not honoured yet, milestone 10).
26. **Review copy is generated** from the aggregates (counts in words up to ten, "evenings/mornings/afternoons" from the best window, name lists "A, B and 2 more"), with empty variants ("A quiet week.", "Nothing moved.", "Your rhythm is still forming."). Plan next week goes to Plan › Upcoming with "Next week starts with 1 carried-forward task and 2 deadlines."
27. **Android speech (from the first live-mic run):** `pauseFor` 3s and `ListenMode.dictation` (1.6s cut people off: the timer starts before the recogniser warms up), `listenFor` 30s, and a 500ms grace after "not listening" so the final result, not the last partial, is used. Debug builds log `[speech]` partials, finals and the dB range per session (`flutter run` output). Levels on the Motorola span −2…10 dB, the full mapped range.
28. **Grammar additions from real speech:** a leading "Hey Planner" is stripped; "in/after N minutes/hours (from now)" is a start relative to now, today (never a duration); "Remind me to …" without a length is a 15-minute block.
29. **App icon** is generated by `tool/make_icons.py` from `assets/icon/source.jpg` (the running ninja): iOS and macOS catalogues, Android legacy + adaptive (black background, safe-zone foreground, themed monochrome silhouette), web. Re-run the script after changing the source.
30. **Notifications** (`domain/notifications.dart`, pure): next task 5 min before each start in the next 7 days (max 40); missed = one check-in per day, 15 min after that day's last open task ends (completing tasks re-plans it away), never one per task; weekly review Sunday 21:00. Scheduled with `flutter_local_notifications` using **inexact** alarms (no exact-alarm permission, so times can drift a few minutes in doze). Re-planned on every change and on resume; nothing is scheduled while a debug clock is pinned. Permission is asked once, just after onboarding (Settings shows "Notifications are off for Planner" + Allow otherwise). Android needs core library desugaring (set in `build.gradle.kts`).
31. **Export as JSON** writes `planner-YYYY-MM-DD.json` (the same `PlannerSnapshot` as Drive) and opens the share sheet (Files, Downloads, Drive…); the note only shows when a target was chosen. **Delete all data** needs a second tap within 4 s and returns to onboarding.
32. **Drive runs on a stand-in client** (`FakeDriveClient`, in memory) until the Google Cloud OAuth client ids exist (section 10). `DriveClient` is the seam: a real `google_sign_in` + `googleapis` (drive.appdata) implementation overrides `driveClientProvider` in `main.dart`. Sync rules: before every upload Drive is read; **conflict** = Drive newer than the last sync and local changes (compare cards, Keep this phone / Use the Drive version, the loser kept as `planner-backup-<timestamp>.json`); Drive newer and no local changes = take Drive's version with a note; restore always saves the current plan as a separate backup first. Edits made during an upload keep `changedSinceSync`. The connected account and last sync live in meta (`driveAccount`, `lastSyncAt`).
33. **Automatic backup** has no background job: it runs on launch, resume and reconnect when connected, on Wi-Fi, with local changes, and at least 20 h after the last one ("Every night, on Wi-Fi" as closely as a foreground-only app can).
34. **Offline** comes from `connectivity_plus` (network type, not reachability). Nothing becomes read-only; the LOCAL chip, the Drive row ("Offline, waiting to back up") and the cloud-with-slash glyph are the only signals. The Today header also shows SYNCING while busy and NEEDS A DECISION on a conflict (tap: Settings › Google Drive). Debug: Settings › Developer › "Simulate a Drive conflict".

---

## 8. Backlog (what is left, in order)

### Milestone 7 (finish)
- Live microphone on the Motorola works (permission, partial and final transcripts, intents). Still to judge by eye: whether the orb looks flat or clipped with the −2…10 dB → 0..1 mapping, and haptics.
- Real wake word: implement `WakeWordEngine` (for example Porcupine with a custom "Hey Planner" keyword) and override `wakeWordEngineProvider` in `main.dart`. Gating, the host widget and tests already exist. **Needs a decision and a key from the user** (section 10).

### Milestone 10
- **Real Google Drive client** (the only Drive piece left): implement `DriveClient` with `google_sign_in` + `googleapis` Drive v3 `appDataFolder` and override `driveClientProvider` in `main.dart`. **Needs from the user: Google Cloud OAuth client ids** (Android SHA-1 + package, iOS client id and reversed client id URL scheme).
- "Week starts on" is shown as Monday but not yet selectable (Progress and the board assume Monday).
- **Tablet (600–1023) and desktop (≥ 1024)** (README 8): left rail / sidebar, Today pane or rail beside the Plan board (`PlanPage(allExpanded: true)` for desktop is already supported by `PlanBoard`), keyboard shortcuts (N, V, T, ← →, Enter, Space, Alt ↑↓, Alt ←→, Ctrl/⌘ Z, ?).
- **Accessibility and reduced-motion pass** (README 9 and 3.5): audit semantics labels against the Components board, focus order, 1.3× text scale on every screen, reduced motion everywhere (orb frozen, no ripples or pulse, blur off, placement in place).

### Also outstanding
- Acceptance test from README 11 as one `integration_test` (onboard → voice → Move Flutter → complete early → missed → weekend → review).
- Loading skeleton state for TaskBlock (only matters if data ever loads after the first frame; today it does not).
- Hover states on desktop for blocks (+5% lift).
- Android emulator: install a stable system image if an emulator is wanted.

---

## 9. Git and collaboration rules

- Repository: https://github.com/siddheshpawarcodes/planner (remote `origin`, branch `main`).
- Every commit is authored and committed as **Siddhesh Pawar <205728342+siddheshpawarcodes@users.noreply.github.com>** (set in this repo's local git config). He is the only collaborator shown.
- **No AI attribution anywhere**: no `Co-Authored-By` trailers, no tool names in commit messages, pull requests, code comments or docs.
- One commit per milestone (or clear sub-part), message "Milestone N: …" with a short body of what changed.
- **Never push with a WindowMaker GitHub account.** This Mac's system git config uses the macOS Keychain helper (`osxkeychain`), which may hold a work account. Always push with the helper disabled so only Siddhesh's own credentials can be used, for example:
  `git -c credential.helper= push origin main` (then authenticate as siddheshpawarcodes when asked, with his own personal access token), or `gh auth login` as siddheshpawarcodes and `git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main`.
- There is no GitHub CLI on this machine. Never put a token in the remote URL.
- Never rewrite history that is already on `origin`.

---

## 10. Decisions still needed from the user

1. **Google Cloud OAuth client IDs** for Drive backup (milestone 10).
2. **Wake word provider and key** (Porcupine AccessKey plus a trained "Hey Planner" keyword, or another choice).
3. App name and bundle id are the defaults (Planner, `com.planner.planner_app`); confirm or supply others before any store build.
