## 0.3.1 (unreleased)

* **Downloads fixed.** In 0.3.0 every map download started by trying two mirrors
  that answer HTTP 404 for every file (they were the engine's built-in fallback:
  the meta server it asks for a server list answers in a format the engine no
  longer reads). One live server was left, so a single dropped connection failed
  the whole file: on an emulator a 105 MB region took seven retries, and a first
  base-map download failed outright. The engine now uses the five mirrors that
  serve the current data version and no meta server.
* **The page no longer waits for ever** when something asks how much of the base
  map is missing while it downloads (`OfflineNavigation.baseMapsBytesMissing`).
  The engine's query dropped the download in progress without telling anyone; it
  now answers from the download's own counters, on Android and iOS.
* **Ids the engine does not know no longer abort the app.** The calls that take a
  map id from outside now check it first.
* **Show the size before downloading:** `NavOptions(askBeforeDownload: true)`
  lists the areas and their sizes and waits for a confirmation, again if the
  route needs more. The progress screen names the area and its size instead of an
  id.
* **Download ahead of time:** `OfflineNavigation.mapAreaAt`, `mapArea`,
  `planDownload` and `downloadMapArea` (new types `MapArea`, `MapDownloadPlan`,
  `formatMapSize`). The README explains what the default flow downloads: a region
  where the engine splits the country (Tanzania is seven regions of 19 to
  175 MB), otherwise the country. `MapPolicy.autoDownloadCountry` keeps its name;
  its documentation now says "areas".
* Tests: `example/integration_test/map_areas_test.dart`.
* Needs the 0.3.1 Android library (`organicmaps-sdk` 0.3.1) and the engine
  framework rebuilt from the same fork commit.

## 0.3.0 (unreleased)

* **iOS support** (iOS 15.0 or later, arm64 devices and Apple Silicon simulators).
  The same page, the same API and the same behaviour as Android: install region
  maps, preview a route, turn-by-turn guidance with voice, simulated routes. The
  engine ships in the package as `OfflineNavEngine.xcframework` (about 11 MB per
  slice) with its data files in the `offline_navigation_data` bundle; together
  they add about 45 MB to an app. See the README for the `Podfile` and
  `Info.plist` setup.
* **New engine on Android too.** Both platforms now run the current Organic Maps
  engine (data version 260714, released maps built for 260111 keep working: the
  map file format did not change), with our region-map patches ported on top. The
  Android library is now two artifacts, `organicmaps-sdk` and the module it
  depends on, `organicmaps-sdk-location-core`; Gradle fetches both. Apps still
  build with `compileSdk 36` (the library's `okhttp` is held at 5.4.0, 5.5.0 and
  later need 37) and the library contains no Java records, so older Android Gradle
  plugin versions can dex it. The plugin uses the SDK's own location provider
  (Android's location stack, no Google Play Services).
* Engine fixes that came with the move, found by the iOS tests and checked on
  Android too: a map installed while the app runs was unknown to the router (every
  route inside it failed with "start point not found"); removing a map could abort
  the engine; a screen opened a second time got a navigation camera with the car
  near the top of the screen. On iOS, following the route with no map on the
  screen (page still opening, a system dialog, page just closed) aborted the app;
  it now waits for the map.
* `tool/check_preview_framing.sh` also checks the iOS simulator
  (`PLATFORM=ios`).
* Test: removing and reinstalling a region map twice in one session.
* Tests: guidance that follows the device's own location (no simulated drive),
  and `example/lib/background_check.dart`, a standalone app to check guidance and
  voice through Home and a locked phone.

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
