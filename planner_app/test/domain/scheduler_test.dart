import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/domain/base_day.dart';
import 'package:planner_app/domain/capacity.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/layout.dart';
import 'package:planner_app/domain/routine.dart';
import 'package:planner_app/domain/scheduler.dart';
import 'package:planner_app/domain/task.dart';
import 'package:planner_app/domain/time.dart';

import 'fixtures.dart';

/// The three-task voice request, said on Tuesday at 19:40.
PlaceResult threeTaskRequest(List<Task> all) => placeMany(
      const [
        TaskSpec(title: 'Study polity', cat: Category.study, duration: 120),
        TaskSpec(title: 'Exercise', cat: Category.body, duration: 45),
        TaskSpec(title: 'Learn Flutter', cat: Category.build, duration: 60),
      ].map((s) => TaskSpec(
          title: s.title, cat: s.cat, duration: s.duration, day: wed)).toList(),
      all,
      routine,
      today: tue,
      now: 1180,
      newId: idGen(),
      allowWindDown: true,
    );

void main() {
  group('time', () {
    test('Monday 28 September 2026 is weekday 0, today (Tue 29) is 1', () {
      expect(weekday0(mon), 0);
      expect(weekday0(dayOf(DateTime(2026, 9, 29))), 1);
      expect(isWeekend(sat), isTrue);
      expect(isWeekend(fri), isFalse);
      expect(dateOf(sat), DateTime(2026, 10, 3));
    });

    test('fmt and dur match the prototype', () {
      expect(fmt(1200), '20:00');
      expect(fmt(1440), '00:00');
      expect(fmt(1335), '22:15');
      expect(dur(190), '3h 10m');
      expect(dur(120), '2h');
      expect(dur(45), '45m');
      expect(dur(-5), '0m');
      expect(ceil5(1301), 1305);
      expect(ceil5(1300), 1300);
    });

    test('labels', () {
      expect(dayLabel(thu), 'Thursday 1 October');
      expect(when(sat, 540), 'Sat 3 Oct, 09:00');
      expect(weekRange(tue), '28 Sep → 4 Oct');
      expect(nextWeekday(tue, 5), sat);
      expect(nextWeekday(sat, 5), sat + 7);
      expect(nextWeekday(tue, 0), mon + 7);
    });
  });

  group('baseItems', () {
    test('weekday with fixed work', () {
      final b = baseItems(wed, routine);
      expect([for (final x in b) '${x.id} ${x.start}-${x.end}'], [
        'wake 420-420',
        'morn 420-480',
        'work 480-1140',
        'c_dinner 1140-1200',
        'wind 1410-1440',
        'sleep 1440-1440',
      ]);
      expect(b[1].kind, ItemKind.protected);
      expect(b[2].kind, ItemKind.fixed);
      expect(b[2].cat, Category.work);
    });

    test('weekend: Getting ready is wake + 60, no office', () {
      final b = baseItems(sat, routine);
      expect([for (final x in b) x.id], ['wake', 'morn', 'c_dinner', 'wind', 'sleep']);
      expect(b[1].end, 480);
    });

    test('no fixed work behaves like a weekend', () {
      final b = baseItems(wed, routine.copyWith(noFixedWork: true));
      expect(b.any((x) => x.id == 'work'), isFalse);
      expect(b[1].end, 480);
    });

    test('overlaps resolve in time order and short leftovers drop', () {
      final r = routine.copyWith(commitments: const [
        // Starts inside the office: pushed to 19:00, then only 5 min left.
        Commitment(
            id: 'x',
            title: 'Standup',
            cat: Category.work,
            start: 1100,
            end: 1145,
            days: DayRule.everyDay),
        Commitment(
            id: 'dinner',
            title: 'Dinner',
            cat: Category.rest,
            start: 1140,
            end: 1200,
            days: DayRule.everyDay),
      ]);
      final b = baseItems(wed, r);
      expect(b.any((x) => x.id == 'c_x'), isFalse);
      final dinner = b.firstWhere((x) => x.id == 'c_dinner');
      expect((dinner.start, dinner.end), (1140, 1200));
    });

    test('commitment day rules', () {
      final r = routine.copyWith(commitments: [
        for (final c in defaultCommitments) c.copyWith(on: true)
      ]);
      expect(baseItems(sat, r).any((x) => x.id == 'c_gym'), isTrue);
      expect(baseItems(sun, r).any((x) => x.id == 'c_call'), isTrue);
      expect(baseItems(fri, r).any((x) => x.id == 'c_gym'), isFalse);
    });
  });

  group('capacity', () {
    test('new user weekday: realistic evening is 3h 10m', () {
      final c = capOf(wed, routine, const [], 0);
      expect(c.available, 300); // 5h
      expect(c.protectedMinutes, 90); // 1h 30m
      expect(c.breaks, 0);
      expect(c.buffer, 20);
      expect(dur(c.realistic), '3h 10m');
      expect(c.planned, 0);
    });

    test('Tue 19:40, empty evening: still 3h 10m from now', () {
      final c = capOf(tue, routine, inbox(), 1180);
      expect(dur(c.realistic), '3h 10m');
      final open = c.layout.gaps.where((g) => g.start >= 1080).toList();
      expect(open.single.start, 1200); // "20:00 → 23:30 open"
      expect(open.single.end, 1410);
    });

    test('weekends are capped at 6h until Planner learns the pace', () {
      final c = capOf(sat, routine, const [], 0);
      expect(c.realistic, 360);
      expect(dur(capOf(sat, routine, const [], 0, weekendCap: 300).realistic), '5h');
    });

    test('learned weekend cap is the 75th percentile after 14 days', () {
      expect(learnedWeekendCap(sat + 7, const [], historyDays: 3), isNull);
      final hist = [
        for (final (i, m) in [(0, 120), (7, 240), (14, 300), (21, 180)].indexed)
          Task.make('h$i', 'x', Category.study, sat - 28 + m.$1, 600, m.$2)
              .copyWith(done: true),
      ];
      // sorted 120 180 240 300 → index round(3 * .75) = 2 → 240
      expect(learnedWeekendCap(sat, hist, historyDays: 30), 240);
    });

    test('over-capacity copy is honest for the first 14 days', () {
      expect(overCapacityText(wed, 50, historyDays: 2),
          'This is 50m more than fits before your wind-down.');
      expect(overCapacityText(wed, 50, historyDays: 20),
          'This is 50m more than you usually finish in an evening.');
    });
  });

  group('three-task voice request', () {
    late PlaceResult res;
    setUp(() => res = threeTaskRequest(inbox()));

    test('places at 20:00, 22:15 and 23:00 on Wednesday', () {
      expect(res.left, isEmpty);
      expect([for (final p in res.placed) fmt(p.slot.start)],
          ['20:00', '22:15', '23:00']);
      expect([for (final p in res.placed) p.day], [wed, wed, wed]);
      expect(res.placed.last.slot.overWindDown, isTrue,
          reason: 'Flutter spills into wind-down');
      expect(res.placed.first.task.source, Source.voice);
    });

    test('a 22:00 break follows the 2h block', () {
      final l = buildDay(wed, routine, res.tasks);
      expect(l.breaks.single.start, 1320);
      expect(l.breaks.single.end, 1335);
      // Wind-down is fully covered by Flutter, so no protected piece remains.
      expect(l.seq.where((x) => x.id.startsWith('wind')), isEmpty);
    });

    test('Wednesday: 3h 45m planned vs 2h 55m realistic, 50m over', () {
      final c = capOf(wed, routine, res.tasks, 0);
      expect(dur(c.available), '5h');
      expect(dur(c.protectedMinutes), '1h 30m');
      expect(dur(c.breaks), '15m');
      expect(dur(c.buffer), '20m');
      expect(dur(c.realistic), '2h 55m');
      expect(dur(c.planned), '3h 45m');
      expect(dur(c.over), '50m');
      expect(c.isOver, isTrue);
      expect([for (final s in c.segments) s.cat],
          [Category.study, Category.body, Category.build]);
    });

    test('Move Flutter goes to Thursday 20:00 and the evening fits', () {
      final m = moveOverToday(wed, routine, res.tasks)!;
      expect(m.task.title, 'Learn Flutter');
      expect(m.day, thu);
      expect(fmt(m.slot.start), '20:00');
      final after = [
        for (final t in res.tasks)
          t.id == m.task.id ? t.placed(m.day, m.slot.start, m.slot.end) : t
      ];
      final c = capOf(wed, routine, after, 0);
      expect(c.planned <= c.realistic, isTrue);
      expect(c.isOver, isFalse);
    });
  });

  group('Wednesday evening', () {
    late List<Task> tasks;
    setUp(() {
      final placed = threeTaskRequest(inbox()).tasks;
      final m = moveOverToday(wed, routine, placed)!;
      tasks = [
        for (final t in placed)
          t.id == m.task.id ? t.placed(m.day, m.slot.start, m.slot.end) : t
      ];
    });

    test('Polity finished at 21:40 frees 20 min', () {
      final polity = tasks.firstWhere((t) => t.title == 'Study polity');
      final before = capOf(wed, routine, tasks, 1300);
      final (done, back) = completeTask(polity, today: wed, now: 1300);
      expect(back, 20);
      expect(done.done, isTrue);
      expect(done.end, 1300); // 21:40
      expect(done.plannedEnd, 1320);
      expect(done.doneAt, 1300);
      final after = capOf(wed, routine,
          [for (final t in tasks) t.id == done.id ? done : t], 1300);
      expect(before.planned - after.planned, 20);
      // Mark not done restores the plan.
      final undone = uncompleteTask(done);
      expect((undone.done, undone.end, undone.plannedEnd), (false, 1320, null));
    });

    test('completing outside the block hands nothing back', () {
      final ex = tasks.firstWhere((t) => t.title == 'Exercise');
      final (_, back) = completeTask(ex, today: wed, now: 1300);
      expect(back, 0);
    });

    test('23:05: Exercise is missed; This weekend is Sat 09:00', () {
      final ex = tasks.firstWhere((t) => t.title == 'Exercise');
      expect(isMissed(ex, wed, 1385), isTrue);
      expect(isMissed(ex, wed, 1370), isFalse);
      final opts = rescheduleOptions(ex, routine, tasks, today: wed, now: 1385);
      expect(opts[0].ok, isFalse);
      expect(opts[0].text, 'No room left today');
      expect(opts[1].text, 'Tomorrow 21:00');
      expect(opts[2].label, 'This weekend');
      expect(opts[2].day, sat);
      expect(opts[2].text, 'Sat 09:00');
      expect(when(opts[2].day, opts[2].slot!.start), 'Sat 3 Oct, 09:00');
    });

    test('Choose a day shows the first fitting time or Full', () {
      final ex = tasks.firstWhere((t) => t.title == 'Exercise');
      final days = chooseDaySlots(ex, routine, tasks, today: wed, now: 1385);
      expect(days.length, 7);
      expect(days[0].$2, isNull); // Full
      expect(fmt(days[3].$2!.start), '10:00'); // Saturday default 10:00
    });

    test('reschedule unfinished moves the missed task forward', () {
      final pol = tasks.firstWhere((t) => t.title == 'Study polity');
      final (done, _) = completeTask(pol, today: wed, now: 1300);
      tasks = [for (final t in tasks) t.id == done.id ? done : t];
      final r = rescheduleUnfinished(tasks, routine, today: wed, now: 1385);
      expect(r.moves.single.$1.title, 'Exercise');
      final moved = r.tasks.firstWhere((t) => t.title == 'Exercise');
      expect(moved.day, thu);
      expect(moved.movedCount, 1);
    });
  });

  group('findSlot', () {
    test('preferences', () {
      expect(findSlot(sat, 60, routine, const [], pref: TimePref.morning)!.start, 540);
      expect(findSlot(sat, 60, routine, const [])!.start, 600);
      expect(findSlot(sat, 60, routine, const [], pref: TimePref.afternoon)!.start, 780);
      expect(findSlot(wed, 60, routine, const [], pref: TimePref.evening)!.start, 1200);
      expect(findSlot(sat, 60, routine, const [], at: 725)!.start, 725);
    });

    test('never before wake, never past sleep, wind-down only on request', () {
      expect(findSlot(wed, 240, routine, const []), isNull);
      expect(findSlot(wed, 210, routine, const [])!.start, 1200);
      expect(findSlot(wed, 240, routine, const [], allowWindDown: true)!.start, 1200);
      expect(findSlot(wed, 240, routine, const [], allowWindDown: true)!.overWindDown, isTrue);
    });

    test('Add gym tomorrow when tomorrow is full searches forward', () {
      final full = [
        Task.make('a', 'Study polity', Category.study, wed, 1200, 210),
      ];
      final res = placeMany(
          const [TaskSpec(title: 'Gym', cat: Category.body, duration: 60)]
              .map((s) => TaskSpec(title: s.title, cat: s.cat, duration: 60, day: wed))
              .toList(),
          full,
          routine,
          today: tue,
          now: 1180,
          newId: idGen(),
          searchForward: true);
      expect(res.placed.single.day, thu);
      expect(fmt(res.placed.single.slot.start), '20:00');
    });

    test('Plan my evening stops when realistic capacity runs out', () {
      final res = placeMany(
          [
            for (final t in inbox())
              TaskSpec(
                  title: t.title,
                  cat: t.cat,
                  duration: t.duration,
                  day: tue,
                  existingId: t.id)
          ],
          [
            ...inbox(),
            Task.make('big', 'Deep work', Category.build, tue, 1200, 160),
          ],
          routine,
          today: tue,
          now: 1180,
          newId: idGen(),
          capacityLimited: true);
      // 160 planned of 175 realistic: even the 20m task would go over.
      expect(res.placed, isEmpty);
      expect(res.left.length, 3);
    });

    test('TaskSheet preview tries every day without wind-down first', () {
      final tasks = threeTaskRequest(inbox()).tasks;
      // Wednesday is full to sleep once Flutter holds 23:00.
      expect(previewSlot(30, routine, tasks, today: tue, now: 1180, date: wed),
          isNull);
      final th = previewSlot(30, routine, tasks, today: tue, now: 1180, date: thu)!;
      expect((th.day, fmt(th.start), th.overWindDown), (thu, '20:00', false));
      final any = previewSlot(30, routine, tasks, today: tue, now: 1180)!;
      expect(any.day, tue);
      expect(fmt(any.start), '20:00');
    });

    test('Fit in picks the next fitting evening slot', () {
      final s = fitInSlot(inbox().first, routine, const [], today: tue, now: 1180)!;
      expect((s.day, fmt(s.start)), (tue, '20:00'));
    });
  });

  group('ripple', () {
    test('Revise polity notes → Sat 10:00: 3 blocks made room, 2h 45m over', () {
      final all = weekSnapshot();
      final snapped = snapDrop(605, 90, routine, isToday: false);
      expect(snapped, 600);
      final next = ripple(all, 't4', sat, snapped, routine);
      final moved = next.firstWhere((t) => t.id == 't4');
      expect((moved.day, moved.start, moved.end), (sat, 600, 690));
      expect(ripplePushed(all, next, 't4'), 3);
      Task byId(String id) => next.firstWhere((t) => t.id == id);
      expect((byId('t2').start, byId('t2').end), (690, 735));
      expect((byId('t6').start, byId('t6').end), (735, 855));
      expect((byId('t5').start, byId('t5').end), (870, 1050));
      expect(byId('t7').start, 1200, reason: 'free, so it keeps its start');
      final c = capOf(sat, routine, next, 0);
      expect(dur(c.over), '2h 45m');
      expect(when(moved.day!, moved.start!), 'Sat 3 Oct, 10:00');
    });

    test('a drop on fixed or protected time slides to the next boundary', () {
      final all = weekSnapshot();
      final next = ripple(all, 't4', fri, 1150, routine); // inside Dinner
      final moved = next.firstWhere((t) => t.id == 't4');
      expect(moved.start, 1200);
      // The call that was at 21:30 slides after the moved block.
      expect(next.firstWhere((t) => t.id == 'i2').start, 1290);
    });

    test('done tasks never move and stay in place for others', () {
      final all = weekSnapshot();
      expect(identical(ripple(all, 't1', thu, 1200, routine), all), isTrue);
      final next = ripple(all, 't3', wed, 1200, routine);
      expect(next.firstWhere((t) => t.id == 't1').start, 1200);
      expect(next.firstWhere((t) => t.id == 't3').start, 1200,
          reason: 'fixed/protected only; done blocks are not in baseIv');
    });

    test('snapDrop never goes before now on today', () {
      expect(snapDrop(1200, 60, routine, isToday: true, now: 1302), 1305);
      expect(snapDrop(100, 60, routine, isToday: false), 420);
      expect(snapDrop(1430, 60, routine, isToday: false), 1380);
    });

    test('Move one picks the block that covers the overflow', () {
      final all = ripple(weekSnapshot(), 't4', sat, 600, routine);
      final m = moveOneBlock(sat, routine, all,
          today: thu, now: 1150, lastDay: sun)!;
      // Over by 165: the only block at least that long is WMM (180).
      expect(m.task.id, 't5');
      expect(m.day, sun);
    });
  });

  group('layout', () {
    test('proportional heights', () {
      expect(rowHeight(ItemKind.marker, 0), 30);
      expect(rowHeight(ItemKind.fixed, 660), 58);
      expect(rowHeight(ItemKind.fixed, 60), 66);
      expect(rowHeight(ItemKind.fixed, 20), 36);
      expect(rowHeight(ItemKind.breakTime, 15), 22);
      expect(rowHeight(ItemKind.protected, 20), 28);
      expect(rowHeight(ItemKind.task, 30), 44);
      expect(rowHeight(ItemKind.task, 120), closeTo(132, 1e-9));
      expect(rowHeight(ItemKind.open, 10), 36);
    });

    test('rows stack with a 6px gap in time order', () {
      final l = buildDay(tue, routine, const []);
      expect([for (final x in l.seq) x.id],
          ['wake', 'morn', 'work', 'c_dinner', 'gap1200', 'wind', 'sleep']);
      for (var i = 1; i < l.seq.length; i++) {
        expect(l.seq[i].y, closeTo(l.seq[i - 1].y + l.seq[i - 1].h + 6, 1e-9));
      }
      expect(nowY(l.seq, 1180), closeTo(l.seq[3].y + 40 / 60 * l.seq[3].h, 1e-9));
    });

    test('a kept overflow eats wind-down and protected pieces split', () {
      final l = buildDay(wed, routine, [
        Task.make('a', 'X', Category.self, wed, 1415, 10),
      ]);
      final winds = l.seq.where((x) => x.id.startsWith('wind')).toList();
      expect([for (final w in winds) (w.start, w.end)], [(1425, 1440)]);
    });

    test('skipped and deleted tasks are not laid out', () {
      final l = buildDay(wed, routine, [
        Task.make('a', 'X', Category.self, wed, 1200, 60).copyWith(skipped: true),
        Task.make('b', 'Y', Category.self, wed, 1300, 60).copyWith(deleted: true),
      ]);
      expect(l.tasks, isEmpty);
    });
  });

  group('guessCat', () {
    test('keywords', () {
      expect(guessCat('Study polity'), Category.study);
      expect(guessCat('Learn Flutter'), Category.build);
      expect(guessCat('Exercise'), Category.body);
      expect(guessCat('Gym'), Category.body);
      expect(guessCat('Call family'), Category.people);
      expect(guessCat('Read fiction'), Category.self);
      expect(guessCat('Team meeting'), Category.work);
      expect(guessCat('Nap'), Category.rest);
      expect(guessCat('Something else'), Category.self);
      expect(guessCat(null), Category.self);
    });
  });

  group('serialisation', () {
    test('task and routine round-trip through JSON', () {
      final t = weekSnapshot().first;
      final j = Task.fromJson(t.toJson());
      expect((j.id, j.day, j.start, j.end, j.plannedEnd, j.done, j.source),
          (t.id, t.day, t.start, t.end, t.plannedEnd, t.done, t.source));
      final r = Routine.fromJson(routine.toJson());
      expect(r.commitments.length, 3);
      expect(r.commitments[1].days, const DayRule.on(5));
      expect(r.commitments[1].label, 'Saturdays, 09:00 → 10:00');
      expect(defaultCommitments.first.label, 'Every day, 19:00 → 20:00');
    });
  });
}
