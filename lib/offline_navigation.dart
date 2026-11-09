/// Drop-in offline turn-by-turn navigation for Flutter, powered by the
/// [Organic Maps](https://organicmaps.app) engine and OpenStreetMap data.
///
/// Push an [OfflineNavigationPage] onto your navigator with a start and
/// destination; it downloads the map areas the trip needs if they are missing
/// (a region of a country where the engine splits it, otherwise the country),
/// builds the route, shows a preview, then guides turn-by-turn — all fully
/// offline after the one-time map download — and pops with a
/// [NavigationResult]:
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
export 'src/map_areas.dart' show MapArea, MapDownloadPlan, formatMapSize;
export 'src/map_view.dart' show OfflineMapView;
export 'src/models.dart'
    show
        NavPoint,
        TravelMode,
        NavOptions,
        MapPolicy,
        NavigationOutcome,
        NavigationFailure,
        NavigationResult,
        RouteSummary;
export 'src/region_map_download.dart' show HttpClientFactory;
export 'src/region_maps.dart'
    show
        RegionMapSource,
        RegionMapInfo,
        MapInstallProgress,
        MapInstallCancelToken,
        MapInstallException,
        MapInstallError,
        isValidRegionMapId;
export 'src/navigation_page.dart' show OfflineNavigationPage;
