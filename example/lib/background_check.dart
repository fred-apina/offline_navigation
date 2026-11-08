// Manual check that guidance survives the app leaving the screen (Home, locked phone) and comes back.
//
// Why a separate app and not an integration test: `flutter test` talks to the phone over a debug link that drops when
// the phone locks, and then ends the test and kills the app. This one runs on its own, in release mode.
//
//   flutter build ios --release -t lib/background_check.dart
//
// then install it, copy the region map into the app's Documents folder as serengeti.mwm
//
//   xcrun devicectl device copy to --device <udid> --source serengeti.mwm --destination Documents/serengeti.mwm \
//     --domain-type appDataContainer --domain-identifier <bundle id>
//
// open the app, tap "Start navigation", press Home, lock the phone, wait, unlock and open the app again.
// The app writes Documents/background_check.log: every lifecycle change and a heartbeat every 5 seconds. Read it with
// `xcrun devicectl device copy from ... --source Documents/background_check.log`. The heartbeat has to continue through
// the locked time, and the voice has to keep speaking turn instructions.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:offline_navigation/offline_navigation.dart';

const _id = 'serengeti';
const _seronera = NavPoint(latitude: -2.4467, longitude: 34.8191, name: 'Seronera');
const _viboko = NavPoint(latitude: -2.4935686, longitude: 34.8302072, name: 'Bwawa La Viboko Vya Naabi');

File get _logFile => File('${Directory.systemTemp.parent.path}/Documents/background_check.log');

void _log(String message) {
  final line = '${DateTime.now().toIso8601String()} $message\n';
  debugPrint(line.trimRight());
  try {
    _logFile.writeAsStringSync(line, mode: FileMode.append, flush: true);
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Check()));
}

class _Check extends StatefulWidget {
  const _Check();

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> with WidgetsBindingObserver {
  Timer? _heartbeat;
  String _status = 'Starting…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _logFile.writeAsStringSync('');
    } catch (_) {}
    _log('app started');
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _log('heartbeat'));
    _start();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _log('lifecycle $state');

  Future<void> _start() async {
    try {
      await OfflineNavigation.initialize();
      if (!await OfflineNavigation.isRegionMapInstalled(_id)) {
        final file = '${Directory.systemTemp.parent.path}/Documents/serengeti.mwm';
        _log('installing the region map from $file');
        await OfflineNavigation.installRegionMapFromFile(_id, file);
      }
      _log('engine ready, region map installed');
      if (!mounted) return;
      setState(() => _status = 'Ready');
      final result = await Navigator.of(context).push<NavigationResult>(MaterialPageRoute(
        builder: (_) => const OfflineNavigationPage(
          start: _seronera,
          destination: _viboko,
          options: NavOptions(mapPolicy: MapPolicy.installedOnly, simulateRoute: true),
        ),
      ));
      _log('page closed: ${result?.outcome}');
      if (mounted) setState(() => _status = 'Page closed: ${result?.outcome}');
    } catch (e) {
      _log('FAILED: $e');
      if (mounted) setState(() => _status = 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(_status)));
}
