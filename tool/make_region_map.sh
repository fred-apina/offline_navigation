#!/usr/bin/env bash
#
# Builds a *region map* for offline_navigation: an Organic Maps .mwm file that
# covers one area (a national park, a city, a campus...) instead of a whole
# country, plus the id, size and SHA-256 you need to host and install it.
#
#   tool/make_region_map.sh \
#       --id serengeti \
#       --boundary serengeti.geojson \
#       --osm tanzania-latest.osm.pbf \
#       --engine ~/src/organicmaps \
#       --build  ~/src/omim-build-release \
#       --out    ./maps
#
# Inputs
#   --id        Region id; also the file name (<id>.mwm). [A-Za-z0-9_-], 1-64 chars.
#   --boundary  GeoJSON with the area: a Polygon/MultiPolygon geometry, a Feature
#               or a FeatureCollection. Draw one at https://geojson.io, or take
#               an administrative boundary from OpenStreetMap.
#   --osm       OpenStreetMap extract (.osm.pbf) that contains the area, e.g. a
#               country from https://download.geofabrik.de. Only the area is kept.
#   --engine    Organic Maps source checkout the plugin's engine was built from.
#   --build     Directory containing the built generator_tool and mwm_diff_tool
#               (see "Prerequisites").
#   --out       Output directory (default: ./region_maps).
#   --python    Python >= 3.10 (default: python3.12, python3.11, python3.10, python3).
#
# Output (in --out)
#   <id>.mwm          the map file
#   <id>.json         {"id", "sizeBytes", "sha256", "dataVersion"}, ready to host
#                     next to the file and to feed to RegionMapSource
#
# Prerequisites
#   * osmium-tool            (brew install osmium-tool / apt install osmium-tool)
#   * Python >= 3.10
#   * generator_tool and mwm_diff_tool, built from --engine at the SAME release
#     the offline_navigation engine (the organicmaps-sdk AAR) was built from.
#     A map built by a newer generator is rejected by the engine. From --engine:
#       ./tools/unix/build_omim.sh -r -p <dir> generator_tool mwm_diff_tool
#     (on macOS this needs Qt 6: brew install cmake ninja qt@6)
#
# The script only reads --engine; everything else happens in a work directory
# under --out, which is kept so reruns and --osm extracts are cheap.
set -euo pipefail

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
die() { echo "error: $*" >&2; exit 1; }

ID= BOUNDARY= OSM= ENGINE= BUILD= OUT=./region_maps PYTHON_BIN=
while [ $# -gt 0 ]; do
  case "$1" in
    --id) ID=${2:?}; shift 2 ;;
    --boundary) BOUNDARY=${2:?}; shift 2 ;;
    --osm) OSM=${2:?}; shift 2 ;;
    --engine) ENGINE=${2:?}; shift 2 ;;
    --build) BUILD=${2:?}; shift 2 ;;
    --out) OUT=${2:?}; shift 2 ;;
    --python) PYTHON_BIN=${2:?}; shift 2 ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$ID" ] && [ -n "$BOUNDARY" ] && [ -n "$OSM" ] && [ -n "$ENGINE" ] && [ -n "$BUILD" ] || usage 1
[[ "$ID" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || die "--id must match [A-Za-z0-9_-]{1,64}"
[ -f "$BOUNDARY" ] || die "no such file: $BOUNDARY"
[ -f "$OSM" ] || die "no such file: $OSM"
[ -f "$ENGINE/tools/python/maps_generator/__main__.py" ] || die "$ENGINE is not an Organic Maps checkout"
[ -x "$BUILD/generator_tool" ] || die "generator_tool not found in $BUILD"
[ -x "$BUILD/mwm_diff_tool" ] || die "mwm_diff_tool not found in $BUILD"
command -v osmium >/dev/null || die "osmium is not installed (brew install osmium-tool)"

if [ -z "$PYTHON_BIN" ]; then
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null &&
       "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
      PYTHON_BIN=$candidate; break
    fi
  done
fi
[ -n "$PYTHON_BIN" ] || die "Python >= 3.10 is required (the generator's pinned dependencies need it)"
"$PYTHON_BIN" -c 'import sys; sys.exit(sys.version_info < (3, 10))' || die "$PYTHON_BIN is older than 3.10"

abspath() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd -P)
BOUNDARY=$(abspath "$BOUNDARY"); OSM=$(abspath "$OSM")
ENGINE=$(cd "$ENGINE" && pwd -P); BUILD=$(cd "$BUILD" && pwd -P)

WORK="$OUT/.work-$ID"
rm -rf "$WORK/gen" "$WORK/data"
mkdir -p "$WORK/gen" "$WORK/data/borders"

echo "==> 1/5 cutting $ID out of $(basename "$OSM")"
osmium extract --overwrite -p "$BOUNDARY" "$OSM" -o "$WORK/$ID.osm.pbf"

echo "==> 2/5 writing the border polygon"
"$PYTHON_BIN" -I - "$BOUNDARY" "$WORK/data/borders/$ID.poly" "$ID" <<'PY'
import json, sys

src, dst, name = sys.argv[1:4]
doc = json.load(open(src))

def geometries(node):
    kind = node.get("type")
    if kind == "FeatureCollection":
        for feature in node["features"]:
            yield from geometries(feature)
    elif kind == "Feature":
        yield from geometries(node["geometry"])
    elif kind == "Polygon":
        yield [node["coordinates"]]
    elif kind == "MultiPolygon":
        yield node["coordinates"]
    elif kind == "GeometryCollection":
        for geometry in node["geometries"]:
            yield from geometries(geometry)

polygons = [polygon for group in geometries(doc) for polygon in group]
if not polygons:
    sys.exit("the boundary contains no Polygon or MultiPolygon")

with open(dst, "w") as out:
    out.write(name + "\n")
    section = 0
    for polygon in polygons:
        for index, ring in enumerate(polygon):
            section += 1
            # The outer ring first; the following rings are holes ("!" prefix).
            out.write(("!" if index else "") + str(section) + "\n")
            for lon, lat in ring:
                out.write("\t%.6E\t%.6E\n" % (lon, lat))
            out.write("END\n")
    out.write("END\n")
print("  %d ring(s)" % section)
PY

echo "==> 3/5 preparing the generator"
for entry in "$ENGINE"/data/*; do
  [ "$(basename "$entry")" = borders ] || ln -s "$entry" "$WORK/data/$(basename "$entry")"
done
printf '# Mwm name\tGeneration time\n%s\t1\n' "$ID" > "$WORK/order.txt"
( cd "$WORK" && md5sum "$ID.osm.pbf" 2>/dev/null || md5 -r "$ID.osm.pbf" ) \
  | awk -v f="$ID.osm.pbf" '{print $1"  "f}' > "$WORK/$ID.osm.pbf.md5"
cat > "$WORK/generator.ini" <<INI
[Developer]
OMIM_PATH: $ENGINE
BUILD_PATH: $BUILD
[Main]
DEBUG: 0
MAIN_OUT_PATH: $WORK/gen
[Generator tool]
USER_RESOURCE_PATH: $WORK/data
THREADS_COUNT_FEATURES_STAGE: 0
[Osm tools]
OSM_TOOLS_PATH: $WORK/osmctools
OSM_TOOLS_SRC_PATH: $ENGINE/tools/osmctools
[Logging]
LOG_FILE_PATH: $WORK/gen/generation.log
[External]
PLANET_URL: file://$WORK/$ID.osm.pbf
PLANET_MD5_URL: file://$WORK/$ID.osm.pbf.md5
NEED_BUILD_WORLD_ROADS: false
[Stages]
NEED_PLANET_UPDATE: 0
DATA_ARCHIVE_DIR: $WORK/data
DIFF_VERSION_DEPTH: 2
[Common]
THREADS_COUNT: 0
[Stats]
STATS_TYPES_CONFIG: $ENGINE/tools/python/maps_generator/var/etc/stats_types_config.txt
INI

VENV="$OUT/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  echo "    creating a Python environment (once)"
  "$PYTHON_BIN" -m venv "$VENV"
  "$VENV/bin/pip" install --quiet -r "$ENGINE/tools/python/maps_generator/requirements_dev.txt"
fi

echo "==> 4/5 generating the map (this takes seconds to minutes)"
( cd "$ENGINE/tools/python" &&
  MM_GEN__CONFIG="$WORK/generator.ini" PYTHONDONTWRITEBYTECODE=1 \
  "$VENV/bin/python" -m maps_generator \
    --countries="$ID" --skip="Coastline" --without_countries="World*" \
    --order="$WORK/order.txt" --suffix=region ) > "$WORK/generator.log" 2>&1 \
  || { tail -30 "$WORK/generator.log" >&2; die "map generation failed; full log: $WORK/generator.log"; }

MWM=$(find "$WORK/gen" -type f -name "$ID.mwm" -path '*/[0-9][0-9][0-9][0-9][0-9][0-9]/*' | sort | tail -1)
[ -n "$MWM" ] || die "the generator produced no $ID.mwm; see $WORK/generator.log"

echo "==> 5/5 writing the result"
cp "$MWM" "$OUT/$ID.mwm"
SIZE=$("$PYTHON_BIN" -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$OUT/$ID.mwm")
SHA=$("$PYTHON_BIN" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$OUT/$ID.mwm")
DATA_VERSION=$(grep -m1 -o '"v": *[0-9]*' "$ENGINE/data/countries.txt" | grep -o '[0-9]*$' || true)
cat > "$OUT/$ID.json" <<JSON
{
  "id": "$ID",
  "sizeBytes": $SIZE,
  "sha256": "$SHA",
  "dataVersion": "${DATA_VERSION:-unknown}"
}
JSON

echo
echo "Done: $OUT/$ID.mwm  ($SIZE bytes)"
cat "$OUT/$ID.json"
echo
echo "Host $ID.mwm somewhere reachable over HTTPS and install it with:"
echo "  OfflineNavigation.installRegionMap(RegionMapSource(id: '$ID', url: Uri.parse('<url>'),"
echo "      sha256: '$SHA', sizeBytes: $SIZE));"
echo "It only works with an engine built from the same release as the generator"
echo "(data version ${DATA_VERSION:-unknown}); check OfflineNavigation.engineDataVersion."
