import '../../data/planner_data.dart';
import '../../domain/category.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';

/// The prototype's journey steps (`snap(k)`), rebuilt against the current
/// week: Monday of this week is the prototype's day 0. Debug only.
enum Scenario { onboard, tue, wed, missed, week, sunday, settings }

extension ScenarioInfo on Scenario {
  String get title => switch (this) {
        Scenario.onboard => 'Install and set up',
        Scenario.tue => 'Tue 19:40, the first evening',
        Scenario.wed => 'Wed 21:40, mid-study',
        Scenario.missed => 'Wed 23:05, a missed task',
        Scenario.week => 'Thu, plan the week',
        Scenario.sunday => 'Sun 21:00, the weekly review',
        Scenario.settings => 'Settings and Google Drive',
      };
}

class ScenarioState {
  const ScenarioState(this.data, this.clock);
  final PlannerData data;
  final DateTime clock;
}

ScenarioState buildScenario(Scenario k, {DateTime? now}) {
  final mon = weekStart(dayOf(now ?? DateTime.now()));
  int d(int i) => mon + i;
  DateTime at(int i, int minute) =>
      dateOf(d(i)).add(Duration(minutes: minute));

  List<Task> inbox() => [
        Task.make('i1', 'Read Laxmikanth ch. 4', Category.study, null, null, 45),
        Task.make('i2', 'Call family', Category.people, null, null, 30),
        Task.make('i3', 'Plan the week', Category.self, null, null, 20),
      ];
  final base = PlannerData(onboarded: true, installedDay: d(1), tasks: inbox());

  final pol = Task.make('t1', 'Study polity', Category.study, d(2), 1200, 120, source: Source.voice);
  final ex = Task.make('t2', 'Exercise', Category.body, d(2), 1335, 45, source: Source.voice);
  final fl = Task.make('t3', 'Learn Flutter', Category.build, d(3), 1200, 60,
      source: Source.voice, movedCount: 1);
  final dls = [
    Deadline(id: 'd1', title: 'WMM report', cat: Category.work, day: d(4), minute: 1080),
    Deadline(
        id: 'u1',
        title: 'UPSC prelims mock',
        cat: Category.study,
        day: d(12),
        note: '3 study blocks planned before it'),
    Deadline(
        id: 'u2',
        title: 'Flutter course, module 3',
        cat: Category.build,
        day: d(16),
        note: 'Nothing planned for it yet'),
  ];
  final polD = pol.copyWith(done: true, end: 1300, plannedEnd: 1320, doneAt: 1300);
  final i = inbox();
  final wk = [
    polD,
    ex.copyWith(day: d(5), start: 600, end: 645, movedCount: 1),
    fl,
    i[0].copyWith(day: d(3), start: 1275, end: 1320),
    Task.make('t4', 'Revise polity notes', Category.study, d(4), 1200, 90),
    i[1].copyWith(day: d(4), start: 1290, end: 1320),
    Task.make('t6', 'Polity practice test', Category.study, d(5), 660, 120),
    Task.make('t5', 'WMM side project', Category.build, d(5), 840, 180),
    Task.make('t7', 'Flutter: state management', Category.build, d(5), 1200, 90),
    Task.make('t8', 'Polity: fundamental rights', Category.study, d(6), 600, 120),
    Task.make('t9', 'Read fiction', Category.self, d(6), 960, 60),
    i[2].copyWith(day: d(6), start: 1080, end: 1100),
    Task.make('i4', 'Journal', Category.self, null, null, 15),
  ];

  switch (k) {
    case Scenario.onboard:
      return ScenarioState(PlannerData(tasks: inbox()), at(1, 1180));
    case Scenario.tue:
    case Scenario.settings:
      return ScenarioState(base, at(1, 1180));
    case Scenario.wed:
      return ScenarioState(
          base.copyWith(tasks: [...i, pol, ex, fl], deadlines: dls), at(2, 1300));
    case Scenario.missed:
      return ScenarioState(
          base.copyWith(tasks: [...i, polD, ex, fl], deadlines: dls), at(2, 1385));
    case Scenario.week:
      return ScenarioState(base.copyWith(tasks: wk, deadlines: dls), at(3, 1150));
    case Scenario.sunday:
      final t = [
        for (final x in wk)
          if (x.day == null)
            x
          else if (x.id == 't7' || x.id == 't9')
            x.copyWith(skipped: true)
          else if (x.day! < d(6) || x.id == 't8' || x.id == 'i3')
            x.copyWith(done: true)
          else
            x
      ];
      return ScenarioState(base.copyWith(tasks: t, deadlines: dls), at(6, 1260));
  }
}
