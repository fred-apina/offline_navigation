#!/usr/bin/env bash
# Checks, on a running Android emulator or device, that the route preview of a
# SHORT route is drawn on the very first open after the app starts.
#
# Background: a short route is built before the map of a freshly opened page has
# a drawing engine, so the engine used to skip its zoom to the route and the
# preview came up zoomed far out (blank without the base world map).
#
# It runs example/integration_test/region_maps_test.dart with no base world map
# and with the network switched off, takes a screenshot when the short route's
# preview is up (the test prints SHORT_PREVIEW_READY), and checks that the map
# area is drawn and not one flat colour.
#
# Needs: adb, flutter and python3 on the PATH, a running emulator or device, and
# a folder with serengeti.mwm. If Gradle cannot use your default JDK, set
# JAVA_HOME or org.gradle.java.home in example/android/gradle.properties.
#
#   DEVICE       adb serial (default emulator-5554)
#   REGION_DIR   folder with serengeti.mwm (default ~/Development/napa-region-maps/hosting/260111)
#   BLANK_ABOVE  a map area with more than this share of one colour counts as
#                blank (default 0.95)
#   KEEP_SHOT    a file to copy the screenshot to, to look at it yourself
#
#   SKIP_BASE_MAPS  true (default) never fetches the base world map, which is the
#                   case where a blank preview is blank; false installs it first
#
# Exit status: 0 the preview is drawn and every test passed, 1 the preview is
# blank, 2 the test did not get far enough to tell, 3 a test failed.
set -u

DEVICE="${DEVICE:-emulator-5554}"
REGION_DIR="${REGION_DIR:-$HOME/Development/napa-region-maps/hosting/260111}"
BLANK_ABOVE="${BLANK_ABOVE:-0.95}"
SKIP_BASE_MAPS="${SKIP_BASE_MAPS:-true}"
MWM="$REGION_DIR/serengeti.mwm"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

[ -f "$MWM" ] || { echo "missing $MWM (set REGION_DIR)" >&2; exit 2; }
SHA="$(shasum -a 256 "$MWM" | cut -d' ' -f1)"
SIZE="$(wc -c < "$MWM" | tr -d ' ')"

W="$(mktemp -d)"
LOG="$W/test.log"
SHOT="$W/short_preview.png"
SERVER_PID=""
cleanup() {
  adb -s "$DEVICE" shell cmd connectivity airplane-mode disable >/dev/null 2>&1
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  rm -rf "$W"
}
trap cleanup EXIT

python3 -I -m http.server 8765 --bind 127.0.0.1 --directory "$REGION_DIR" >/dev/null 2>&1 &
SERVER_PID=$!
adb -s "$DEVICE" reverse tcp:8765 tcp:8765 >/dev/null
adb -s "$DEVICE" shell cmd connectivity airplane-mode disable >/dev/null

(
  cd "$HERE/example" && flutter test integration_test/region_maps_test.dart -d "$DEVICE" \
    --dart-define=PHASE=all \
    --dart-define=REGION_URL=http://localhost:8765/serengeti.mwm \
    --dart-define=REGION_SHA256="$SHA" --dart-define=REGION_SIZE="$SIZE" \
    --dart-define=OFFLINE_DELAY=45 --dart-define=REQUIRE_OFFLINE=true \
    --dart-define=SKIP_BASE_MAPS="$SKIP_BASE_MAPS" --dart-define=HOLD_SECONDS=8
) > "$LOG" 2>&1 &
TEST_PID=$!

# Switch the network off once the map is installed, then screenshot the preview.
until grep -q READY_FOR_OFFLINE "$LOG" 2>/dev/null || ! kill -0 "$TEST_PID" 2>/dev/null; do sleep 2; done
grep -q READY_FOR_OFFLINE "$LOG" && adb -s "$DEVICE" shell cmd connectivity airplane-mode enable >/dev/null
until grep -q SHORT_PREVIEW_READY "$LOG" 2>/dev/null || ! kill -0 "$TEST_PID" 2>/dev/null; do sleep 1; done
if grep -q SHORT_PREVIEW_READY "$LOG"; then
  sleep 4 # let the camera finish moving
  adb -s "$DEVICE" exec-out screencap -p > "$SHOT"
  [ -n "${KEEP_SHOT:-}" ] && cp "$SHOT" "$KEEP_SHOT"
fi
wait "$TEST_PID"; TEST_STATUS=$?

if [ ! -s "$SHOT" ]; then
  echo "The short route's preview was never reached (flutter test exit $TEST_STATUS). Log tail:" >&2
  tail -15 "$LOG" >&2
  exit 2
fi

if [ "$TEST_STATUS" -ne 0 ]; then
  echo "A test failed (flutter test exit $TEST_STATUS). Log tail:" >&2
  tail -30 "$LOG" >&2
  exit 3
fi

python3 -I - "$SHOT" "$BLANK_ABOVE" <<'PY'
import struct, sys, zlib

path, blank_above = sys.argv[1], float(sys.argv[2])
data = open(path, 'rb').read()
assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
pos, idat = 8, b''
while pos < len(data):
    n, kind = struct.unpack('>I4s', data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + n]
    pos += 12 + n
    if kind == b'IHDR':
        w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
    elif kind == b'IDAT':
        idat += body
    elif kind == b'IEND':
        break
assert depth == 8 and interlace == 0 and ctype in (2, 6), 'unsupported PNG'
bpp = 3 if ctype == 2 else 4
raw, stride = zlib.decompress(idat), w * bpp

# The map area: below the status bar and above the preview panel.
y0, y1 = int(h * 0.07), int(h * 0.70)
counts, total = {}, 0
prev, i = bytearray(stride), 0
for y in range(y1):
    f = raw[i]
    line = bytearray(raw[i + 1:i + 1 + stride])
    i += 1 + stride
    if f == 1:
        for x in range(bpp, stride):
            line[x] = (line[x] + line[x - bpp]) & 255
    elif f == 2:
        for x in range(stride):
            line[x] = (line[x] + prev[x]) & 255
    elif f == 3:
        for x in range(stride):
            left = line[x - bpp] if x >= bpp else 0
            line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
    elif f == 4:
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    prev = line
    if y >= y0 and y % 3 == 0:
        for x in range(0, w, 3):
            px = bytes(line[x * bpp:x * bpp + 3])
            counts[px] = counts.get(px, 0) + 1
            total += 1

dominant = max(counts.values()) / total
print(f'map area: {len(counts)} distinct colours, the most common covers {dominant:.1%}')
if dominant > blank_above:
    print('PREVIEW IS BLANK: the map is one flat colour, so the camera is not framing the route.')
    sys.exit(1)
print('PREVIEW IS DRAWN: the route is framed and the map is visible.')
PY
