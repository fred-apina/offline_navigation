import 'package:flutter/foundation.dart';

import 'messages.g.dart' show WireMapArea;
import 'models.dart' show MapStatus;

/// A downloadable map from the engine's country list: a whole country, or one region of a country that the engine
/// splits.
///
/// Organic Maps splits some large countries into regions so that a trip does not need the whole country. Tanzania,
/// for example, is seven regions (`Tanzania_Northern`, `Tanzania_Lake`, ...) of 19 to 175 MB; most other countries
/// are a single file. Use [OfflineNavigation.mapAreaAt] to find the one that covers a point.
///
/// Not to be confused with the region maps of [OfflineNavigation.installRegionMap], which are files you build and
/// host yourself.
@immutable
class MapArea {
  const MapArea({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.isDownloaded,
  });

  /// The engine's id for the area, for example `Tanzania_Northern`. Pass it to [OfflineNavigation.downloadMapArea].
  final String id;

  /// The engine's display name, for example `Northern`.
  final String name;

  /// Full size of the area's map file, whether or not it is on the device.
  final int sizeBytes;

  /// Whether the area is on the device (and up to date, or only an update is available).
  final bool isDownloaded;

  /// Internal: from the platform channel.
  factory MapArea.fromWire(WireMapArea wire) => MapArea(
        id: wire.id,
        name: wire.name,
        sizeBytes: wire.sizeBytes,
        isDownloaded: MapStatus.isDownloaded(wire.status),
      );

  @override
  bool operator ==(Object other) =>
      other is MapArea &&
      other.id == id &&
      other.name == name &&
      other.sizeBytes == sizeBytes &&
      other.isDownloaded == isDownloaded;

  @override
  int get hashCode => Object.hash(id, name, sizeBytes, isDownloaded);

  @override
  String toString() => 'MapArea($id "$name", ${formatMapSize(sizeBytes)}${isDownloaded ? ', downloaded' : ''})';
}

/// What a trip still needs to download: the map areas at its ends that are not on the device, and the base world
/// map on first run. See [OfflineNavigation.planDownload].
///
/// A long trip can pass through areas between its ends. The page finds out when it builds the route and asks again
/// (with [NavOptions.askBeforeDownload]) for those.
@immutable
class MapDownloadPlan {
  const MapDownloadPlan({required this.areas, this.baseMapsBytes = 0});

  /// The areas still to download.
  final List<MapArea> areas;

  /// Bytes of the base world map (72 MB) still missing; 0 when it is present or was left out of the plan.
  final int baseMapsBytes;

  /// Everything the plan would download.
  int get totalBytes => baseMapsBytes + areas.fold<int>(0, (sum, area) => sum + area.sizeBytes);

  /// True when nothing needs to be downloaded.
  bool get isEmpty => areas.isEmpty && baseMapsBytes <= 0;

  @override
  String toString() =>
      'MapDownloadPlan(${areas.map((a) => a.id).join(', ')}${baseMapsBytes > 0 ? ' + base maps' : ''}: ${formatMapSize(totalBytes)})';
}

/// A size for people: `19 MB`, `104.6 MB`... decimal megabytes, the way the map server lists them; `1.2 GB` from
/// 1000 MB on.
String formatMapSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / 1000000;
  if (mb >= 1000) return '${(mb / 1000).toStringAsFixed(1)} GB';
  if (mb >= 100) return '${mb.round()} MB';
  if (mb >= 10) return '${mb.toStringAsFixed(0)} MB';
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  return '<1 MB';
}
