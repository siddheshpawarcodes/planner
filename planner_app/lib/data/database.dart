import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

@DataClassName('TaskRow')
class TasksTable extends Table {
  @override
  String get tableName => 'tasks';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get cat => text()();
  IntColumn get day => integer().nullable()();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get endMinute => integer().nullable()();
  IntColumn get plannedEnd => integer().nullable()();
  IntColumn get duration => integer()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get doneAt => integer().nullable()();
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  IntColumn get deadline => integer().nullable()();
  TextColumn get recurrence => text().nullable()();
  TextColumn get seriesId => text().nullable()();
  IntColumn get movedCount => integer().withDefault(const Constant(0))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DeadlineRow')
class DeadlinesTable extends Table {
  @override
  String get tableName => 'deadlines';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get cat => text()();
  IntColumn get day => integer()();
  IntColumn get minute => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SeriesRow')
class SeriesTable extends Table {
  @override
  String get tableName => 'series';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get cat => text()();
  TextColumn get rule => text()();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  IntColumn get fromDay => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Routine, settings and app meta as JSON values.
@DataClassName('KvRow')
class KvTable extends Table {
  @override
  String get tableName => 'kv';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [TasksTable, DeadlinesTable, SeriesTable, KvTable])
class PlannerDatabase extends _$PlannerDatabase {
  PlannerDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'planner'));

  @override
  int get schemaVersion => 1;
}
