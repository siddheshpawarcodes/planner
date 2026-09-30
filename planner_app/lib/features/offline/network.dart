import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/ui_state.dart';
import '../../data/backup/sync.dart';

/// The platform's connectivity, overridden in `main`; null in tests, where
/// the debug Network switch drives [onlineProvider] instead.
final connectivityProvider = Provider<Connectivity?>((ref) => null);

/// On Wi-Fi or Ethernet (automatic backups wait for it).
class WifiController extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) {
    if (v != state) state = v;
  }
}

final wifiProvider = NotifierProvider<WifiController, bool>(WifiController.new);

/// Keeps [onlineProvider] and [wifiProvider] current (README 6.12: nothing
/// becomes read-only; offline only shows the LOCAL chip and the Drive row's
/// status), and gives automatic backup its chances: launch, resume and
/// reconnect.
class NetworkHost extends ConsumerStatefulWidget {
  const NetworkHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<NetworkHost> createState() => _NetworkHostState();
}

class _NetworkHostState extends ConsumerState<NetworkHost> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _auto);
    final c = ref.read(connectivityProvider);
    if (c != null) {
      c.checkConnectivity().then(_apply);
      _sub = c.onConnectivityChanged.listen(_apply);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _auto());
  }

  void _apply(List<ConnectivityResult> r) {
    if (!mounted) return;
    final was = ref.read(onlineProvider);
    final online = r.any((x) => x != ConnectivityResult.none);
    ref.read(onlineProvider.notifier).set(online);
    ref.read(wifiProvider.notifier).set(r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet));
    if (online && !was) _auto();
  }

  void _auto() {
    if (!mounted) return;
    ref.read(syncProvider.notifier).autoBackUpIfDue(wifi: ref.read(wifiProvider));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
