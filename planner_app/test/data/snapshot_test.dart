import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/data/snapshot.dart';

void main() {
  test('a snapshot round-trips through JSON and leaves deleted tasks out', () {
    final d = buildScenario(Scenario.week, now: DateTime(2026, 9, 28)).data;
    final withDeleted = d.copyWith(tasks: [...d.tasks, d.tasks.first.copyWith(deleted: true)]);
    final s = PlannerSnapshot.of(withDeleted, at: DateTime(2026, 10, 1, 21, 14));
    final back = PlannerSnapshot.decode(s.encode());
    expect(back.schemaVersion, 1);
    expect(back.exportedAt, DateTime(2026, 10, 1, 21, 14));
    expect(back.tasks.length, d.tasks.length);
    expect(back.tasks.map((t) => t.id), d.tasks.map((t) => t.id));
    expect(back.deadlines.map((x) => x.title), d.deadlines.map((x) => x.title));
    expect(back.routine.workEnd, d.routine.workEnd);
    expect(s.toJson().keys, containsAll(['schemaVersion', 'exportedAt', 'deviceId', 'routine', 'tasks', 'series', 'deadlines', 'settings']));
  });

  test('a newer schema is refused rather than half-read', () {
    final j = PlannerSnapshot.of(buildScenario(Scenario.tue).data).toJson()..['schemaVersion'] = 99;
    expect(() => PlannerSnapshot.fromJson(j), throwsFormatException);
  });
}
