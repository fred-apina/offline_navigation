## 0.2.0

Region maps: navigate in places with no internet using a small map of just the
area you need, prepared ahead of time. Everything is additive; apps that change
nothing behave exactly as in 0.1.x.

* `OfflineNavigation.installRegionMap` downloads a map file (resumable, SHA-256
  and size checked, free space checked) and installs it. The engine uses it
  immediately, with no restart, and finds it again on every later start.
  `installRegionMapFromFile` installs a file your app already has.
  `listRegionMaps`, `isRegionMapInstalled`, `removeRegionMap`.
* `OfflineNavigation.ensureBaseMaps` and `baseMapsBytesMissing` to prepare the
  base world map ahead of time; `engineDataVersion` to match map files to the
  engine.
* `NavOptions.mapPolicy`: `MapPolicy.installedOnly` never uses the network for
  map data; missing maps end the page with `NavigationFailure.mapsMissing`.
* `NavigationResult` carries a typed `failure` and the `missingMaps`
  (`NavigationResult.failed`); the existing constructor is unchanged.
* `tool/make_region_map.sh` builds a region map from a GeoJSON boundary and an
  OpenStreetMap extract.
* Requires engine AAR `organicmaps-sdk` 0.2.0: runtime registration of custom
  maps; custom maps are known to routing; the router is rebuilt when they
  change; fixes an engine abort when a map that is not in the country list has
  the current data version.

## 0.1.1

* Fix consumer builds failing with a D8 record-desugaring error
  (`Attempt to create a global synthetic for 'Record desugaring'...`) in apps
  using the default `flutter create` Java 11 compile options. The engine AAR
  (0.1.1) no longer contains Java records.

## 0.1.0

First public release.

* `OfflineNavigationPage`: a self-contained offline turn-by-turn navigation
  page. Pass a start and destination; it initializes the engine, downloads the
  required country map (and the base world map on first run) with progress UI,
  builds the route, shows a preview with distance/ETA, then guides turn-by-turn
  with voice instructions, and pops with a `NavigationResult`.
* Travel modes: drive, walk, cycle.
* Route preview with a Start button; optional voice guidance; optional route
  simulation for demos and tests.
* Automatic recovery when a route crosses regions whose maps aren't downloaded.
* Location permission requested in-page; graceful handling of denial.
* Android only (minSdk 21). The Organic Maps engine is consumed as a prebuilt
  AAR; consumer apps are auto-configured for asset packaging.
* Typed platform channels (Pigeon).

## 0.0.1

* Phase 0 spike: Organic Maps engine initialization from the plugin and map
  rendering inside a Flutter platform view (hybrid composition). Android only.
