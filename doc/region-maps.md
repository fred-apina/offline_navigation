# Region maps: navigation where there is no internet

By default the navigation page downloads the map areas a route needs (up to a few
hundred MB for a large country, see [What gets downloaded](../README.md#what-gets-downloaded)).
For places with poor or no connectivity you can prepare a much smaller map of just
the place you need (a national park, a city, a campus) **ahead of time**, and
navigate there with no network at all. A national park of 13,000 km² becomes about
2 MB.

## Use one in your app

```dart
// 1. Before the trip, with internet. Resumes if interrupted.
await OfflineNavigation.installRegionMap(
  RegionMapSource(
    id: 'serengeti',
    url: Uri.parse('https://maps.example.com/serengeti.mwm'),
    sha256: '<sha-256 of the file, printed by tool/make_region_map.sh>',
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
  so your app decides what to offer.
* **No base world map needed.** With `installedOnly` the page neither requires nor
  downloads the base world map (`World.mwm` and `WorldCoasts.mwm`, 72 MB together).
  The map is drawn from the region you installed and is blank outside it, so use
  this for navigation that stays inside the region. To draw the world around it as
  well, call `OfflineNavigation.ensureBaseMaps()` once while online.
* **Your own downloader?** Hand the finished file to
  `OfflineNavigation.installRegionMapFromFile(id, path, sha256: ..., moveFile: true)`.
* **Manage maps** with `listRegionMaps()`, `isRegionMapInstalled(id)` and
  `removeRegionMap(id)`. Replace a map with `installRegionMap(..., replace: true)`.
* **Errors** are `MapInstallException`s with a `MapInstallError` (`checksumMismatch`,
  `notEnoughSpace`, `downloadFailed`, `unsupportedFormat`, ...). A failed or
  cancelled download keeps its partial file and the next attempt resumes it.

**Both the start and the destination must lie inside installed maps.** A route
from outside the region (for example from the town before the park gate) needs a
map that covers that part as well. Draw the boundary generously, along the access
roads, or install an additional region map.

## Build a region map

`tool/make_region_map.sh` turns a GeoJSON boundary and an OpenStreetMap extract
into the `.mwm` file plus its size and SHA-256:

```sh
tool/make_region_map.sh --id serengeti --boundary serengeti.geojson \
    --osm tanzania-latest.osm.pbf --engine ~/src/organicmaps \
    --build ~/src/omim-build-release --out ./maps
```

It needs `osmium-tool`, Python 3.10+, and the generator tools built from the
Organic Maps source **of the same release as the engine in this plugin**: an
engine rejects maps from a newer generator (`MapInstallError.unsupportedFormat`).
`OfflineNavigation.engineDataVersion` reports the engine's data version. The
script's header explains how to build the tools.

## Host it

Host the file anywhere that serves HTTPS, ideally with `Range` support so large
downloads can resume. Keep `id`, `sizeBytes` and `sha256` in your own catalogue
(for example next to the content your app downloads for that place).
