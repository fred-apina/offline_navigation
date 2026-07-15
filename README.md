# offline_navigation

Drop-in **offline turn-by-turn navigation** for Flutter, powered by the
[Organic Maps](https://organicmaps.app) engine and OpenStreetMap data.

Pass a start and destination; the library takes care of the rest — including
automatically downloading the offline map of the country the route is in:

```dart
final result = await Navigator.push(context, MaterialPageRoute(
  builder: (_) => OfflineNavigationPage(
    start: NavPoint(latitude: -3.3869, longitude: 36.6830, name: 'Arusha Gate'),
    destination: NavPoint(latitude: -3.2379, longitude: 36.8219, name: 'Momella Lakes'),
    travelMode: TravelMode.drive,
    options: NavOptions(voiceGuidance: true),
  ),
));
```

> **Status: Phase 0 spike.** The current code proves the core architecture:
> the Organic Maps map surface rendering inside a Flutter platform view, with
> the engine initialized by the plugin (no custom Application class needed).
> The navigation page API above is the target for v1 and is not implemented yet.
>
> The Android build currently consumes the Organic Maps SDK as a local Gradle
> module (see `example/android/settings.gradle.kts`); a prebuilt AAR on Maven
> replaces this before release.

## Platform support

| Android | iOS |
|---|---|
| ✅ (minSdk 21) | Planned |

## License & attribution

Apache-2.0, built on the [Organic Maps](https://github.com/organicmaps/organicmaps)
engine (Apache-2.0). Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors (ODbL); the map widget shows a permanent attribution notice.
