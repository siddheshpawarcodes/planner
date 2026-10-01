# Planner: implementation progress

The single handoff document for this build. Anyone picking the work up in a
new session should read this file first, then `planner-final-handoff/README.md`
(the product spec, the source of truth) and `planner-final-handoff/prototype-logic.js`
(the exact prototype logic). Everything decided so far is recorded here, so
nothing needs to be re-derived.

Last updated: 1 October 2026, day 3. All ten milestones, the README 11 acceptance test, full-screen customisable alarms and a free Vosk "Hey Planner" are built; what remains is on-device verification (see "Start here").

---

## 0. Start here (state on day 3)

**Code:** everything is committed on `main` (181 tests passing plus the device acceptance test, analyzer clean). The last commits may not be on GitHub yet: run `git log --oneline origin/main..HEAD`; anything listed needs `git -c credential.helper= push origin main` (the user signs in as siddheshpawarcodes with a personal access token, see section 9).

**Waiting on the user:**
1. **"Hey Planner" is now Vosk** (1 Oct; Porcupine removed, see decision 50). Built and unit-tested. **On the Motorola (1 Oct, 12:36):** the bundled model unpacked and loaded (`VoskWake: model ready`), it listened on Today, stopped when another app came to the front and re-armed when Planner returned. **Spoken tests (1 Oct, 14:09-14:23):** with the first rule (exact "hey planner" only, near-miss decoys) the user had to say it 3-4 times: logged alternatives showed their "hey planner" landing on "hey plan", "hey planet", "planner" or "a planner", often with "hey planner" a close second. After re-tuning (decision 50) it woke on 8 of 9 tries (the miss heard only "hey"). **Requests after a wake:** now forwarded to the on-device recogniser with no gap (decision 51); short words in the user's accent are still misheard. **To run next:** Settings › Developer › Probe recogniser (Indian-English clips from the Mac's Rishi voice are in `files/probe/` on the phone; it compares biasing off/on and `en-IN`, results as `[probe]` lines in the `flutter run` log). Background talk nearby can also wake it and fill a request. Next time: `flutter run -d ZD222MDN6H` (no dart-defines any more), open Today, and say "Hey Planner"; watch logcat for `VoskWake` (`model ready`, `listening`, `wake: "..."`) and the `[wake]` lines in the `flutter run` log. The first arm copies the model to app storage (a few seconds). Also try near-misses ("hey planet", "okay planner") and normal talk; neither should wake it. On a fresh clone run `planner_app/tool/fetch_vosk_model.sh` before building for Android.
2. **iOS OAuth client for Drive:** deferred by the user; do not block on it.

**Full-screen alarms (built 1 Oct, verified on the Motorola):** in-app ring; Snooze (rang 10 min later); slide to Done over the lock screen (returned to the lock screen); a ring with Planner's process killed (cold start, Aurora and the slide track drawn correctly on the current build); a chosen phone tone (Helium, copied to `files/alarm_tones/`, played by the service); the 15 s gentle start (volume rose 0 → 1 in steps over 15 s); Start now, unlocked and after a cold start (sound stops, Planner stays on Today). The quiet-banner swap: verified (a burst of screenshots across an in-app ring shows no heads-up; the notification sits on `planner_alarm_quiet`). **Still to check:** Start now with the lock screen up (it should ask to unlock), and a photo and a video background (the user picks them: the picker shows their gallery). The user's choices on 1 Oct: Full screen, Aurora, slide to confirm, 15 s gentle start, Helium.
**Heads-up banner over the alarm screen:** the plugin's notification channel is IMPORTANCE_HIGH (needed for the full-screen intent), so Android adds a heads-up banner while the phone is in use. Once Planner's screen shows an alarm, `AlarmHost` calls `quietBanner`: `MainActivity` re-posts the notification under the same id (still the service's foreground notification) on channel `planner_alarm_quiet` (IMPORTANCE_LOW, silent), which takes the banner down; Stop and tap-to-open remain in the shade. On the Motorola no banner showed at all in a burst of screenshots across the ring.

**To verify on the Motorola next time it is plugged in** (`adb devices` shows `ZD222MDN6H`):
- **Google Drive (real, Android):** Settings › Backup › Google Drive › Connect. Expect Google's account picker and consent, then "Backed up just now". If it fails, read `[drive]` lines in the `flutter run` log. Cloud-side prerequisites: Drive API enabled; the account is a test user while the consent screen is in Testing; Android OAuth client = `com.planner.planner_app` + SHA-1 `EE:51:6E:0B:9D:5D:4A:A2:94:AF:95:6F:FD:33:D1:6C:77:B9:2B:2D` (this Mac's debug keystore; verified matching).
- ~~Task alarms~~ **verified on the Motorola, 1 Oct:** with notifications and "Alarms & reminders" granted, every task gets an exact alarm-clock alarm (Android's next alarm clock showed Study polity at 20:00, its reminder at 19:55). Completing Study polity removed its alarm from `dumpsys alarm`; un-completing it brought it back. Settings › Developer › "Test alarm in 1 minute" rang on time: channel `planner_alarm`, category alarm, flags INSISTENT, playing on USAGE_ALARM, shown as a heads-up. Note: the phone's alarm volume was 1 of 7 (the user's setting, left alone), and Bedtime mode allows alarms. A task can't be placed a few minutes ahead during office hours (by design), hence the debug alarm. Swiping the heads-up up only moves it to the shade; it keeps ringing until swiped away there or tapped.
- **Notifications (granted on the Motorola, 1 Oct):** the permission prompt appears once, after onboarding (Settings › Delete all data re-runs onboarding on a device with demo data). **Fixed on 1 Oct:** before that the prompt never showed (it was read through the unmounted onboarding page's `ref` and threw), which is why the Motorola still said "Notifications are off for Planner". On 1 Oct the user was asked to tap Allow for notifications and for "Alarms & reminders" themselves (permission grants are the user's); once granted, the task-alarm check below can run.
- Orb reaction to the real microphone (not flat or maxed out) and haptics.

**Device etiquette (precautions for driving the user's own phone):** check a screenshot before any adb tap; if another app, the notification shade or quick settings is open, stop and ask. Never touch system settings (Do Not Disturb was seen on; it was not changed by us). Don't repeat anything personal seen on screen. Screenshots: `adb -s ZD222MDN6H exec-out screencap -p > shot.png`.

**Builds on the phone:** the installed build runs on the real clock and keeps its data (built without `PLANNER_SCENARIO`). Builds made with `--dart-define=PLANNER_SCENARIO=…` reset to demo data on every launch.

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
      settings.dart            Settings (theme, motion, today view, notifications, alarms, voice, backup, data)
      snapshot.dart            PlannerSnapshot (the Export and Drive JSON document)
      backup/                  drive_client (interface + stand-in), google_drive_client (Drive v3 appData),
                               sync (SyncController state machine, conflict rule, status copy)
    features/
      alarm/                   alarm_engine (alarm plugin, alarmDiff), alarm_platform (planner/alarm channel),
                               alarm_screen, alarm_backgrounds (six looks, media, effects), alarm_host (/alarm),
                               alarm_customise_page (/alarm-look)
      today/                   today_model, today_header, timeline_strip, dial_view, today_page
      tasks/                   task_form, task_sheet, detail_sheet, decision_sheet
      plan/                    plan_board (WeekBoard), plan_page, upcoming
      voice/                   orb_painter (drawOrb port), planner_orb, speech, voice_controller, voice_overlay,
                               wake_word (WakeWordEngine interface, foreground gate, WakeWordHost),
                               vosk_engine ("Hey Planner" via VoskWake.kt, bundled model)
      keyboard/                shortcuts (KeyboardHost, "?" panel, ShortcutLegend)
      notifications/           notification_service (NotificationService, LocalNotifications, task alarms)
      offline/                 network (connectivity_plus → onlineProvider, auto-backup triggers)
      onboarding/              onboarding_page (steps, assembly, exit), onboarding_widgets (segments,
                               readout, ruler, 24h bar, commitment rows, Add your own, assembly rows)
      progress/                progress_page, ribbon (CategoryRibbon painter + geometry lerp), heatmap
                               (FocusHeatmap), review_page (six-stage weekly review, route /review)
      settings/                Routine section with Edit routine (live) + developer panel; rest is milestone 10
    widgets/                   side_nav (tablet rail, desktop sidebar), task_focus (keyboard blocks),
                               controls (Pressable, pills, chips, switch, segmented), task_block,
                               capacity_meter, bottom_nav, note_strip, planner_sheet, surfaces, icons
  test/
    flutter_test_config.dart   loads the real fonts so widget tests measure text like the device
    domain/                    scheduler, series, intents tests (README numbers)
    app/                       harness + today, sheets, plan, missed, voice, theme tests
                               journey.dart: the README 11 acceptance journey (acceptance_test.dart)
  integration_test/            acceptance_test.dart: the same journey on a device (run with -d macos)
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
| 7 | Voice: overlay, orb, STT, intents, wake word | **Done in code** | Grammar and flow tests; live microphone works on the Motorola (dictation mode, 3 s pause). "Hey Planner" now runs on Vosk (free, offline, decision 50): built and tested on this Mac and in unit tests; **first run on the phone pending** (section 0). |
| 8 | Onboarding with assembly | **Done** | 14 domain tests (ranges, cascade, ruler, steps, 3h 10m / 6h copy, routine reflow) and 4 widget tests (first launch end to end, ruler and no fixed hours, Add your own, Edit routine). iPhone simulator. |
| 9 | Progress (ribbon, heatmap) and weekly review | **Done** | 8 domain tests (Sunday and Wednesday scenarios, heat, carried, copy) and 4 widget tests (empty state, day select and With work, all six review stages with keys and Plan next week, closing). Motorola and iPhone simulator. |
| 10 | Settings, Drive, offline; tablet and desktop; accessibility and reduced-motion pass | **Done** except the real Google Drive client (needs OAuth ids): 10a Settings + notifications + export/delete, 10b Drive (stand-in client) + offline, 10c tablet/desktop + keyboard, 10d accessibility and reduced-motion pass | Notifications, snapshot, sync suites; Settings, layout/keyboard and accessibility widget tests (every screen at 1.3× with reduced motion; 44px targets, labels and contrast via Flutter's guidelines). Motorola (Settings, Export), iPhone and iPad simulators, desktop rendered at 1440 × 900. |

Test count on day 3: 181 passing (`flutter test`), analyzer clean; `flutter test integration_test -d macos` passes (about 1 min, real time). **First Android run done on the Motorola** (Today, Progress, Settings render correctly).

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
35. **Breakpoints are width plus platform:** phone < 600; tablet from 600; desktop from 1024 only on macOS, Windows, Linux or the web. The README table says tablet = 600-1023, but its own Tablet board is an iPad in landscape at 1194, so a wide iPad or Android tablet stays tablet. `PlannerLayout.of(context)` publishes the kind (set in `app.dart`).
36. **Wide layouts reuse the router's branch navigators** (no duplicated pages): `PaneSwitcher` puts the Today branch in the 380 pane (tablet, left) or 400 rail (desktop, right, with the key legend) and shows Plan on the other side when Today or Plan is selected, Progress or Settings otherwise. The Plan branch is `preload: true` so the board is there on first launch. Each pane is its own semantics container: a navigator's page route blocks semantics painted before it in the same container, which had hidden the rail and Today pane from screen readers.
37. **Keyboard:** `KeyboardHost` is a `Focus` at the shell root (no semantics node of its own), so focused blocks and sheets see keys first, text fields keep their letters (only Esc passes through, closing the sheet), and onboarding/review keep their own keys as separate routes. Keys: N, V, T, P (Plan), G (Progress), ← → (Today/Tomorrow on the phone, the board's day elsewhere, within the week), Esc, Ctrl/⌘ Z (the note's Undo), ? (panel). `TaskFocus` makes Today and board blocks focusable: Enter opens, Space completes, Alt ↑↓ ±15 min, Alt ←→ ±1 day (through the same ripple as a drag).
38. **macOS** builds with a deployment target of 11.0 (speech_to_text requires it).
39. **Accessibility pass (10d):** `test/app/a11y_test.dart` visits every screen at 1.3× text with reduced motion (any overflow fails) and runs Flutter's guidelines: 44 × 44 targets (README 3.4, not Android's 48), a label on every tap target, AA text contrast. Fixes it drove: segmented controls and short pills keep their look but get 44px hit areas (`minTarget`); duplicate unlabelled tap nodes removed (orb, ribbon days, review sides) with `excludeFromSemantics`; board block text lines and Progress day labels scale with the text size. **Exception:** the Plan board's time-proportional blocks (45 min = 18px) and 26px collapsed columns stay below 44px; they carry custom actions (Move earlier/later/to the next day), keyboard focus, and the same tasks at 44px+ on Today.
40. **Reduced motion:** blur and the now pulse were already off; placement now skips the staged introduction entirely (blocks appear in place).
41. **Google Drive on Android is real** (`data/backup/google_drive_client.dart`): Drive v3 `appDataFolder` with the `drive.appdata` and `userinfo.email` scopes, via `google_sign_in` 7 **authorization only** (no `authenticate()`, which on Android would need a web `serverClientId`). It relies on the Android OAuth client for `com.planner.planner_app` with SHA-1 `EE:51:6E:0B:9D:5D:4A:A2:94:AF:95:6F:FD:33:D1:6C:77:B9:2B:2D`, which matches this Mac's debug keystore (release builds are signed with it too for now; a Play release needs its own SHA-1s registered). The Google Cloud project needs the Drive API enabled, and while the consent screen is in Testing the account must be a test user. iOS: stand-in in debug, "not available yet" in release (user decision: no iOS OAuth client for now).
42. ~~**Wake word is Porcupine**~~ (replaced by Vosk, decision 50; kept for history) (`features/voice/porcupine_engine.dart`, behind `WakeWordEngine`). AccessKey: `--dart-define-from-file=config/secrets.json` (git-ignored; copy `config/secrets.example.json`). Keyword: `assets/wake/hey_planner_android.ppn` / `hey_planner_ios.ppn` (git-ignored). Without either, the wake phrase stays off and Settings says so. It arms only when the microphone is already allowed, stops before voice opens the mic, and re-arms 400 ms after voice closes. Porcupine's plugins declare compileSdk 31; the root `android/build.gradle.kts` lifts plugin libraries to 36.
43. **Week starts on Monday** (user decision, 30 Sep): the row stays fixed at Monday.
44. **Task alarms** (user request, 30 Sep): every upcoming task in the next 7 days (max 40) gets an alarm at its start, in addition to the 5-minute reminder; Settings › Notifications › Task alarms (default on). Android channel `planner_alarm`: alarm sound (`content://settings/system/alarm_alert`) on the alarm audio stream, FLAG_INSISTENT (repeats until dismissed). Scheduled with `AndroidScheduleMode.alarmClock` when `canScheduleExactNotifications()` is true (manifest declares `SCHEDULE_EXACT_ALARM`; the user grants "Alarms & reminders" from Settings' Allow row), otherwise inexact. There is no separate "delete on completion" code: `NotificationHost` cancels everything and schedules the current plan on every change, so done, skipped, deleted or moved tasks lose or move their alarm. No full-screen intent (it would need the app to show over the lock screen).
45. **Acceptance test** (README 11): `test/app/journey.dart` is one journey on one in-memory store and one fake clock, from Tuesday's onboarding (install day stamped as `main.dart` does) through the voice request, Move Flutter, done early, the missed Exercise, This weekend and the Sunday review (3 planned, 1 finished, 1h 40m focused, 2 rescheduled and carried, best hours 20:00 → 22:00). `test/app/acceptance_test.dart` runs it under `flutter test`; `integration_test/acceptance_test.dart` runs the same code on a device in real time. Run it on macOS (`flutter test integration_test -d macos`), not the user's phone: it never touches stored data, but installing a test build replaces the installed debug app. The review is opened through its button's own handler (`openReview`) because the button sits under the bottom nav at 860 px.
46. **"No room" names the chosen day:** with a day chosen in the TaskSheet the preview says "No room left today", "No room tomorrow" or "No room on Saturday"; only Planner picks says "No room in the next 7 days" (the prototype said that for every case, which read wrong when only today was searched).
47. **Debug test alarm:** Settings › Developer › "Test alarm in 1 minute" adds one alarm (id 3999) to `plannedNotesProvider`, since every re-plan cancels everything pending. Changes to providers need a hot restart (`kill -USR2`), not a hot reload: Riverpod providers that already exist keep their old code.
48. **Full-screen alarms** (user request, 1 Oct). Settings › Notifications › Alarm style: *Notification* (the `planner_alarm` channel, unchanged, the default) or *Full screen* (Android only; the rows are hidden where `alarmEngineProvider` is unavailable). Full screen uses the `alarm` plugin 5.13: exact `setExactAndAllowWhileIdle` alarms (not alarm-clock class, so no status-bar alarm icon), a foreground service that plays the tone on the alarm stream with optional fade-in and vibration, and a full-screen intent with the plugin's `RING` action on `MainActivity`. `MainActivity` (channel `planner/alarm`) shows over the lock screen and turns the screen on only for that launch (the plugin also toggles this while ringing), and after Done or Snooze clears it and `moveTaskToBack`, so the phone returns to the lock screen or the interrupted app; Start now asks to unlock first, then stays and opens the task. The alarm screen is the root route `/alarm` (system back is blocked, so the plan beneath is never reachable over the lock screen) driven by `AlarmHost` in the shell. Re-planning (`alarmDiff`): ids are stable per task (`alarmIdFor`, FNV-1a); alarms still ahead follow the plan exactly; alarms whose planned minute has passed (ringing or snoozed) are left alone unless their task is done or gone; nothing is set for a past time (the plugin would ring it at once; the cached plan can hold one). Changing tone, fade, vibrate or snooze re-sets every alarm. Snooze from Planner's screen = stop + set again at now + N min. The plugin's storage and Do Not Disturb permissions are removed from the manifest (`tools:node="remove"`); it brings `USE_EXACT_ALARM`, fine for an app with alarms, but a Play release needs the full-screen-intent declaration.
49. **Alarm look** (`data/alarm_prefs.dart`, inside Settings JSON so Export/Drive carry it): one shared `AlarmLook` plus optional per-category overrides; sound and answering are global. Backgrounds: six code-drawn animated looks (Orb, Aurora, Embers, Stars, Sunrise, Waves; still under reduced motion), a photo or GIF, a looping silent video (`video_player`), or the category colour. Effects: blur, dim, slow zoom (Ken Burns), tint (category or six colours) with strength. Text: clock size S-XL, font Bricolage/Geist/Mono, centred or left, task name, times, what's next, and a message (60 characters). Picked media and tones are copied into Planner's files (`alarm_media/`, `alarm_tones/`, unused copies pruned); a missing file falls back to the category colour (a restored backup on another phone keeps the look minus the media). Tones: the phone's alarm tones via RingtoneManager, previewed on the alarm stream; "Phone default" = the plugin's default. Customise alarm screen (`/alarm-look`) has a pinned live preview and **Ring a test** (10 s, in the edited category's look; `testAlarmProvider` now carries a category and is no longer debug-only).
50. **"Hey Planner" uses Vosk, free and offline** (user decision, 1 Oct: everything free of cost). Picovoice has no free or personal plan any more (its FAQ: only a one-time enterprise Free Trial; the AccessKey stops when it ends), so Porcupine, its plugins, `config/secrets.example.json` and `assets/wake/` are gone, along with the root Gradle lift to compileSdk 36 that only Porcupine needed. Vosk (`com.alphacephei:vosk-android:0.3.47` + JNA 5.13.0, Apache 2.0) runs in `android/.../VoskWake.kt` (channels `planner/wake`, `planner/wake/events`) with `vosk-model-small-en-us-0.15` bundled in `android/app/src/main/assets/vosk-model` (user choice: bundle, about 40 MB in the APK; git-ignored; `tool/fetch_vosk_model.sh` fetches it; `StorageService` copies it to app storage on first use, keyed by the `uuid` file). The recogniser is limited to a grammar of "hey planner" plus near words (hey planet/banner/plan/plant/plane/player, okay planner, a planner, the single words, `[unk]`) with `setMaxAlternatives(3)`. **Wake rule, tuned on the user's voice:** a partial wakes when an utterance starts with `(hey|a)? (planner|planet|plant|plan)`, and a final wakes when, in any of the top three alternatives scoring within 5% (at least 3) of the best, the whole utterance is `(hey|a)? (planner|planet|plant|plan|plan a|plan banner)`; at most once per 2 s. So "hey planet" or "hey plan" on their own now wake it (accepted trade-off), while sentences that merely contain "planner" ("I need a planner for the week"), "hey banner", "okay planner" and ordinary talk do not (checked on the Mac set and on the phone). Debug builds log every final's alternatives as `VoskWake: heard: …`. After a wake, `stripWakeResidue` drops a misheard tail of the phrase from the start of the request ("Hitler at gym…" → "add gym…"). Tested on this Mac with Python Vosk and macOS voices (Samantha, Daniel): every "hey planner" (alone or starting a request) woke it about 0.2 s after the phrase; no near-miss or ordinary sentence did, in partials or finals. Without decoys every near-miss woke it. The gate is unchanged (Today visible, resumed, voice idle, microphone already allowed). The Settings caption reads the engine's reason when it is off. **Release note:** Vosk 0.3.47's native libraries predate Google Play's 16 KB page-size requirement; check the alignment (or a newer Vosk build) before a Play release.
51. **Voice requests after a wake (1 Oct, iterated on the user's voice).** Vosk owns the microphone (`VoskWake.kt` records 16 kHz mono itself and keeps the audio since the last pause). On a wake the last 2.5 s plus the live audio go to the phone's **on-device** recogniser through Android 13's `EXTRA_AUDIO_SOURCE` (`OnDeviceRequest.kt`): no gap while a recogniser starts, Google-quality words, offline. Found on the Motorola: only the on-device recogniser accepts an audio source (the default one returns error 7); with one it dictates continuously (segments, no final result), so segments are joined (settled text arrives with a leading space; an empty settle keeps its live words) and 1.5 s of quiet ends the request (the wake phrase alone waits up to 8 s); audio pushed faster than real time is skipped, so a backlog goes in at about 2× speed; biasing strings (Planner's commands, days, times, common activities, and the user's task names sent from Dart at each start) are passed. Fallbacks: Vosk's unrestricted recogniser transcribes (no Android 13 / no on-device recogniser) and a lone wake hands the microphone to `speech_to_text`. Real launches use the live microphone; the demo voice is only for tests and PLANNER_SCENARIO builds. **Accuracy so far:** the start of the sentence now arrives, but the user's short words are still misheard ("add gym" → "adjint", "and g", "details"); next step is the probe matrix below, then possibly a second opinion from Vosk in a Planner-vocabulary grammar.
52. **Speech parsing (1 Oct):** times stay whole through normalisation ("3:00 p.m." had split into the tasks "00 p" and "M"); times parse without "at" (6:00 in the evening, for 3 pm, 15:00, 4 o'clock, six thirty pm); an asked-for time inside fixed time is moved with a reason ("15:00 is during Office, so Planner found 20:00."); a time with no task asks for the rest; voice delete takes natural phrasings and a time alone ("delete the 11 pm task"); after a wake a leading "at"/"and" is read as "add".
53. **Phones are locked to portrait** (user request, 1 Oct; `main.dart`, shortest side < 600); tablets still rotate.

---

## 8. Backlog (what is left, in order)

1. **On-device verification** listed in section 0 (Drive, task alarms, notifications prompt, orb levels, haptics), and the first real "Hey Planner" run with Vosk.
2. **Alarm actions on the Notification style (optional):** the full-screen style has Done, Snooze and Start now; the notification style still has none (it would need a background notification-response handler).
3. **Release readiness:** a release signing key (and its SHA-1 plus Google Play's app-signing SHA-1 registered for the Android OAuth client), app name and id confirmation, iOS OAuth client when the user wants Drive on iOS, and the iOS `hey_planner_ios.ppn`.
4. Small polish: TaskBlock loading skeleton (only if data ever loads after the first frame), desktop hover lift (+5%) on blocks, an Android emulator with a stable image if wanted.

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

1. ~~Picovoice AccessKey and keyword files~~: no longer needed (Vosk, decision 50).
2. **iOS OAuth client** for Drive (deferred by the user).
3. App name and bundle id are the defaults (Planner, `com.planner.planner_app`); confirm or supply others before any store build.
