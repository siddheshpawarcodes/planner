import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/notifications.dart';
import 'package:planner_app/domain/task.dart';

import 'fixtures.dart';

void main() {
  // Tuesday 29 September 2026, 19:40.
  final now = DateTime(2026, 9, 29, 19, 40);
  final tasks = [
    Task.make('a', 'Study polity', Category.study, wed, 1200, 120),
    Task.make('b', 'Exercise', Category.body, wed, 1335, 45),
    Task.make('c', 'Read', Category.self, tue, 1170, 30), // started already
    Task.make('d', 'Journal', Category.self, tue, 1320, 15).copyWith(done: true),
    Task.make('e', 'Call family', Category.people, null, null, 30),
  ];

  test('next task: 5 minutes before each upcoming start', () {
    final n = planNotifications(tasks: tasks, now: now).where((x) => x.kind == NoteKind.nextTask).toList();
    expect(n.map((x) => x.title), ['Study polity', 'Exercise']);
    expect(n.first.at, DateTime(2026, 9, 30, 19, 55));
    expect(n.first.body, 'Starts in 5 minutes, 20:00 → 22:00.');
  });

  test('missed: one check-in per day after its last open task', () {
    final m = planNotifications(tasks: tasks, now: now).where((x) => x.kind == NoteKind.missed).toList();
    expect(m.map((x) => x.at), [DateTime(2026, 9, 29, 20, 15), DateTime(2026, 9, 30, 23, 15)]);
    expect(m.first.body, 'Read is still open. Planner can find it a new time.');
    expect(m.last.body, 'Some of today’s plan is still open. Planner can find new times.');
  });

  test('weekly review on Sunday 21:00, and every kind can be switched off', () {
    final r = planNotifications(tasks: tasks, now: now).where((x) => x.kind == NoteKind.review).single;
    expect(r.at, DateTime(2026, 10, 4, 21));
    expect(planNotifications(tasks: tasks, now: now, nextTask: false, alarms: false, missed: false, review: false),
        isEmpty);
    final late = planNotifications(tasks: const [], now: DateTime(2026, 10, 4, 21, 30));
    expect(late.single.at, DateTime(2026, 10, 11, 21));
  });

  test('task alarms ring at each start, and go away when a task is done or moves', () {
    List<PlannedNote> alarms(List<Task> t) =>
        planNotifications(tasks: t, now: now).where((x) => x.kind == NoteKind.alarm).toList();
    final a = alarms(tasks);
    expect(a.map((x) => (x.title, x.at)), [
      ('Study polity', DateTime(2026, 9, 30, 20)),
      ('Exercise', DateTime(2026, 9, 30, 22, 15)),
    ]);
    expect(a.first.body, 'Time to start: 20:00 → 22:00.');
    // Completed: its alarm is gone the next time the plan is scheduled.
    final done = [for (final t in tasks) t.id == 'a' ? t.copyWith(done: true) : t];
    expect(alarms(done).map((x) => x.title), ['Exercise']);
    // Skipped or deleted: gone too.
    expect(alarms([for (final t in tasks) t.id == 'b' ? t.copyWith(skipped: true) : t]).map((x) => x.title),
        ['Study polity']);
    // Moved: the alarm moves with it.
    final moved = [for (final t in tasks) t.id == 'b' ? t.copyWith(day: thu, start: 1200, end: 1245) : t];
    expect(alarms(moved).last.at, DateTime(2026, 10, 1, 20));
  });
}
