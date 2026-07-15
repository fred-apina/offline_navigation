# offline_navigation

Drop-in **offline turn-by-turn navigation** for Flutter, powered by the
[Organic Maps](https://organicmaps.app) engine and OpenStreetMap data.

Pass a start and destination; the library takes care of the rest — including
automatically downloading the offline map of the country the route is in:

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

   The native Organic Maps engine is downloaded automatically as a prebuilt
   Android library (~80 MB, one-time) during your next Gradle sync.

2. Enable core library desugaring in `android/app/build.gradle.kts` (required
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

## Permissions

The plugin declares the location permissions it needs (they merge into your
app's manifest automatically) and requests location access at runtime when
turn-by-turn guidance starts. No manifest edits are required on your side.
Simulated guidance (`NavOptions(simulateRoute: true)`) needs no location access,
which is handy for demos and tests.

## Platform support

| Android | iOS |
|---|---|
| ✅ (minSdk 21) | Planned |

## How it works

The Organic Maps map surface is embedded in your widget tree via a platform
view, while all navigation UI (instruction banner, lane hints, ETA bar,
download and preview screens) is drawn in Flutter and fed by native event
streams. The engine — rendering, routing, and map management — is the same
C++ core that powers the Organic Maps app, consumed as a prebuilt AAR
(`io.github.fred-apina:organicmaps-sdk`).

## License & attribution

Apache-2.0, built on the [Organic Maps](https://github.com/organicmaps/organicmaps)
engine (Apache-2.0). Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors (ODbL); the map widget shows a permanent attribution notice.
