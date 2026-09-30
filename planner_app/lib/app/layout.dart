import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Responsive layouts (README 8): phone under 600, tablet from 600 (left
/// rail, Today pane, Plan board), desktop from 1024 (sidebar, week planner,
/// Today rail). All three render from the same state and functions.
///
/// The README's Tablet board is an iPad in landscape at 1194 wide, so on
/// touch platforms (iOS, Android) wide windows stay tablet; the desktop
/// layout is for desktop platforms and the web.
enum LayoutKind {
  phone,
  tablet,
  desktop;

  bool get wide => this != phone;

  static LayoutKind forWidth(double w, {bool? desktopPlatform}) {
    if (w < 600) return phone;
    final desk = desktopPlatform ??
        (kIsWeb ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return w >= 1024 && desk ? desktop : tablet;
  }
}

/// Publishes the layout for the current window size.
class PlannerLayout extends InheritedWidget {
  const PlannerLayout({super.key, required this.kind, required super.child});
  final LayoutKind kind;

  static LayoutKind of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlannerLayout>()?.kind ?? LayoutKind.phone;

  @override
  bool updateShouldNotify(PlannerLayout old) => kind != old.kind;
}

/// Tablet rail and desktop sidebar widths, and the Today pane or rail.
const kRailWidth = 84.0;
const kSidebarWidth = 232.0;
const kTabletTodayWidth = 380.0;
const kDesktopTodayWidth = 400.0;
