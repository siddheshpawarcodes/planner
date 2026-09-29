/// The seven category "lines". Colours live in `app/theme` (CategoryStyle);
/// the domain only needs identity, names and inference.
enum Category { study, build, body, people, self, work, rest }

extension CategoryName on Category {
  String get label => const [
        'Study', 'Build', 'Body', 'People', 'Self', 'Work', 'Rest'
      ][index];
}

Category categoryFromName(String? name) => Category.values
    .firstWhere((c) => c.name == name, orElse: () => Category.self);

final _study = RegExp(r'polity|study|upsc|revise|exam|history|laxmikanth|test');
final _build = RegExp(r'flutter|code|build|wmm|app|project|design');
final _body = RegExp(r'gym|exercise|run|yoga|walk|workout|swim');
final _people = RegExp(r'call|family|friend|mum|mom|dad|dinner with');
final _self = RegExp(r'read|journal|plan|meditat|write');
final _work = RegExp(r'office|meeting|report|email|work');
final _rest = RegExp(r'rest|nap|break|relax');

/// Keyword category inference, ported from the prototype's `guessCat`.
/// Order matters: the first matching line wins. Always user-editable.
Category guessCat(String? title) {
  final t = (title ?? '').toLowerCase();
  if (_study.hasMatch(t)) return Category.study;
  if (_build.hasMatch(t)) return Category.build;
  if (_body.hasMatch(t)) return Category.body;
  if (_people.hasMatch(t)) return Category.people;
  if (_self.hasMatch(t)) return Category.self;
  if (_work.hasMatch(t)) return Category.work;
  if (_rest.hasMatch(t)) return Category.rest;
  return Category.self;
}
