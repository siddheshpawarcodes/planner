# Planner: final design handoff (Flutter)

This is the production handoff for **Planner**, a local-first personal time-management app. It replaces the first "core identity" handoff and keeps what worked there: the proportional timeline, the now-line, the Planner Orb, the voice-to-scheduling sequence, capacity, the Strip and Dial views, the motion tokens and both themes. It closes every remaining product gap: Plan (Today, Tomorrow, Week, Upcoming), task creation, task detail, the missed-task flow, onboarding, weekly review, Settings, Google Drive, offline, empty states, responsive layouts, a full state matrix for every component, and reduced motion.

**Build target:** Flutter, Android first, then iOS, tablet and desktop from the same codebase. Dark and light themes carry equal weight; the default follows the system.

**Emotional outcome:** *"I feel in control of my time."* Every decision below serves that.

---

## 0. How to use the design canvas

The canvas is at the Artifact link shared with this file. The boards:

| Board | What it is | Fidelity |
|---|---|---|
| **Prototype: the whole journey** (`Main.dc.html`) | One interactive phone (400 × 860) holding the entire product, with a control panel beside it. **This is the build target.** | Final |
| **Foundations** (`System.dc.html`) | Grounds, category colours (contrast computed), type, shape, spacing, motion tokens with the live curves, reduced motion, Dart token code | Final |
| **Components** (`Components.dc.html`) | Every reusable widget with all of its states, specs, semantics and Flutter names; 8 live orb states | Final |
| **Locked decisions** (`Decisions.dc.html`) | Rail vs blocks, colour restraint, navigation, and the other calls settled after round one | Final |
| **Choreography** (`Choreography.dc.html`) | Millisecond timing diagrams for every cross-component sequence, plus the final quality test walked through | Final |
| **Tablet** (`Tablet.dc.html`) | 1194 × 834 landscape, light theme | Final layout |
| **Desktop** (`Desktop.dc.html`) | 1440 × 900, dark theme, keyboard model | Final layout |

The HTML is a **design reference**, not code to port line by line. The JavaScript in `Main.dc.html` does contain the exact scheduling, capacity and layout maths (`baseItems`, `buildDay`, `capOf`, `findSlot`, `ripple`) and every timing. Port those functions faithfully into pure Dart. All three layouts (phone, tablet, desktop) render from the same functions.

### Prototype controls (right of the phone)
- **Journey steps 1 to 8** jump to consistent moments: install, Tue 19:40 first evening, the three-task voice request, Wed 21:40 mid-study, Wed 23:05 missed task, Thu planning the week, Sun 21:00 weekly review, Settings and Drive.
- **Demo voice lines**: pick any of the nine voice commands, then tap the orb. "Say Hey Planner" simulates the wake phrase, and it only works while Today is on screen.
- **Switches**: theme, motion (full or reduced), microphone permission (allowed or denied), live mic (real amplitude drives the orb), network (online or offline), clock speed (1× or 60×).
- **Clock +30 min** and **Simulate a Drive conflict**.

---

## 1. Product model

1. The user tells Planner how a normal day works (**routine**) and what they need to get done (**tasks**).
2. Planner finds **realistic free time**, places tasks into it, tracks execution, learns patterns, and helps reschedule unfinished work.

### Information architecture
```
Onboarding (first run, or Settings, Edit routine)
Bottom nav:  Today · Plan · [ORB] · Progress · (settings icon)
  Today      Strip | Dial, day switch Today/Tomorrow, capacity, timeline
  Plan       Today | Tomorrow | Week | Upcoming   (one board, three zooms, plus a list)
  Progress   Ribbon, stats, heatmap, "Review this week" (Sunday evening)
  Settings   Routine, Notifications, Voice, Appearance, Backup (Google Drive), Data and statistics, About
Overlays:    Voice (orb), TaskSheet (create/edit), DetailSheet, DecisionSheet (missed/reschedule), Weekly review, Note strip
```
The orb sits dead centre in a five-slot grid (`1fr 1fr 92px 1fr 1fr`). Settings is an icon-only secondary slot in `t3`.

---

## 2. Locked decisions (summary; full reasoning on the Decisions board)

1. **Task language: B, square-cornered blocks (radius 4).** Blocks beat the rail on duration, mobile tap targets, drag, completion room and hierarchy. The rail survives as the **collapsed form** of a block in the Week board (4px transit lines).
2. **Colour: transit map.** Full category colour only for **current and next**. Everything else is a tint (20% of the colour mixed into `bg` in dark, 16% in light). Commitments are solid tinted bands (26% dark, 20% light).
3. **The now-line is ink (`tx`), not an accent.** Colour belongs to categories.
4. **No big clock on Today.** The now-pill carries the time.
5. **Plan is one instrument.** Today, Tomorrow and Week are the same board at three zooms. Upcoming is the one list.
6. **Done in Today vs Week.** Today dims finished work (focus on what's left). Week saturates finished work (the week fills in).
7. **One note strip** above the nav on every screen, with Undo. It replaces the inline note from round one.
8. **Protected time** is inferred: *Getting ready* (wake to work start, or wake + 60 on weekends) and *Wind-down* (the 30 min before sleep).
9. **Over-capacity copy is honest.** For the first 14 days: "This is 50m more than fits before your wind-down." After that, once history exists: "This is 50m more than you usually finish in an evening."

---

## 3. Design tokens

### 3.1 Neutrals
| token | dark | light | use |
|---|---|---|---|
| bg | `#0F1012` | `#F4F3EF` | page ground |
| s1 | `#1A1B1E` | `#E8E7E2` | sheets, panels, tracks |
| s2 | `#25272B` | `#DCDAD3` | thumbs, raised chips, note strip |
| ln | `#2E3035` | `#D3D1CA` | hairlines, dashed open time |
| tx | `#F2F2EF` | `#121212` | text, now-line, primary buttons |
| t2 | `#A9ABB0` | `#4D4D4A` | secondary text |
| t3 | `#80838A` | `#686863` | meta, times (≥ 4.5:1 on bg in both themes) |
| veil | `rgba(15,16,18,.86)` | `rgba(244,243,239,.88)` | voice overlay |
| scrim | `rgba(0,0,0,.52)` | `rgba(18,18,18,.30)` | behind sheets |

There are no drop shadows inside the app. Depth comes from bg → s1 → s2. Theme changes cross-fade over 420ms.

### 3.2 Categories
| category | colour | ink | examples |
|---|---|---|---|
| Study | `#2450E6` | white | UPSC polity, revision, tests |
| Build | `#00875A` | white | Flutter, side projects |
| Body | `#D9331A` | white | exercise, gym |
| People | `#C92A76` | white | family calls |
| Self | `#F5B800` | `#1A1404` | reading, journaling, planning |
| Work | `#5A6B7D` | white | office, reports |
| Rest | `#8C6A40` | white | dinner, breaks |

Rest was darkened from the proposed `#A07A4C` so white ink passes 4.5:1. All inks pass AA; the ratios are computed on the Foundations board. Category inference from a title (the prototype's `guessCat`) is keyword-based and always editable.

### 3.3 Type
Fonts: **Bricolage Grotesque** (500/600/700, opsz), **Geist** (300-600), **Geist Mono** (400-600). Bundle them via `pubspec.yaml`.

| role | spec |
|---|---|
| display | Bricolage 600 52/1.0, −3% (review) |
| question | Bricolage 600 34/1.06, −2% (onboarding) |
| screenTitle | Bricolage 600 24, −1.5% |
| sheetTitle | Bricolage 600 30/1.08 |
| taskTitle | Bricolage 600 15/1.2 (12 in Week blocks) |
| numeral | Geist 300 64-112/0.9, −5%, tabular |
| body | Geist 400 13-15/1.45 |
| time | Geist Mono 400-500 11-13, tabular |
| stateLabel | Geist Mono 600 9.5-11, +8-16% tracking (NOW, NEXT, MISSED, LISTENING only) |

**Rule:** if it isn't a time, it isn't mono. Support text scale up to 1.3×: rows grow rather than truncate.

### 3.4 Shape and space
- Radius: task block, band and chip square **4**. Week lines, heat cells and bars **2**. Panels **12**. Sheets **24** (top corners). Controls pill (**999**).
- Spacing: 4, 8, 12, 16, 20, 24, 32. Page gutter 20 (16 on Plan). Timeline row gap 6.
- Surface language: **solid tint = fixed**, **135° hatch = protected**, **dashed hairline = open**, **category stripes = overflow**, **dashed outline task = missed**.
- Touch targets ≥ 44 × 44 always.

### 3.5 Motion
| token | duration | curve | use |
|---|---|---|---|
| Snap | 160ms | `Cubic(0.3, 0, 0.2, 1)` | press, toggle, check stroke, drag pickup |
| Settle | 420ms | `Cubic(0.2, 0.8, 0.2, 1)` | screens, tabs, days, sheets, colour |
| Spring | 640ms | `Cubic(0.34, 1.35, 0.55, 1)` or `SpringDescription(mass: 1, stiffness: 260, damping: 20)` | placement, drag release, reflow, counters, capacity |
| Drift | 2600ms | `Curves.easeInOut`, repeat | ambient only: orb breath, now pulse |

**Hierarchy (one tier leads at a time):** 1 state change, 2 user action, 3 navigation, 4 data visualisation, 5 ambient. Ambient pauses whenever tiers 1-3 run (voice, drag, sheets).

**Reduced motion** (`MediaQuery.disableAnimations` OR Settings, Motion, Reduced): durations × 0.01, orb frozen per state (t = 1.2), no ripples, pulse or wobble, blur off (opacity only), voice script at 0.35×, placement appears in place. **State always commits before any animation. No feature waits for an animation to finish.**

Dart token classes are on the Foundations board (`PlannerColors` ThemeExtension, `Category` extension, `PlannerMotion.of(context, d)`).

---

## 4. Domain model

```dart
enum Category { study, build, body, people, self, work, rest }
enum Priority { low, normal, high }

class Routine {            // from onboarding, editable in Settings
  int wake;                 // minutes from midnight, e.g. 420
  int workStart, workEnd;   // 480, 1140
  int sleep;                // 1440 (can exceed 1440 for after-midnight)
  bool noFixedWork;
  List<Commitment> commitments;  // e.g. Dinner 1140-1200 every day
}

class Commitment { String id, title; Category cat; int start, end; DayRule days; bool on; }
// DayRule: everyDay | weekdays | weekends | weekday(int)

class Task {
  String id; String title; Category cat;
  DateTime? day;            // null = Unscheduled inbox
  int? start, end;          // minutes; end moves when finished early
  int? plannedEnd;          // original end if finished early
  int duration;             // requested minutes
  bool done, skipped, deleted; int? doneAt;
  Priority priority; DateTime? deadline;
  RecurrenceRule? recurrence; String? seriesId;
  int movedCount;           // counts toward "Rescheduled"
  Source source;            // voice | manual
  DateTime createdAt, updatedAt;
}

class Deadline { String id, title; Category cat; DateTime due; }
class Series { String id, title; Category cat; RecurrenceRule rule; int start, end; DateTime from; }
```

**Derived, never stored:** timeline items (markers, bands, protected pieces, auto breaks, open gaps), capacity, missed status, week load, progress aggregates.

---

## 5. Scheduling engine (port exactly; pure functions in `domain/`)

### 5.1 Base day (`baseItems(day, routine)`)
- Markers: Wake at `wake`, Sleep at `sleep`.
- Weekdays with fixed work: **Getting ready** (protected) `wake → workStart`, **Office** (fixed, Work) `workStart → workEnd`.
- Weekends or no fixed work: **Getting ready** `wake → wake+60`.
- Each active commitment that matches the day (fixed, its category).
- **Wind-down** (protected) `sleep−30 → sleep`.
- Overlaps resolve in time order: a later item starts at the previous one's end, and is dropped if under 10 min.

### 5.2 Day layout (`buildDay`)
- Tasks for the day (not deleted or skipped), sorted.
- **Auto break:** 15 min after any task of 120 min or more, if free and not in fixed time.
- Protected pieces are *trimmed* where a task overlaps them (a kept overflow eats wind-down).
- **Open gaps** are all remaining time from wake to sleep of 10 min or more.
- **Proportional layout:** PX = 1.1 px/min, GAP 6. Heights: marker 30; fixed `d > 90 ? 58 : max(36, d×1.1)`; break 22; protected `max(28, d×1.1)`; task `max(44, d×1.1)`; open `max(36, d×1.1)`.

### 5.3 Capacity (`capOf(day, fromMinute)`)
```
clip(x)   = max(0, x.end − max(x.start, from))
available = Σ clip(open, task, break, protected)       // non-fixed time
protected = Σ clip(base protected items)
breaks    = Σ clip(breaks)
buffer    = min(20, max(0, available − protected − breaks))
realistic = max(0, available − protected − breaks − buffer)
            weekend: min(realistic, 360) until 14 days of history,
            then the 75th percentile of finished minutes for that weekday
planned   = Σ clip(undone tasks)
over      = planned − realistic      // the calm row appears when over > 15
```
Today counts from `now`; other days count from 0. Worked example (new user, Wednesday): available 5h, protected 1h 30m, breaks 15m, buffer 20m, **realistic 2h 55m**. Polity 2h + Exercise 45m + Flutter 1h = **3h 45m planned, 50m over**.

### 5.4 Finding time (`findSlot(day, duration, {after, pref, at, exclude, allowWindDown})`)
- Busy = fixed + protected (wind-down excluded only when `allowWindDown`) + other live tasks, each extended by +15 when 120 min or more.
- Preference start: morning 09:00, afternoon 13:00, evening 18:00, weekend default 10:00, or an exact time. Try from the preference, then from `after`.
- `earliestFree` walks forward past every overlapping interval; the first fit before sleep wins.
- **Voice multi-task placement** places tasks in the order spoken, each after the previous one, and allows spill into wind-down as a last resort (so it can offer "Move / Keep anyway").
- **Manual creation** tries every day without wind-down first, then with it.
- "Add gym tomorrow" when tomorrow is full searches forward and says so: "Tomorrow evening is full, so Planner found the next free hour."

### 5.5 Moving time (`ripple(tasks, id, day, start)`)
Used by drag, move and reschedule:
1. Snap to 15 min. If the drop hits fixed or protected time, slide to the next free boundary.
2. Place the moved task. Done tasks never move.
3. Every other undone task that day, in time order, keeps its start if free, otherwise slides to the earliest free start after it (never into fixed or protected time).
4. A day that overflows gets striped load and the calm row: "Saturday runs 2h 45m past what fits. Move one block to a lighter day?" **Move one** picks the block that best covers the overflow and sends it to the next lighter day's first fitting slot.

### 5.6 Missed
A task is missed when `!done && end <= now` (today), or its day is past. It is not red. It shows a dashed outline and a MISSED label, and Today shows one calm prompt: "Exercise didn't happen. What should we do with it?" [Decide] [Later].

---

## 6. Screens

Mobile frame: 400 × 860 logical px; top inset 36 (system status bar, not drawn); nav 84. All copy below is final. **No em-dashes anywhere in UI copy.**

### 6.1 Onboarding (5 questions, then assembly)
- Top: 5 progress segments (3px, fill `tx`, Settle 520). Back button (44) from step 2.
- Question: Bricolage 600 34. The subtitle explains what Planner will do with the answer.
  1. "When do you wake up?" "Your day starts here. Planner never schedules before it." (04:00-12:00)
  2. "When does work begin?" "Planner keeps working hours off-limits." Chip: **I don't work fixed hours** (skips step 3).
  3. "When does work end?" "Your own time usually starts after this."
  4. "When do you normally sleep?" "Planner protects the last 30 minutes as wind-down." (up to 02:00)
  5. "What recurring commitments do you have?" Toggle rows (Dinner preselected, every day 19:00 → 20:00; Gym Sat 09:00; Family call Sun 18:00) plus **Add your own** (title, start chip, length, days).
- **Time input:** Geist 300 88 readout, −/+ 15 min buttons (44), and a draggable ruler (2 px/min, 15-min ticks, 5-min snap, masked edges). Keyboard and screen readers use the buttons; the readout is an `<output>` live region.
- **Live 24h bar** under the question: night, protected hatch, work band, commitments, dashed open time. It fills as the user answers, and a `tx` marker shows the value being set.
- **Assembly (step 6):** the first real weekday builds itself top to bottom. Each item rises 14px with Spring, 240ms apart. Then "**Your rhythm is ready.**" and "3h 10m of realistic time every weekday evening. Up to 6h on weekends." with the **Open Today** button. The transition to Today is Settle: the onboarding scales to 1.03 and blurs out while Today scales in from 0.98.

### 6.2 Today
Header (top to bottom):
1. Date title (Bricolage 600 21), **LOCAL** chip when offline, **+** add (44).
2. Day switch Today/Tomorrow (184 × 36, thumb Spring 460) and view switch Strip/Dial (112 × 36).
3. **Now line**: "Now Study polity 20 min left", "Now Dinner then Study polity at 20:00", "Next Exercise at 22:15", "Evening is yours, sleep at 00:00", or "Tomorrow 3 tasks planned". On the right, the done odometer: rolling digit (700ms Spring) / total, with DONE or PLANNED.
4. Segment bar: one 3px segment per task. It fills in the **task's category colour** when done (Today) or placed (Tomorrow).
5. **CapacityMeter** (see 7.3). Tap it to expand the equation panel.
6. Calm rows (at most one): over-capacity, or the missed prompt.

**Timeline (Strip):** proportional rows (5.2), 44px time column, content from 52px, masked top and bottom fades, auto-scroll so now sits 150px from the top. **Now indicator:** `tx` pill 44 × 20 with HH:mm, 1.5px line, and an 8px dot pulsing on Drift (paused during voice, drag and sheets). Its position moves linearly each second.

**TaskBlock** (7.1). Tap opens Detail, or the Decision sheet when missed. Tap the check or swipe right to complete. Completion commits immediately; if finished early, the block's end moves to now and the note says "Study polity done early. 20 min back in your evening." The next task is promoted to full colour.

**Empty state** (inside the main open window when the day has no tasks): "No plans yet." / "Tell Planner what you want to accomplish." / "Tap the orb, or say "Hey Planner"." / "20:00 → 23:30 open".

**Dial:** 320px, r 128, 24 ticks. Sleep is a dashed arc, commitments 8px tint 55%, protected dotted, open hairline, tasks 20px (26 selected) in tint 60% or full for now and next, missed dashed. The hand rotates `now/1440 × 360°`. The centre shows NOW/NEXT/MISSED/DONE, the title, the range, and **Mark done** or **Decide**. Below it, the up-next list. **Strip ↔ Dial:** the strip fades and scales to 0.97 (300); the dial turns in from −8° and 0.9 (520 Spring); arcs draw in time order (700, 45ms stagger).

### 6.3 Voice (the Planner Orb)
**Foreground only.** "Hey Planner" is armed only while Today is the visible route and the app is resumed. It stops on pause, route change, sheet, review or settings. There is no background service. Tapping the orb works anywhere in the app. Under the orb on Today, a 9px mono **HEY PLANNER** caption shows the wake phrase is available; it fades out on other tabs.

**Orb states** (PlannerOrb, CustomPainter + Ticker; renderer ported from `drawOrb`):
| state | visual | params |
|---|---|---|
| Idle | breathing, core = current task category or warm white | amp .03, idle 1 |
| Hover | livelier (desktop, web) | amp .16 |
| Wake | elastic wobble, rises from the nav (scale .42) to the upper centre (translateY −486, scale 1.1) over 760ms `Cubic(.34,1.22,.5,1)` | amp .45, wobV += 9 |
| Listening | surface and core follow the mic; peaks over .62 ripple (at most one per 420ms) | amp = clamp(RMS×7)×.95+.12 |
| Processing | surface stills, 3 droplets orbit | amp .05, proc 1 |
| Result | gentle wait while parsed rows show, or waiting for confirmation | amp .06, idle .6 |
| Success | core fills with the **scheduled task's category**, the tick draws, it docks | succ → 1 |
| Cancelled | a small horizontal "no" shake, core dims; note "Cancelled. Nothing was changed." | cancel 1 → 0 |
| Microphone denied | hollow core with a slash. "Planner can't hear you yet." [Allow microphone] [Type instead] (opens TaskSheet) | deny 1 |

**Overlay:** veil + 18px backdrop blur (opacity only under reduced motion). State label at top 70 (Mono 500 11, +16%). The transcript appears word by word (every 215ms, fade + rise 10px + unblur 6px). On understanding, key words go to `tx` weight 500 and the rest to `t3` (22ms stagger). Then the words lift and blur out, and the parsed rows stagger in (170ms): category square, Bricolage 20 title, mono detail. Hint at the bottom: "Tap anywhere to cancel".

**Intents** (rule-based parser over speech-to-text; slots: title, category, duration, day, time, recurrence):
| utterance | result | confirmation | after |
|---|---|---|---|
| "Tomorrow I want to study polity for two hours, exercise for 45 minutes and learn Flutter for one hour." | 3 tasks tomorrow evening, placed in order, break after 2h, Flutter spills into wind-down | none | Today › Tomorrow, **placement sequence**, then the over-capacity row |
| "Add gym tomorrow for one hour." | Gym 1h in the first evening slot; if tomorrow is full, the next free day, with an explanation | none | placement, or Week |
| "Move gym to Saturday." | finds the next undone gym or exercise task and moves it to Saturday morning | none | Plan › Week: held at the old spot, then flies to Saturday, both columns scan |
| "Mark gym complete." | completes today's gym task | none | Today, completion sweep |
| "Delete my gym task." | "DELETE THIS TASK?" row | **required**: [Delete Gym] (Body red) [Keep it] | note with Undo |
| "What do I have tomorrow?" | lists tomorrow's tasks, or office hours when empty; summary "3h 45m planned, 2h 55m realistic." | answer stays open: [Open tomorrow] [Done] | none |
| "Plan my evening." | places Unscheduled tasks into tonight until realistic capacity runs out; leftovers stay in the inbox with an explanation | none | Today placement |
| "Reschedule unfinished tasks." | every missed task goes to its next free slot | none | Today: tasks fly out, gaps close, note |
| "Add a recurring gym session every Monday." | series Gym, Mondays 20:00 → 21:00, from Monday 5 October | none | Plan › Upcoming › Repeats |

Not found: "There's no gym task on your plan. Try "Add gym tomorrow for one hour."" Destructive intents always confirm. Everything else commits at SUCCESS.

**Voice → scheduling sequence** (timings on the Choreography board; total about 13.6s at 1×):
1. Wake 0, Listening 900, words every 215, Understanding (last word + 550), parsed rows (+1100), **SUCCESS (+1200 + 3 × 170): tasks are committed here** with `place = hidden`.
2. Idle (+1200): veil out, orb docks, the day switch goes to Tomorrow (170 out, 360 in).
3. +650: the **window highlights** (`s1` fill, `t3` hairline) with its range "20:00 → 00:00 open", and a **scan line** sweeps it (800).
4. Each task is **introduced** at the top of the window (44px, inset 16%, 1.5px category ring), then 360ms later **placed** at its exact minute with a 640 Spring and a 5ms haptic, 620ms apart.
5. **Capacity and the odometer update as each one lands.** 500ms after the last one the highlight clears and the calm over-capacity row appears.

### 6.4 Task creation (TaskSheet, progressive)
It opens from **+** (Today, Plan), from "Type instead", or prefilled from voice ("From your voice: …").
1. **"What do you need to do?"** Bricolage 25 input, with suggestion chips from history (Study polity, Exercise, Learn Flutter, Read, Call family). A mic button switches to voice.
2. As soon as there's a title: **How long?** 15m 30m 45m 1h 1h 30m 2h, plus −/+ 15 for custom. The **category chip** is auto-inferred and tap-to-change (7 options).
3. After a duration: **When?** Planner picks (default) / Today / Tomorrow / Saturday. Time preference: Any time / Morning / Afternoon / Evening (exact time when editing).
4. **More options** (collapsed, with a summary line): Priority (Low, Normal, High), Deadline (None and quick dates), Repeat (Never, Every day, Weekdays, Every <weekday>).
5. **Live preview** (always visible): "Planner will place it", then "Tomorrow 21:00 → 21:30", then "1h 40m of realistic time left after this." or "This goes 25m past what fits. Planner will ask before keeping it."
6. **Schedule** (disabled until it fits): the sheet closes and the same **placement sequence** runs on Today (today or tomorrow), or Plan › Week flashes the new block (later days). Editing an existing task says **Save**.

### 6.5 Task detail (DetailSheet)
Category square and name, then the title (Bricolage 30). Day, range and duration. A **mini day strip** (wake → sleep) with this block highlighted among its neighbours. Rows: Deadline, Priority, Repeats, Added by (Voice or You), Status (Planned, In progress, Done at 21:40, Missed, Skipped). **History** squares (filled done, outlined missed, grey skipped), e.g. "Done 5 of the last 7 times", or "New on your plan. History builds as it repeats." Actions: **Complete** (full category colour; "Mark not done" when done; for missed tasks **Decide what to do with it**), then Reschedule, Skip, Edit, Delete (tap twice: "Tap again to delete"; the note offers Undo).

### 6.6 Missed task (DecisionSheet)
Title: "**What should we do with this?**" (from Detail's Reschedule: "When should this happen?"). Subtitle: "Exercise was planned for Wed 22:15 → 23:00." Options with the scheduler's real answer on the right:
- **Later today**: next slot after now, or "No room left today" (disabled)
- **Tomorrow**: evening slot, e.g. "Tomorrow 21:00"
- **This weekend**: morning slot, e.g. "Sat 09:00"
- **Choose a day**: expands a 7-day chip row, each showing its first fitting time or "Full"
- **Skip this time** (for recurring tasks: "Skip this occurrence"), "Counts as a decision"
- **Delete** (tap twice)

**Reschedule animation:** commit, the sheet closes (460 Settle), the block is **held** in place for 260ms, lifts to 1.02, then **flies** toward its destination (translate (96, −40), scale 0.5, fade over 560). Rows below reflow up (Spring), the Plan tab (or Tomorrow) bumps to 1.12, and the note reads "Exercise moved to Sat 3 Oct, 09:00." with Undo.

### 6.7 Plan
Header: dynamic title ("This week", "Thursday 1 October", "Upcoming") plus **+**. Segmented control: **Today | Tomorrow | Week | Upcoming** (thumb Spring).

**The board** (WeekBoard), one Stack:
- 06:00 → 24:00 in 432px (0.4 px/min). Axis every 3h (26px column).
- **Week mode:** the selected day expands (344 − 6×26 − 6×4 ≈ 164px). The other six collapse to 26px, and their tasks become **4px transit lines**.
- **Today/Tomorrow mode:** the selected day takes about 254px and the rest become 12px slivers. The same marks animate between zooms, **lines grow into blocks**.
- Column header: date, a 3px **load bar** (fill `tx` to realistic, stripes past it), and "1h 45m / 3h 10m" or "+1h 15m" when expanded.
- Commitment bands 30% tint, protected hatch, labelled free gaps of 40 min or more in the expanded day ("2h free"), a deadline rule ("Due 18:00, WMM report"), and the now-line in today's column.
- Colour: future tint 55% (line) or 28% (block), **done, current and next full**, missed dashed.
- **Drag:** long press 250ms on touch (6px with a mouse), lift to 1.03 with a `tx` ring. The column under the finger highlights; a **ghost** shows the snapped slot with a readout "Sat 10:00 → 11:30". **Neighbours reflow live** (ripple). On drop: Spring to the slot, a **scan line** runs down both affected days (700), load bars update, and the note reads "Revise polity notes moved to Sat 3 Oct, 10:00. 3 blocks made room. Saturday is now 2h 45m over what fits." with Undo.
- Below the board: the selected day's title and "2h 15m planned of 2h 55m realistic", **Add to this day**, the calm overload row when relevant, and (in day modes) the **Unscheduled** inbox with **Fit in**.
- Empty: "Your week is clear." / "Tell Planner what you want to accomplish, and it will find the time."

**Upcoming:** Deadlines (title, note such as "3 study blocks planned before it", date, "In 11 days"), Repeats (commitments and series), and Unscheduled (**Fit in** places it in the next fitting slot). Empty: "Nothing upcoming. Your week is clear."

### 6.8 Progress
Header "This week 28 Sep → 4 Oct" with a **Your time | With work** toggle.
- **Hero: stacked category ribbon.** A streamgraph centred on a baseline across Mon to Sun. Band thickness is hours **completed** per category (order Study, Build, Body, People, Self, Rest, then Work when included), smoothed with horizontal-tangent cubics, with 1px `bg` separators. A **dashed envelope** marks what was planned, so the gap between ribbon and envelope is unfinished time. Monday before install pinches to zero. It reveals left to right (clip, 1400 Settle). Tap a day: a hairline cursor and a per-day breakdown ("Saturday, 8h: Build 3h, Study 2h…"); otherwise it shows weekly category totals in a 2-column legend.
- "**19 of 24** planned tasks done" (count-up 1500ms ease-out cubic) with one sentence of interpretation.
- Three stats: completed %, focused (Study + Build + Self), days with Planner.
- Rescheduled, Skipped, Carried forward (three small s1 cells).
- **Heatmap** "When you actually work": 7 × 36 half-hour cells, monochrome `tx` at 0/.18/.36/.62/1. Diagonal entry with an 11ms stagger. A bracket marks the best window. Tap a cell for "Thu 21:00 → 21:30: 22m focused".
- **Review this week** (Sunday evening), or "The weekly review opens on Sunday evening."
- Early-week empty: "Your first week has started." / "Tell Planner what you want to accomplish. The ribbon fills in as you do it." Heatmap: "Your rhythm appears here after a few days of use."

### 6.9 Weekly review (staged story, 6 screens)
Full screen, 6 progress segments, tap right to advance or left to go back, close top right, arrow keys on desktop.
1. "**Your week, as it happened.**" The ribbon draws in (1600). "The dashed outline is what you planned."
2. "**You planned 24 tasks.** / You finished 19." 24 squares fill in category colours (45ms each); "79% completion in your first week. The five open squares were moved or skipped, not lost."
3. "**16h 10m** of focused time." Study, Build and Self bars grow (no tracks).
4. "**Some things moved.**" Rescheduled 4, Skipped 2, Carried forward 1, each with its names.
5. "**Your best hours were 20:30 → 22:30.**" Heatmap, Most active: Study 8h 40m, Biggest day: Saturday.
6. "**Coming up.**" Deadlines. **Plan next week** (goes to Plan › Upcoming) and Done.

### 6.10 Settings
A push page (slides from the right, the nav stays visible, the settings icon turns active). Sections:
- **Routine**: Wake, Work, Sleep, Commitments; **Edit routine** re-runs onboarding prefilled, then "Routine updated. Planner rebuilt your week around it."
- **Notifications**: Next task (5 min before), Missed tasks (one gentle check-in, never a pile-up), Weekly review (Sunday 21:00).
- **Voice**: "Hey Planner" switch ("Works only while Today is open on screen. Planner never listens in the background."), Microphone status with Allow, Language.
- **Appearance**: Theme (System, Dark, Light), Motion (System, Reduced, Full), Today opens as (Strip, Dial).
- **Backup**: Google Drive row with its live status.
- **Data and statistics**: Week starts on Monday; Count skipped as missed (off: "skipping is a decision, not a failure"); Export as JSON; Delete all data (tap twice).
- **About**: "Planner 1.0. Local-first: your plan lives on this phone and works offline. Google Drive only keeps a private backup."

### 6.11 Google Drive (backup and sync, never the primary database)
Scope: `drive.appdata` (app data folder only). Copy: "Planner only sees the one backup file it creates. It can't read the rest of your Drive."

States:
| state | UI |
|---|---|
| Not connected | explanation plus **Connect Google Drive** |
| Connecting | "Waiting for Google…" plus an indeterminate 2px bar; the app stays usable |
| Synced | Account, Last backup, Status, Back up automatically (nightly, on Wi-Fi); **Back up now**, **Restore from Drive**, Disconnect |
| Backing up / Restoring | label plus a determinate 3px bar with % |
| Offline | calm s1 panel: "You're offline. Everything is saved on this phone, and Planner backs up as soon as you reconnect." Backup is disabled as "Back up when online" |
| Conflict | "Two versions of your plan". Compare cards (This phone: edited today 21:14, 14 tasks; Drive: tablet, yesterday 22:40, 12 tasks), **Keep this phone** / **Use the Drive version**. The loser is kept as a separate backup file |
| Restore confirmation | sheet: "Replace this phone's plan with the Drive backup?" "…Planner saves your current plan as a separate backup first, so you can switch back." [Restore] [Cancel] |

Sync model: a single JSON snapshot `planner-backup.json` (`schemaVersion`, `exportedAt`, `deviceId`, `routine`, `tasks`, `series`, `deadlines`, `settings`) plus `planner-backup-<timestamp>.json` for kept losers. **Conflict** = the remote `exportedAt` is newer than the last local sync *and* local has changes since the last sync. There is no silent merge in v1.

### 6.12 Offline
Planner is local-first: nothing becomes read-only. The only signals are the small **LOCAL** chip on Today's header (tap: "Offline. Everything is saved on this phone and backs up when you reconnect."), the Drive row status "Offline, waiting to back up", and the sync glyph (cloud with slash). Never a banner.

---

## 7. Component catalogue (widgets; full state matrices on the Components board)

Every interactive widget: Default, Hover (desktop), Pressed (Snap scale .97, check .86), Focused (2px `tx` outline, 2px offset), Loading, Success, Error, Disabled, and Completed where relevant.

### 7.1 `TaskBlock(task, state, onOpen, onComplete)`
States: upcoming (tint), next (full + NEXT), current (full + NOW + elapsed shade `rgba(0,0,0,.18)` growing each second), hover (+5% lift), pressed (.98), focused, dragging (1.03 + `tx` ring), staged (placement: 44px, inset 16%, category ring), completing (sweep `scaleX 0→1` over 380 Snap, check to 1.18, tick draws 300 after 200), completed (bg fill, 1px `ln` ring, `t3` struck title), missed (transparent, dashed `t3`, MISSED), overflow (category stripes over the portion inside wind-down, WIND-DOWN label), loading (shape-true skeleton plus shimmer, first open only), error (local write failed: "Not saved, tap to retry"), disabled (0.5, past and locked).
Swipe: activates after 8px horizontal, 1:1 to 80px then 0.35×, capped at 140; releasing past 70px completes; returns with a 560 Spring. Reveal layer: tint plus the category-coloured DONE label.
Semantics: "Study polity, 20:00 to 22:00, in progress. Double-tap for details." Custom actions: Complete, Reschedule.

### 7.2 Timeline rows
`TimelineMarker`, `CommitmentBand`, `ProtectedBand`, `OpenWindow` (carries the empty state), `BreakRow`, `NowIndicator`.

### 7.3 `CapacityMeter(capacity, expanded)`
8px bar: planned segments in category colours in time order, stripes past realistic; right of the marker: breaks (s2), buffer (dotted), protected (hatch). 2px `tx` marker. Legend AVAILABLE / PROTECTED / BREAKS / BUFFER. Animates with 620 Spring. The whole meter is a button that expands the **equation panel** (Available, − Protected with names, − Breaks, − Buffer, = Realistic). `OverCapacityRow`: calm s1 panel with **Move <task>** (primary) and **Keep anyway** (text).

### 7.4 `PlannerOrb` and `VoiceOverlay`: see 6.3.

### 7.5 Controls
`PrimaryPill` (tx on bg, 44-52 tall), `SecondaryPill` (1px ln), `ChoiceChip` (36), `PlannerSwitch` (40 × 24, thumb 18, Spring 420, `role=switch`), `SegmentedControl` (thumb Spring 460, aria-pressed, arrow keys), `IconButton` (44). Loading: a 2px bar sweeps inside and the label becomes the -ing verb (no spinners). Success: past tense for 1.2s. Error: inline t2 text under the control, never red fills.

### 7.6 `WeekBoard(days, selected, mode)`, `DayColumn`, `TransitLine`, `DragGhost`: see 6.7. Every mark is an `AnimatedPositioned` keyed by id, so moves and zooms are the same animation.

### 7.7 Surfaces
`PlannerSheet` (24 top radius, handle 36 × 4, Settle 460 from 104%, scrim, drag down to close, focus to the title), `NoteStrip` (s2, 12 radius, 96px above the bottom, rises 12px Spring, 3.6s or 5.2s with an action, live region), `SyncChip` (silent when synced, SYNCING, LOCAL, NEEDS A DECISION), `BottomNav` (84px, 1px top hairline, active 16 × 2 `tx` bar with scaleX Spring, Plan bump on incoming moves).

### 7.8 Data viz
`CategoryRibbon` (CustomPainter), `FocusHeatmap`, `CountUp`.

---

## 8. Responsive

| width | layout |
|---|---|
| < 600 | Phone: bottom nav with the centred orb, single pane. The mobile prototype. |
| 600-1023 | Tablet: **left rail** (Today, Plan above the orb, Progress and settings below it, orb vertically centred), a **Today pane** (380) always visible, and the **Plan board** filling the rest with the selected day expanded to about 284px. Calm rows sit under the board. See the Tablet board (light theme). |
| ≥ 1024 | Desktop: **sidebar** (232: nav with key hints, week summary with 7 mini load bars, docked orb with "Talk to Planner V", sync status, settings), **Week planner** (all 7 days expanded, about 96px each, titles and times), **Today rail** (400: date, now line, capacity, strip from 18:00, keyboard legend). See the Desktop board. |

Desktop and web add hover states, a grab cursor, the drag ghost with a readout, and **keyboard**: N new task, V talk, T today, ← → previous or next day, Enter open, Space complete, Alt ↑↓ move 15 min, Alt ←→ move a day, Ctrl/⌘ Z undo, ? all shortcuts. Voice on desktop: V or click the orb; the wake phrase follows the same foreground rule (Today visible).

---

## 9. Accessibility
- Contrast: text on bg ≥ 4.5:1 in both themes (t3 is about 5:1 in both themes). Category inks pass AA (computed on the Foundations board).
- Targets ≥ 44 × 44. Visible shapes can be smaller (the 22px check) but the hit area never is.
- Semantics: every block, column, orb state and chart has a label (strings on the Components board). The ribbon exposes per-day summaries; the heatmap exposes a row summary.
- Screen readers: completion, placement and moves are announced through the NoteStrip live region. Swipe and drag always have button or custom-action equivalents (check button, Reschedule, Move earlier/later/to…).
- Colour is never the only signal: MISSED label plus dashed outline, NOW/NEXT labels, stripes for over.
- Reduced motion: see 3.5. Text scale up to 1.3× with row growth.
- Keyboard traversal on desktop and tablet with a hardware keyboard: focus order header → board (arrow keys within) → Today rail.

---

## 10. Architecture (suggested; adapt to an existing project)
```
lib/
  app/            router (go_router), theme (PlannerColors, PlannerMotion), l10n
  domain/         routine.dart, task.dart, base_day.dart, layout.dart,
                  capacity.dart, scheduler.dart (findSlot, ripple, placeMany),
                  intents.dart (voice grammar), progress.dart (aggregates)
  data/           drift database (tasks, commitments, series, deadlines, settings, history)
                  backup/ (drive_client.dart, snapshot.dart, conflict.dart)
  features/
    onboarding/   today/ (strip, dial)  plan/ (week_board, upcoming)
    voice/        (wake_word, stt, orb_painter, overlay, voice_controller)
    tasks/        (task_sheet, detail_sheet, decision_sheet)
    progress/     (ribbon_painter, heatmap, review)
    settings/     (settings_page, drive_page)
  widgets/        task_block, capacity_meter, note_strip, controls/*
```
- State: Riverpod. `clockProvider` (1s tick + boundary checks), `routineProvider`, `tasksProvider` (Drift stream), derived `dayLayoutProvider(day)`, `capacityProvider(day)`, `weekProvider`, `voiceControllerProvider` (a state machine: idle → wake → listening → processing → result → success | cancelled | denied), `placementProvider` (visual-only staging map, like `place` in the prototype), `syncProvider` (Drive state machine).
- **Visual staging is separate from domain state.** `place`, `hold`, `leaving` and `sweeping` in the prototype are UI-only maps. The repository writes first, always.
- Packages (suggested): `flutter_riverpod`, `drift` + `sqlite3_flutter_libs`, `go_router`, `speech_to_text` (STT), `record` (amplitude stream for the orb), `permission_handler`, `google_sign_in` + `googleapis` (Drive v3 appDataFolder), `flutter_local_notifications`, `connectivity_plus`. For the wake word, use an on-device keyword spotter that runs only while Today is foreground (for example Porcupine with a custom "Hey Planner" keyword), falling back to a tap. No background audio service.
- Haptics: light impact 12ms on complete, 8ms on orb tap, 5ms per placement, 16ms on voice success.

---

## 11. Build order and acceptance
1. Tokens and theme, then the domain functions (port `baseItems`, `buildDay`, `capOf`, `findSlot`, `earliestFree`, `ripple`) **with unit tests from the numbers in this doc** (for example Wednesday: realistic 2h 55m, planned 3h 45m, over 50m).
2. Today Strip with TaskBlock, NowIndicator and CapacityMeter; completion, including done early.
3. TaskSheet and the placement sequence.
4. Plan board (three zooms, drag, ripple, scan), then Upcoming.
5. Missed flow and DecisionSheet with the fly animation.
6. Voice: overlay and orb painter, then STT and intents, then the wake word (foreground only).
7. Onboarding with assembly.
8. Progress (ribbon, heatmap), then the weekly review.
9. Settings, Drive (all states, conflict, restore), offline.
10. Tablet and desktop layouts, keyboard, reduced motion pass, accessibility pass.

**Acceptance: the final quality test as an integration test** (also on the Choreography board):
- Onboard with wake 07:00, office 08:00-19:00, dinner 19:00-20:00, sleep 00:00. Expect the weekday realistic evening to be 3h 10m.
- On Today at 19:40, the empty evening state shows. Say the three-task request. Expect 3 Wednesday tasks at 20:00, 22:15 and 23:00, a 22:00 break, capacity 3h 45m / 2h 55m, and the over row.
- Tap **Move Flutter**. Expect Thursday 20:00 and the evening back within realistic.
- On Wednesday at 21:40, complete Study polity. Expect end 21:40, the note "20 min back", odometer 1.
- At 23:05 Exercise is missed. Expect the prompt. Decide: This weekend. Expect Saturday 09:00, Rescheduled +1.
- On Sunday the review shows the week's aggregates.

---

## 12. Assets
No bitmaps. Every graphic is code-drawn (orb, dial, ribbon, heatmap, hatch, stripes). Icons in the canvas are simple stroke placeholders; in Flutter use one icon family (Phosphor, 1.5 stroke): Plus, X, CaretLeft, CaretRight, Sliders, Microphone, Cloud, CloudSlash.
