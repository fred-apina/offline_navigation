# offline_navigation

Drop-in **offline turn-by-turn navigation** for Flutter, powered by the
[Organic Maps](https://organicmaps.app) engine and OpenStreetMap data.

Pass a start and destination; the library takes care of the rest — including
automatically downloading the offline map the route needs, which is a region
of a country where Organic Maps splits it (Tanzania is seven regions of 19 to
175 MB) and the country otherwise (or, for places without internet, using a
small [region map](#region-maps-navigation-where-there-is-no-internet) you
installed beforehand):

```dart
final result = await Navigator.push(context, MaterialPageRoute(
  builder: (_) => OfflineNavigationPage(
    start: NavPoint(latitude: -6.1722, longitude: 35.7395, name: 'Dodoma City'),
    destination: NavPoint(latitude: -6.1841, longitude: 35.9297, name: 'University of Dodoma'),
    travelMode: TravelMode.drive,
    options: NavOptions(voiceGuidance: true),
  ),
));
// result.outcome: arrived | cancelledByUser | failed
```

The navigation page manages its own flow — engine initialization, map
download with progress UI, route preview with distance/ETA, then live
turn-by-turn guidance with voice instructions — and pops back to your app
with a `NavigationResult` when done. Everything after the map download works
fully offline.

## Installation

1. Add the dependency:

   ```sh
   flutter pub add offline_navigation
   ```

   The native Organic Maps engine comes with the package on iOS (an XCFramework
   and its data files, about 45 MB added to your app) and is downloaded
   automatically as a prebuilt Android library (~80 MB, one-time) during your
   next Gradle sync.

### Android

Enable core library desugaring in `android/app/build.gradle.kts` (required
by the engine on `minSdkVersion < 26`; the build fails with instructions if
it is missing):

   ```kotlin
   android {
     compileOptions {
       isCoreLibraryDesugaringEnabled = true
     }
   }
   dependencies {
     coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
   }
   ```

That's it. Asset packaging (`noCompress`) is configured automatically.

### iOS

Needs iOS 15.0 or later. In `ios/Podfile` set the platform and, with Xcode 27,
the deployment target of all pods (some pods still declare an older one that
Xcode now rejects):

```ruby
platform :ios, '15.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
```

Add the location usage text to `ios/Runner/Info.plist` (without it iOS never
shows the permission prompt, so guidance cannot use the GPS):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your position is shown on the map and used for turn-by-turn directions.</string>
```

To keep guiding when the screen is locked or the app is in the background, also
add the `location` background mode (the plugin turns background updates on only
when the app declares it) and the `audio` mode, which lets the spoken turn
instructions play with the screen locked:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>audio</string>
</array>
```

The location mode is what keeps the app running while it guides, so it applies
to real guidance. A simulated drive (`simulateRoute: true`) has no location
updates to keep it alive: iOS suspends the app a few seconds after it leaves the
screen, and the drive carries on from where it was when the app comes back.

The iOS simulator runs on Apple Silicon (arm64) only; there is no Intel
simulator slice.

## Permissions

On Android the plugin declares the location permissions it needs (they merge
into your app's manifest automatically); on iOS see the `Info.plist` key
above. Location access is requested at runtime when turn-by-turn guidance
starts. Simulated guidance (`NavOptions(simulateRoute: true)`) needs no
location access, which is handy for demos and tests.

## Platform support

| Android | iOS |
|---|---|
| ✅ (minSdk 21) | ✅ (iOS 15.0, arm64 devices and Apple Silicon simulators) |

## How it works

The Organic Maps map surface is embedded in your widget tree via a platform
view, while all navigation UI (instruction banner, lane hints, ETA bar,
download and preview screens) is drawn in Flutter and fed by native event
streams. The engine — rendering, routing, and map management — is the same
C++ core that powers the Organic Maps app, consumed as a prebuilt AAR on
Android (`io.github.fred-apina:organicmaps-sdk`) and as a prebuilt XCFramework
(`OfflineNavEngine`) on iOS. Both are built from the same engine fork.

## What gets downloaded

By default (`MapPolicy.autoDownloadCountry`) the page downloads what the route
needs, and nothing else:

* the **map area** each end of the route is in. Organic Maps splits some large
  countries into regions, so a trip inside one region does not need the country:
  Tanzania is seven regions (Northern 105 MB, Coastal 123 MB, Lake 175 MB, ...),
  against 585 MB for the whole country in older map data. Most other countries
  are still a single file (Kenya 296 MB, Uganda 339 MB). A route that runs into
  another area makes the page download that one too and carry on.
* the **base world map**, 72 MB, once. It draws the world around the areas.

(The policy is called `autoDownloadCountry` for compatibility; it downloads
areas.) Measured on an emulator: Arusha to Moshi downloaded 177 MB (base map and
Northern), then Arusha to Dar es Salaam added only Coastal, 123 MB.

**Show the size first.** `NavOptions(askBeforeDownload: true)` makes the page
list the areas and their sizes and wait for a "Download" before it fetches
anything; Cancel closes the page with `NavigationOutcome.cancelledByUser`. It
asks again if the route turns out to need another area.

**Your own screen**, or downloading ahead of time (the Wi-Fi at the hotel, before
the trip):

```dart
// What would this trip download? Nothing is downloaded by asking.
final plan = await OfflineNavigation.planDownload(start: arusha, destination: moshi);
print('${plan.areas.map((a) => '${a.name} ${formatMapSize(a.sizeBytes)}')}, '
    'base map ${formatMapSize(plan.baseMapsBytes)}, total ${formatMapSize(plan.totalBytes)}');

// Which area is this point in? "Download Northern Tanzania" next to a park:
final area = await OfflineNavigation.mapAreaAt(-3.3869, 36.6830);
if (area != null && !area.isDownloaded) {
  await OfflineNavigation.downloadMapArea(
    area.id,
    onProgress: (p) => print('${((p.fraction ?? 0) * 100).round()} %'),
    cancelToken: token, // optional
  );
}
await OfflineNavigation.ensureBaseMaps(); // the 72 MB base map, if you want it
```

Then open the page with `MapPolicy.installedOnly` for a guarantee that it never
uses the network. Do not run these while an `OfflineNavigationPage` is
downloading: they share the engine's one download-progress stream.

## Region maps: navigation where there is no internet

By default the page downloads the map areas a route needs (see above; up to a
few hundred MB for a large country). For places with poor or no connectivity
you can prepare a much smaller map of just the place you need — a national park,
a city, a campus — **ahead of time**, and navigate there with no network at all.

```dart
// 1. Before the trip, with internet. Resumes if interrupted.
await OfflineNavigation.installRegionMap(
  RegionMapSource(
    id: 'serengeti',
    url: Uri.parse('https://maps.example.com/serengeti.mwm'),
    sha256: '539469244b52c0c8ac42852de30c7f1ce2956a328471ad2e8822a5b1fd3139dc',
    sizeBytes: 2149600,
  ),
  onProgress: (p) => setState(() => progress = p.fraction),
);

// 2. In the area, with no internet.
final result = await Navigator.push<NavigationResult>(
  context,
  MaterialPageRoute(
    builder: (_) => OfflineNavigationPage(
      start: here,
      destination: camp,
      options: const NavOptions(mapPolicy: MapPolicy.installedOnly),
    ),
  ),
);
if (result?.failure == NavigationFailure.mapsMissing) {
  // The installed maps do not cover this route: offer to download one.
}
```

* **The map is used immediately.** Installing registers the file with the running
  engine; no app restart is needed, and it is found again on every later start.
* **`MapPolicy.installedOnly`** guarantees the page never uses the network. If
  something the route needs is missing, the page closes at once with
  `NavigationFailure.mapsMissing` and the ids in `NavigationResult.missingMaps`,
  so your app decides what to offer. The default,
  `MapPolicy.autoDownloadCountry`, behaves as in 0.1.x.
* **No base world map needed (0.2.1).** With `installedOnly` the page neither
  requires nor downloads the base world map (`World.mwm` and `WorldCoasts.mwm`,
  72 MB together). The map is drawn from the region you installed and is blank
  outside it, so use this for navigation that stays inside the region. To draw
  the world around it as well, call `OfflineNavigation.ensureBaseMaps()` once
  while online.
* **Your own downloader?** Hand the finished file to
  `OfflineNavigation.installRegionMapFromFile(id, path, sha256: ..., moveFile: true)`.
* **Manage maps** with `listRegionMaps()`, `isRegionMapInstalled(id)` and
  `removeRegionMap(id)`. Replace a map with `installRegionMap(..., replace: true)`.
* **Errors** are `MapInstallException`s with a `MapInstallError` (`checksumMismatch`,
  `notEnoughSpace`, `downloadFailed`, `unsupportedFormat`, ...). A failed or
  cancelled download keeps its partial file and the next attempt resumes it.

**Both the start and the destination must lie inside installed maps.** A route
from outside the region (for example from the town before the park gate) needs a
map that covers that part as well — draw the boundary generously, along the
access roads, or install an additional region map.

### Building a region map

`tool/make_region_map.sh` turns a GeoJSON boundary and an OpenStreetMap extract
into the `.mwm` file plus its size and SHA-256:

```sh
tool/make_region_map.sh --id serengeti --boundary serengeti.geojson \
    --osm tanzania-latest.osm.pbf --engine ~/src/organicmaps \
    --build ~/src/omim-build-release --out ./maps
```

It needs `osmium-tool`, Python 3.10+, and the generator tools built from the
Organic Maps source **of the same release as the engine in this plugin** — an
engine rejects maps from a newer generator (`MapInstallError.unsupportedFormat`).
`OfflineNavigation.engineDataVersion` reports the engine's data version. The
script's header explains how to build the tools. A national park of 13,000 km²
becomes about 2 MB.

Host the file anywhere that serves HTTPS, ideally with `Range` support so large
downloads can resume. Keep `id`, `sizeBytes` and `sha256` in your own catalogue
(for example next to the content your app downloads for that place).

## License & attribution

Apache-2.0, built on the [Organic Maps](https://github.com/organicmaps/organicmaps)
engine (Apache-2.0). Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors (ODbL); the map widget shows a permanent attribution notice.
