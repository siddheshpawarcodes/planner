# Planner: implementation progress

The single handoff document for this build. Anyone picking the work up in a
new session should read this file first, then `planner-final-handoff/README.md`
(the product spec, the source of truth) and `planner-final-handoff/prototype-logic.js`
(the exact prototype logic). Everything decided so far is recorded here, so
nothing needs to be re-derived.

Last updated: 29 September 2026, end of day 1 (milestones 1 to 6 done, milestone 7 mostly done).

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
| Android phone | Motorola edge 50 pro, Android 16 (API 36), id `ZD222MDN6H` |
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
    data/
      database.dart            Drift tables: tasks, deadlines, series, kv (routine, settings, meta)
      repository.dart          PlannerRepository, DriftPlannerRepository, MemoryPlannerRepository (tests)
      planner_data.dart        PlannerData snapshot
      settings.dart            Settings (theme, motion, today view, notifications, voice, backup, data)
    features/
      today/                   today_model, today_header, timeline_strip, dial_view, today_page
      tasks/                   task_form, task_sheet, detail_sheet, decision_sheet
      plan/                    plan_board (WeekBoard), plan_page, upcoming
      voice/                   orb_painter (drawOrb port), planner_orb, speech, voice_controller, voice_overlay
      progress/                placeholder (milestone 9)
      settings/                placeholder page holding the developer panel (milestone 10)
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
| 7 | Voice: overlay, orb, STT, intents, wake word | **Mostly done** | Grammar: 13 tests (all nine demo lines). Flow: 4 widget tests end to end with the demo voice. Not yet run on Android: the first Motorola build (`flutter run -d ZD222MDN6H`) was stopped before it finished, so nothing has been verified on a real Android device yet, including the real microphone. Wake word not done (needs a key). |
| 8 | Onboarding with assembly | Not started | |
| 9 | Progress (ribbon, heatmap) and weekly review | Not started (placeholder page) | |
| 10 | Settings, Drive, offline; tablet and desktop; accessibility and reduced-motion pass | Not started (dev panel only) | |

Test count at end of day 1: 83 passing (`flutter test`), analyzer clean.

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

---

## 8. Backlog (what is left, in order)

### Milestone 7 (finish)
- Run on the Motorola with the real microphone: permission prompt, partial transcript, sound level driving the orb, final result → intent. Tune `DeviceSpeech` level mapping (−2…10 dB → 0..1) if the orb looks flat or clipped.
- Wake word "Hey Planner": foreground only (Today visible, app resumed, no sheet, review or settings, voice idle; stop on pause or route change). **Needs a decision from the user**: Porcupine (Picovoice) access key and a custom "Hey Planner" keyword file, or another on-device spotter. Build a `WakeWordEngine` interface with gating now; until a key exists, show the HEY PLANNER caption only in debug and keep tap-to-talk.
- Debug "Say Hey Planner" button in the developer panel that respects the same gating (note: "“Hey Planner” works only while Today is open on screen.").
- Orb hover state on desktop and web (amp .16).
- First Android run on the Motorola: `flutter run -d ZD222MDN6H --dart-define=PLANNER_SCENARIO=tue` (the first Gradle build is slow on this Mac; let it finish), then check layout, haptics and voice.

### Milestone 8: Onboarding (README 6.1)
Five questions with progress segments, time input (Geist 300 88 readout, −/+ 15 buttons, draggable ruler 2 px/min with 15-min ticks and 5-min snap, live region), the live 24h bar, commitments with Add your own, assembly (items rise 14px on Spring, 240ms apart) and "Your rhythm is ready." with the realistic-time copy, then the Settle transition to Today. Route `/onboarding` outside the shell; first launch goes there (currently `main.dart` marks new installs onboarded with the default routine). "Edit routine" in Settings re-runs it prefilled and ends with "Routine updated. Planner rebuilt your week around it." Prototype reference: `obKey`, `obRange`, `obSet`, ruler handlers, `obNext`, `openApp`, `editRoutine`, `cuAdd` in `prototype-logic.js`.

### Milestone 9: Progress and weekly review (README 6.8, 6.9)
Pure aggregates in `domain/progress.dart` (per-category completed hours per day, planned envelope, stats, heatmap from actual completion times, best window). CategoryRibbon CustomPainter (streamgraph, horizontal-tangent cubics, 1px bg separators, dashed envelope, left-to-right clip reveal 1400), day cursor and breakdown, count-up 1500 ease-out cubic, three stats, the moved cells, FocusHeatmap (7 × 36, 0/.18/.36/.62/1, diagonal 11ms stagger, bracket on the best window), Review button on Sunday evening. Weekly review: six staged screens with tap left/right, arrow keys, progress segments, the copy in README 6.9, "Plan next week" → Plan › Upcoming. Prototype reference: `WMOCK`, `WENV`, `HEATF`, the progress and review parts of `renderVals`.

### Milestone 10
- **Settings** (README 6.10): push page with every section and row; Edit routine; notifications (flutter_local_notifications: next task 5 min before, one missed check-in, Sunday 21:00 review); voice switch and mic status; appearance (theme, motion, Today opens as); data (week start, count skipped as missed, Export JSON, Delete all data on a second tap); About copy.
- **Google Drive** (README 6.11): `drive.appdata` scope, single `planner-backup.json` snapshot (schemaVersion, exportedAt, deviceId, routine, tasks, series, deadlines, settings) plus `planner-backup-<timestamp>.json` for kept losers; states Not connected, Connecting, Synced, Backing up / Restoring with %, Offline, Conflict (compare cards), Restore confirmation. Conflict = remote exportedAt newer than the last local sync and local changes since then; no silent merge. `PlannerData.changedSinceSync` and `lastSyncAt` already exist. **Needs from the user: Google Cloud OAuth client IDs** (Android SHA-1 + package, iOS client and reversed client id). Until then, build every state against a fake Drive client.
- **Offline** (README 6.12): `connectivity_plus` into `onlineProvider` (currently a debug toggle); LOCAL chip already on Today; Drive row "Offline, waiting to back up".
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
