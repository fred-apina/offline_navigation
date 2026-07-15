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
