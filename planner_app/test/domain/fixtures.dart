import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/routine.dart';
import 'package:planner_app/domain/task.dart';
import 'package:planner_app/domain/time.dart';

/// The prototype's week: Monday 28 September 2026 is day index 0.
final int mon = dayOf(DateTime(2026, 9, 28));
final int tue = mon + 1, wed = mon + 2, thu = mon + 3, fri = mon + 4;
final int sat = mon + 5, sun = mon + 6;

/// Onboarding defaults: wake 07:00, office 08:00-19:00, dinner 19:00-20:00,
/// sleep 00:00.
const routine = Routine();

/// Prototype `INBOX()`.
List<Task> inbox() => [
      Task.make('i1', 'Read Laxmikanth ch. 4', Category.study, null, null, 45),
      Task.make('i2', 'Call family', Category.people, null, null, 30),
      Task.make('i3', 'Plan the week', Category.self, null, null, 20),
    ];

/// Prototype snapshot 'week' (Thursday, planning the week).
List<Task> weekSnapshot() {
  final i = inbox();
  return [
    Task.make('t1', 'Study polity', Category.study, wed, 1200, 120,
            source: Source.voice)
        .copyWith(done: true, end: 1300, plannedEnd: 1320, doneAt: 1300),
    Task.make('t2', 'Exercise', Category.body, sat, 600, 45,
        source: Source.voice, movedCount: 1),
    Task.make('t3', 'Learn Flutter', Category.build, thu, 1200, 60,
        source: Source.voice, movedCount: 1),
    i[0].copyWith(day: thu, start: 1275, end: 1320),
    Task.make('t4', 'Revise polity notes', Category.study, fri, 1200, 90),
    i[1].copyWith(day: fri, start: 1290, end: 1320),
    Task.make('t6', 'Polity practice test', Category.study, sat, 660, 120),
    Task.make('t5', 'WMM side project', Category.build, sat, 840, 180),
    Task.make('t7', 'Flutter: state management', Category.build, sat, 1200, 90),
    Task.make('t8', 'Polity: fundamental rights', Category.study, sun, 600, 120),
    Task.make('t9', 'Read fiction', Category.self, sun, 960, 60),
    i[2].copyWith(day: sun, start: 1080, end: 1100),
    Task.make('i4', 'Journal', Category.self, null, null, 15),
  ];
}

String Function() idGen() {
  var n = 200;
  return () => 'n${++n}';
}
