import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/router.dart';
import '../../app/state/derived.dart';
import '../../app/state/note.dart';
import '../../app/state/store.dart';
import '../../app/theme/planner_theme.dart';
import '../../data/alarm_prefs.dart';
import '../../domain/notifications.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../notifications/notification_service.dart';
import 'alarm_backgrounds.dart';
import 'alarm_engine.dart';
import 'alarm_platform.dart';
import 'alarm_screen.dart';

/// Picks a photo, GIF or video and copies it into Planner's files, so the
/// alarm still has it if the original is deleted. Returns the copy's path.
class AlarmMedia {
  const AlarmMedia();

  Future<String?> pick({required bool video}) async {
    final p = ImagePicker();
    final f = video
        ? await p.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2))
        : await p.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (f == null) return null;
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/alarm_media');
    await dir.create(recursive: true);
    final ext = f.path.contains('.') ? f.path.substring(f.path.lastIndexOf('.')) : (video ? '.mp4' : '.jpg');
    final out = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(f.path).copy(out);
    return out;
  }

  /// Deletes copies no look uses any more.
  Future<void> prune(AlarmPrefs p) async {
    final used = {p.look.mediaPath, for (final l in p.overrides.values) l.mediaPath};
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/alarm_media');
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      if (f is File && !used.contains(f.path)) await f.delete();
    }
  }
}

final alarmMediaProvider = Provider<AlarmMedia>((ref) => const AlarmMedia());

/// Settings › Customise alarm screen: a live preview, then the look
/// (background, effects, clock and text) for every alarm or one category,
/// and the global sound and actions.
class AlarmCustomisePage extends ConsumerStatefulWidget {
  const AlarmCustomisePage({super.key});

  @override
  ConsumerState<AlarmCustomisePage> createState() => _AlarmCustomisePageState();
}

class _AlarmCustomisePageState extends ConsumerState<AlarmCustomisePage> {
  late AlarmPrefs _p = ref.read(settingsProvider).alarm;

  /// null = the default look; otherwise that category's.
  Category? _scope;
  final _message = TextEditingController();
  late final AlarmPlatform _platform;

  @override
  void initState() {
    super.initState();
    _platform = ref.read(alarmPlatformProvider);
    _message.text = _look.message;
  }

  @override
  void dispose() {
    _message.dispose();
    _platform.stopPreview();
    super.dispose();
  }

  AlarmLook get _look => _scope == null ? _p.look : _p.lookFor(_scope!);
  bool get _own => _scope == null || _p.overrides.containsKey(_scope);

  void _save() {
    final store = ref.read(plannerStoreProvider.notifier);
    store.setSettings(ref.read(settingsProvider).copyWith(alarm: _p));
  }

  void _update(AlarmPrefs p, {bool save = true}) {
    setState(() => _p = p);
    if (save) _save();
  }

  void _edit(AlarmLook Function(AlarmLook l) f, {bool save = true}) {
    final l = f(_look);
    _update(_scope == null ? _p.copyWith(look: l) : _p.withOverride(_scope!, l), save: save);
  }

  void _setScope(Category? c) {
    setState(() => _scope = c);
    _message.text = _look.message;
  }

  Future<void> _pickMedia({required bool video}) async {
    final path = await ref.read(alarmMediaProvider).pick(video: video);
    if (path == null) return;
    _edit((l) => l.copyWith(bg: video ? AlarmBg.video : AlarmBg.photo, mediaPath: path));
    await ref.read(alarmMediaProvider).prune(_p);
  }

  void _test() {
    final at = DateTime.now().add(const Duration(seconds: 10));
    ref.read(testAlarmProvider.notifier).set(at, cat: _scope ?? Category.study);
    ref.read(noteProvider.notifier).say('Test alarm rings at ${fmt(at.hour * 60 + at.minute)}. Lock the phone to see it there.');
  }

  /// The sample the preview shows: the next real task in scope, or a
  /// stand-in.
  PlannedAlarm _sample() {
    final cat = _scope ?? Category.study;
    final today = dayOf(DateTime.now());
    final tasks = ref.read(tasksProvider);
    Task? t;
    for (final x in tasks) {
      if (!x.isLive || x.done || x.day! < today || (_scope != null && x.cat != _scope)) continue;
      if (t == null || x.day! * 1440 + x.start! < t.day! * 1440 + t.start!) t = x;
    }
    if (t == null) {
      return PlannedAlarm(
        id: 0,
        at: dateOf(today).add(const Duration(hours: 20)),
        title: _scope == null ? 'Study polity' : '${cat.label} time',
        cat: cat,
        range: '20:00 → 21:00',
        next: 'Then Exercise at 21:15',
      );
    }
    final a = alarmsFrom([
      PlannedNote(0, NoteKind.alarm, dateOf(t.day!).add(Duration(minutes: t.start!)), t.title, '', taskId: t.id)
    ], tasks);
    return a.first;
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final l = _look;
    final line = BorderSide(color: c.ln);
    final reduced = PlannerMotion.reduced(context);

    Widget heading(String t, {String? sub}) => Padding(
          padding: const EdgeInsets.only(top: 26, bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(t, style: PlannerType.bricolage600(15, color: c.tx))),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub, style: PlannerType.body(size: 12, color: c.t3)),
            ],
          ]),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(t, style: PlannerType.body(size: 13, color: c.t2)),
        );
    Widget toggle(String title, bool on, ValueChanged<bool> set, {String? sub}) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: Border(top: line)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: PlannerType.ui(14, color: c.tx)),
                if (sub != null) Text(sub, style: PlannerType.body(size: 12, color: c.t3)),
              ]),
            ),
            PlannerSwitch(value: on, onChanged: set, label: title),
          ]),
        );
    Widget slider(String name, double v, AlarmLook Function(AlarmLook l, double x) apply) => Row(children: [
          SizedBox(width: 92, child: Text(name, style: PlannerType.body(size: 13, color: c.t2))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: c.tx,
                inactiveTrackColor: c.ln,
                thumbColor: c.tx,
                overlayColor: c.tx.withValues(alpha: 0.08),
                trackHeight: 3,
              ),
              child: Slider(
                value: v,
                semanticFormatterCallback: (x) => '$name ${(x * 100).round()}%',
                onChanged: (x) => _edit((l) => apply(l, x), save: false),
                onChangeEnd: (_) => _save(),
              ),
            ),
          ),
          SizedBox(width: 40, child: Text('${(v * 100).round()}%', textAlign: TextAlign.right,
              style: PlannerType.time(size: 12, color: c.t3))),
        ]);
    Widget chips<T>(List<(T, String)> opts, bool Function(T) sel, ValueChanged<T> tap) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (v, s) in opts) PlannerChip(label: s, selected: sel(v), onTap: () => tap(v)),
          ],
        );

    final editors = <Widget>[
      heading('Background'),
      chips<AlarmBg>(
        const [(AlarmBg.look, 'Animated look'), (AlarmBg.photo, 'Photo or GIF'), (AlarmBg.video, 'Video'), (AlarmBg.category, 'Category colour')],
        (v) => l.bg == v,
        (v) {
          if ((v == AlarmBg.photo || v == AlarmBg.video) && (l.bg != v || l.mediaPath == null)) {
            _pickMedia(video: v == AlarmBg.video);
          } else {
            _edit((l) => l.copyWith(bg: v));
          }
        },
      ),
      if (l.bg == AlarmBg.look) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AlarmLookId.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final id = AlarmLookId.values[i];
              final on = l.lookId == id;
              return Pressable(
                onTap: () => _edit((l) => l.copyWith(lookId: id)),
                label: '${id.label} look',
                selected: on,
                radius: 14,
                excludeChildSemantics: true,
                child: Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 72,
                    height: 120,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: on ? c.tx : Colors.transparent, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: AlarmBackground(
                        look: AlarmLook(bg: AlarmBg.look, lookId: id, dim: 0, zoom: false),
                        cat: _scope ?? Category.study,
                        reduced: !on || reduced,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(id.label, style: PlannerType.ui(12, color: on ? c.tx : c.t2)),
                ]),
              );
            },
          ),
        ),
      ],
      if (l.bg == AlarmBg.photo || l.bg == AlarmBg.video) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              l.mediaPath == null || !File(l.mediaPath!).existsSync()
                  ? 'Nothing chosen yet. Until then it uses the category colour.'
                  : l.bg == AlarmBg.video
                      ? 'Your video, looping silently (the alarm tone is the sound).'
                      : 'Your photo. GIFs play as they are.',
              style: PlannerType.body(size: 12, color: c.t3),
            ),
          ),
          const SizedBox(width: 10),
          SecondaryPill(
            label: l.mediaPath == null ? 'Choose' : 'Change',
            height: 36,
            padding: 14,
            onTap: () => _pickMedia(video: l.bg == AlarmBg.video),
          ),
        ]),
      ],
      if (l.bg == AlarmBg.category)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Each alarm glows in its task’s colour: Study blue, Body red, and so on.',
              style: PlannerType.body(size: 12, color: c.t3)),
        ),

      heading('Effects'),
      slider('Blur', l.blur, (l, x) => l.copyWith(blur: x)),
      slider('Dim', l.dim, (l, x) => l.copyWith(dim: x)),
      toggle('Slow zoom', l.zoom, (v) => _edit((l) => l.copyWith(zoom: v)), sub: 'The background drifts in and out'),
      label('Tint'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PlannerChip(
            label: 'None',
            selected: !l.hasTint,
            onTap: () => _edit((l) => l.copyWith(tintCategory: false, tint: null))),
        PlannerChip(
            label: 'Category',
            selected: l.tintCategory,
            onTap: () => _edit((l) => l.copyWith(tintCategory: true, tint: null))),
        for (final t in alarmTints)
          Pressable(
            onTap: () => _edit((l) => l.copyWith(tintCategory: false, tint: t)),
            label: 'Tint colour',
            selected: l.tint == t,
            excludeChildSemantics: true,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color(t),
                shape: BoxShape.circle,
                border: Border.all(color: l.tint == t ? c.tx : c.ln, width: l.tint == t ? 2.5 : 1),
              ),
            ),
          ),
      ]),
      if (l.hasTint) ...[const SizedBox(height: 6), slider('Strength', l.tintStrength, (l, x) => l.copyWith(tintStrength: x))],

      heading('Clock and text'),
      label('Clock size'),
      SegmentedPill<ClockSize>(
        label: 'Clock size',
        options: [for (final s in ClockSize.values) (s, s.label)],
        value: l.size,
        onChanged: (v) => _edit((l) => l.copyWith(size: v)),
        height: 40,
      ),
      label('Clock font'),
      SegmentedPill<ClockFont>(
        label: 'Clock font',
        options: [for (final f in ClockFont.values) (f, f.label)],
        value: l.font,
        onChanged: (v) => _edit((l) => l.copyWith(font: v)),
        height: 40,
      ),
      label('Layout'),
      SegmentedPill<AlarmAlign>(
        label: 'Layout',
        options: const [(AlarmAlign.center, 'Centred'), (AlarmAlign.left, 'Left')],
        value: l.align,
        onChanged: (v) => _edit((l) => l.copyWith(align: v)),
        height: 40,
      ),
      const SizedBox(height: 10),
      toggle('Task name', l.showTitle, (v) => _edit((l) => l.copyWith(showTitle: v))),
      toggle('Start and end time', l.showRange, (v) => _edit((l) => l.copyWith(showRange: v))),
      toggle('What’s next', l.showNext, (v) => _edit((l) => l.copyWith(showNext: v))),
      label('Message'),
      TextField(
        controller: _message,
        maxLength: 60,
        style: PlannerType.body(size: 15, color: c.tx),
        decoration: InputDecoration(
          hintText: 'For example: You’ve got this.',
          hintStyle: PlannerType.body(size: 15, color: c.t3),
          filled: true,
          fillColor: c.s1,
          counterStyle: PlannerType.time(size: 11, color: c.t3),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (v) => _edit((l) => l.copyWith(message: v), save: false),
        onEditingComplete: _save,
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          _save();
        },
      ),
    ];

    final scopeRow = SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        PlannerChip(label: 'Every alarm', selected: _scope == null, onTap: () => _setScope(null)),
        for (final cat in Category.values) ...[
          const SizedBox(width: 8),
          PlannerChip(
            label: _p.overrides.containsKey(cat) ? '${cat.label} •' : cat.label,
            selected: _scope == cat,
            leading: CatSquare(cat.color),
            onTap: () => _setScope(cat),
          ),
        ],
      ]),
    );

    final sound = <Widget>[
      heading('Sound', sub: 'For every alarm'),
      Pressable(
        onTap: _chooseTone,
        label: 'Alarm tone, ${_p.toneName}',
        radius: 4,
        pressedScale: 0.99,
        excludeChildSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(border: Border(top: line)),
          child: Row(children: [
            Expanded(child: Text('Alarm tone', style: PlannerType.ui(14, color: c.tx))),
            Text(_p.toneName, style: PlannerType.body(size: 14, color: c.t2)),
            const SizedBox(width: 6),
            PlannerIcon(PIcon.chev, size: 16, color: c.t3, stroke: 1.6),
          ]),
        ),
      ),
      label('Gentle start'),
      SegmentedPill<int>(
        label: 'Gentle start',
        options: const [(0, 'Off'), (15, '15 s'), (30, '30 s'), (60, '1 min')],
        value: _p.fadeSeconds,
        onChanged: (v) => _update(_p.copyWith(fadeSeconds: v)),
        height: 40,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _p.fadeSeconds == 0
              ? 'Rings at full volume straight away.'
              : 'Vibrates, and the tone rises to full volume over ${_p.fadeSeconds == 60 ? 'a minute' : '${_p.fadeSeconds} seconds'}.',
          style: PlannerType.body(size: 12, color: c.t3),
        ),
      ),
      const SizedBox(height: 8),
      toggle('Vibrate', _p.vibrate, (v) => _update(_p.copyWith(vibrate: v))),

      heading('Answering', sub: 'For every alarm'),
      toggle('Slide to confirm', _p.slide, (v) => _update(_p.copyWith(slide: v)),
          sub: 'Slide right for Done, left to snooze, so a pocket can’t answer it'),
      label('Snooze for'),
      SegmentedPill<int>(
        label: 'Snooze for',
        options: const [(5, '5 min'), (10, '10 min'), (15, '15 min')],
        value: _p.snoozeMinutes,
        onChanged: (v) => _update(_p.copyWith(snoozeMinutes: v)),
        height: 40,
      ),
    ];

    final sample = _sample();
    final preview = AspectRatio(
      aspectRatio: 390 / 800,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FittedBox(
          child: SizedBox(
            width: 390,
            height: 800,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 20, bottom: 12), textScaler: TextScaler.noScaling),
              child: AlarmScreen(alarm: sample, look: l, prefs: _p, preview: true, reduced: reduced),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 52,
            child: Row(children: [
              const SizedBox(width: 8),
              PlannerIconButton(icon: PIcon.back, label: 'Back', onTap: () => ref.read(routerProvider).pop(), color: c.tx, size: 20),
              Expanded(child: Semantics(header: true, child: Text('Alarm screen', style: PlannerType.screenTitle(size: 20, color: c.tx)))),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SecondaryPill(label: 'Ring a test', height: 36, padding: 14, onTap: _test),
              ),
            ]),
          ),
          // Pinned, so every change shows while the editors scroll.
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.34,
              child: Semantics(label: 'Preview of the alarm screen', child: ExcludeSemantics(child: preview)),
            ),
          ),
          Container(height: 1, color: c.ln),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 48),
              children: [
                scopeRow,
                if (!_own) ...[
                  const SizedBox(height: 16),
                  Text('${_scope!.label} alarms use the look for every alarm.',
                      style: PlannerType.body(size: 14, color: c.t2)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PrimaryPill(
                      label: 'Give ${_scope!.label} its own look',
                      onTap: () => _update(_p.withOverride(_scope!, _p.look)),
                    ),
                  ),
                ] else ...[
                  if (_scope != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(children: [
                        Expanded(
                          child: Text('Only ${_scope!.label} alarms look like this.',
                              style: PlannerType.body(size: 13, color: c.t2)),
                        ),
                        TextPill(
                          label: 'Use the shared look',
                          onTap: () {
                            _update(_p.withOverride(_scope!, null));
                            ref.read(alarmMediaProvider).prune(_p);
                          },
                        ),
                      ]),
                    ),
                  ...editors,
                ],
                ...sound,
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _chooseTone() async {
    final platform = ref.read(alarmPlatformProvider);
    final tones = await platform.tones();
    if (!mounted) return;
    final c = PlannerColors.of(context);
    final picked = await showModalBottomSheet<AlarmTone?>(
      context: context,
      backgroundColor: c.s1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _TonePicker(tones: tones, current: _p.toneName, platform: platform),
    );
    await platform.stopPreview();
    if (picked == null) return;
    if (picked.uri.isEmpty) {
      _update(_p.copyWith(tonePath: null, toneName: 'Phone default'));
      return;
    }
    final path = await platform.copyTone(picked);
    if (path == null) {
      ref.read(noteProvider.notifier).say('That tone couldn’t be used. Try another.');
      return;
    }
    _update(_p.copyWith(tonePath: path, toneName: picked.title));
  }
}

class _TonePicker extends StatefulWidget {
  const _TonePicker({required this.tones, required this.current, required this.platform});
  final List<AlarmTone> tones;
  final String current;
  final AlarmPlatform platform;

  @override
  State<_TonePicker> createState() => _TonePickerState();
}

class _TonePickerState extends State<_TonePicker> {
  late String _sel = widget.current;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final all = [const AlarmTone('Phone default', ''), ...widget.tones];
    final sel = all.where((t) => t.title == _sel).firstOrNull ?? all.first;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('Alarm tone', style: PlannerType.sheetTitle(size: 24, color: c.tx)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('Tap to hear it. It plays at alarm volume.', style: PlannerType.body(size: 13, color: c.t3)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final t in all)
                Pressable(
                  onTap: () {
                    setState(() => _sel = t.title);
                    widget.platform.preview(t.uri.isEmpty ? null : t.uri);
                  },
                  label: t.title,
                  selected: t.title == sel.title,
                  radius: 0,
                  pressedScale: 1,
                  excludeChildSemantics: true,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 50),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      Expanded(child: Text(t.title, style: PlannerType.ui(15, color: c.tx))),
                      if (t.title == sel.title) Icon(Icons.check_rounded, size: 20, color: c.tx),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: PrimaryPill(label: 'Use ${sel.title}', expand: true, onTap: () => Navigator.pop(context, sel)),
          ),
        ]),
      ),
    );
  }
}
