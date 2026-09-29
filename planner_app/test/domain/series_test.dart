import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/routine.dart';
import 'package:planner_app/domain/series.dart';
import 'package:planner_app/domain/task.dart';
import 'package:planner_app/domain/time.dart';

import 'fixtures.dart';

void main() {
  final gym = Series(
    id: 'sg',
    title: 'Gym',
    cat: Category.body,
    rule: const DayRule.on(0),
    start: 1200,
    end: 1260,
    from: mon + 7, // Monday 5 October
  );

  test('a weekly series lands on each matching day in the horizon', () {
    final occ = materializeSeries(gym, const [], routine, fromDay: tue, toDay: tue + kSeriesHorizonDays);
    expect([for (final t in occ) dayLabel(t.day!)], [
      'Monday 5 October',
      'Monday 12 October',
      'Monday 19 October',
      'Monday 26 October',
    ]);
    expect(occ.every((t) => t.start == 1200 && t.end == 1260), isTrue);
    expect(occ.first.id, occurrenceId('sg', mon + 7));
    expect(occ.first.seriesId, 'sg');
    expect(occ.first.recurrence, const DayRule.on(0));
  });

  test('existing occurrences are never recreated, even when moved', () {
    final moved = Task.make(occurrenceId('sg', mon + 7), 'Gym', Category.body, mon + 8, 1200, 60)
        .copyWith(seriesId: 'sg');
    final occ = materializeSeries(gym, [moved], routine, fromDay: tue, toDay: mon + 14);
    expect([for (final t in occ) t.day], [mon + 14]);
  });

  test('an occupied series time slides to the next free start', () {
    final busy = [Task.make('x', 'Study', Category.study, mon + 7, 1200, 30)];
    final occ = materializeSeries(gym, busy, routine, fromDay: mon + 7, toDay: mon + 7);
    expect(occ.single.start, 1230);
  });

  test('ending a series removes future undone occurrences only', () {
    final occ = materializeSeries(gym, const [], routine, fromDay: tue, toDay: mon + 21);
    final done = occ.first.copyWith(done: true);
    final all = [done, ...occ.skip(1)];
    final gone = endSeries('sg', all, fromDay: mon + 7);
    expect(gone.length, occ.length - 1);
    expect(gone.every((t) => t.deleted), isTrue);
  });
}
