## 0.3.0 (unreleased)

* **iOS support** (iOS 15.0 or later, arm64 devices and Apple Silicon simulators).
  The same page, the same API and the same behaviour as Android: install region
  maps, preview a route, turn-by-turn guidance with voice, simulated routes. The
  engine ships in the package as `OfflineNavEngine.xcframework` (about 11 MB per
  slice) with its data files in the `offline_navigation_data` bundle; together
  they add about 45 MB to an app. See the README for the `Podfile` and
  `Info.plist` setup.
* `tool/check_preview_framing.sh` also checks the iOS simulator
  (`PLATFORM=ios`).
* Test: removing and reinstalling a region map twice in one session.

## 0.2.2

* Fix the route preview of a short route coming up zoomed far out on the first
  open after the app starts: a blank map with `MapPolicy.installedOnly` and no
  base world map, a tiny world with it. A short route is built before the map
  has a drawing engine, so the engine's zoom to the route was silently dropped.
  The page now builds the route once more when the drawing engine appears, and
  the engine fits it. Routes that were already fitted are untouched.
* The Kotlin unit tests run again. A leftover template test had stopped them
  compiling since the Pigeon migration and is removed; the new logic has tests.
  `tool/check_preview_framing.sh` checks the fix on a device.

## 0.2.1

* `MapPolicy.installedOnly` no longer needs the base world map (`World.mwm` and
  `WorldCoasts.mwm`, 72 MB). In 0.2.0 the page ended with
  `NavigationFailure.mapsMissing` and `OfflineNavigation.baseMapsId` when it
  was absent, so an app that only wants to navigate inside a region it has
  already installed had to download 72 MB first. Now it routes and guides with
  the installed region alone; the map is blank outside it. A route that leaves
  the installed maps still ends with `mapsMissing`, as before. The default
  policy, `autoDownloadCountry`, is unchanged.
* Docs: the base maps are 72 MB, not "a few MB".

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
* Build fix: the plugin now compiles against Android API 36, as current
  `flutter_plugin_android_lifecycle` and AndroidX releases require. Before this,
  a new app failed at `checkReleaseAarMetadata`.
* Release build fix: the plugin now ships the R8/ProGuard keep rule for the
  engine (`-keep class app.organicmaps.sdk.**`). The 0.2.0 engine AAR does not
  carry it, and without it a release build crashed at start-up with
  `NoSuchFieldError ... BookmarkManager ... INSTANCE`.

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
