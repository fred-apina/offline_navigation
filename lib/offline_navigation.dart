/// Drop-in offline turn-by-turn navigation for Flutter, powered by the
/// [Organic Maps](https://organicmaps.app) engine and OpenStreetMap data.
///
/// Push an [OfflineNavigationPage] onto your navigator with a start and
/// destination; it downloads the required country map if missing, builds the
/// route, shows a preview, then guides turn-by-turn — all fully offline after
/// the one-time map download — and pops with a [NavigationResult]:
///
/// ```dart
/// final result = await Navigator.push<NavigationResult>(
///   context,
///   MaterialPageRoute(
///     builder: (_) => OfflineNavigationPage(
///       start: const NavPoint(latitude: -6.1722, longitude: 35.7395, name: 'Dodoma'),
///       destination: const NavPoint(latitude: -6.1841, longitude: 35.9297, name: 'UDOM'),
///       travelMode: TravelMode.drive,
///       options: const NavOptions(voiceGuidance: true),
///     ),
///   ),
/// );
/// ```
///
/// See [OfflineNavigationPage] for the full page, [OfflineMapView] for the bare
/// map widget, and [OfflineNavigation] to warm the engine up ahead of time.
library;

export 'src/engine.dart' show OfflineNavigation;
export 'src/map_view.dart' show OfflineMapView;
export 'src/models.dart'
    show
        NavPoint,
        TravelMode,
        NavOptions,
        NavigationOutcome,
        NavigationResult,
        RouteSummary;
export 'src/navigation_page.dart' show OfflineNavigationPage;
