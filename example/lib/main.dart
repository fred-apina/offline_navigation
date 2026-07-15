import 'package:flutter/material.dart';
import 'package:offline_navigation/offline_navigation.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offline_navigation demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const DemoHome(),
    );
  }
}

/// A preset A→B trip for the demo picker.
class _Trip {
  const _Trip(this.label, this.start, this.destination);
  final String label;
  final NavPoint start;
  final NavPoint destination;
}

const _trips = <_Trip>[
  _Trip(
    'Zürich HB → ETH Zürich',
    NavPoint(latitude: 47.3779, longitude: 8.5403, name: 'Zürich HB'),
    NavPoint(latitude: 47.3763, longitude: 8.5476, name: 'ETH Zürich'),
  ),
  _Trip(
    'Arusha → Usa River',
    NavPoint(latitude: -3.3869, longitude: 36.6830, name: 'Arusha'),
    NavPoint(latitude: -3.3689, longitude: 36.8286, name: 'Usa River'),
  ),
];

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  _Trip _trip = _trips.first;
  TravelMode _mode = TravelMode.drive;
  bool _voice = true;
  bool _simulate = true; // On by default so the demo works without real GPS.
  NavigationResult? _lastResult;

  Future<void> _navigate() async {
    final result = await Navigator.of(context).push<NavigationResult>(
      MaterialPageRoute(
        builder: (_) => OfflineNavigationPage(
          start: _trip.start,
          destination: _trip.destination,
          travelMode: _mode,
          options: NavOptions(voiceGuidance: _voice, simulateRoute: _simulate),
        ),
      ),
    );
    if (mounted) setState(() => _lastResult = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('offline_navigation demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Route', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final trip in _trips)
            ListTile(
              leading: Icon(
                _trip == trip
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _trip == trip ? Theme.of(context).colorScheme.primary : null,
              ),
              title: Text(trip.label),
              subtitle: Text('${trip.start.name} → ${trip.destination.name}'),
              onTap: () => setState(() => _trip = trip),
            ),
          const Divider(height: 32),
          Text('Travel mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<TravelMode>(
            segments: const [
              ButtonSegment(value: TravelMode.drive, icon: Icon(Icons.directions_car), label: Text('Drive')),
              ButtonSegment(value: TravelMode.walk, icon: Icon(Icons.directions_walk), label: Text('Walk')),
              ButtonSegment(value: TravelMode.cycle, icon: Icon(Icons.directions_bike), label: Text('Cycle')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Voice guidance'),
            value: _voice,
            onChanged: (v) => setState(() => _voice = v),
          ),
          SwitchListTile(
            title: const Text('Simulate movement'),
            subtitle: const Text('Drive the route automatically (no real GPS needed)'),
            value: _simulate,
            onChanged: (v) => setState(() => _simulate = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _navigate,
            icon: const Icon(Icons.navigation),
            label: const Text('Start offline navigation'),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: Icon(switch (_lastResult!.outcome) {
                  NavigationOutcome.arrived => Icons.check_circle,
                  NavigationOutcome.cancelledByUser => Icons.cancel,
                  NavigationOutcome.failed => Icons.error,
                }),
                title: Text('Last result: ${_lastResult!.outcome.name}'),
                subtitle: _lastResult!.message == null ? null : Text(_lastResult!.message!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
