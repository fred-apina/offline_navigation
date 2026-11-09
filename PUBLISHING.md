# Publishing runbook (maintainer only)

This library has three artifacts:

1. **`io.github.fred-apina:organicmaps-sdk`** — the prebuilt native engine AAR
   for Android, published to **Maven Central**. Rebuilt only when the engine or
   its bundled map-data version changes.
2. **`ios/Frameworks/OfflineNavEngine.xcframework` and `ios/Resources/`** — the
   same engine for iOS and its data files. These travel **inside the pub.dev
   package** (29 MB compressed), not through a registry, and are not committed
   to git. Rebuilt only when the engine changes.
3. **`offline_navigation`** — the Dart/Flutter plugin, published to **pub.dev**.
   Depends on (1) and ships (2).

Most releases only touch (3). You only redo (1) and (2) when updating the engine,
and they must be built from the same engine commit.

## Before every engine release: check the map mirrors

Map downloads go to the servers listed in `DEFAULT_URLS_JSON` in the engine fork's
`private.h` (`METASERVER_URL` is empty on purpose: the meta server upstream names
answers in a format the engine cannot read, and the engine then fell back to a
list with dead mirrors, which made downloads fail, see the 0.3.1 changelog). A
mirror that does not have the current data version answers 404 and costs every
download one of its servers, so check each one before a release and after the
data version changes (`<version>` is the engine's data version, for example
`260714`, see `OfflineNavigation.engineDataVersion`):

```sh
for host in cdn cdn-us1 cdn-fi3 cdn-de2 cdn-de3; do
  for file in World WorldCoasts Tanzania_Northern; do
    printf '%s %s ' $host $file
    curl -s -o /dev/null -r 0-1023 -w '%{http_code}\n' "https://$host.organicmaps.app/maps/<version>/$file.mwm"
  done
done
```

Every line must say `206`. Take a mirror that says anything else out of the list.

---

## One-time setup

### A. Sonatype Central Portal account + namespace

1. Go to <https://central.sonatype.com> and **Sign in with GitHub** (use the
   `fred-apina` account). Because you own that GitHub username, the
   `io.github.fred-apina` namespace is granted to you **automatically** — no
   verification repository needed. Confirm it appears under *View Namespaces*.
2. Generate a **publishing token**: avatar → *View Account* → *Generate User
   Token*. You get a token **username** and **password**. Keep them secret.

### B. GPG signing key (you generate and own this — never commit it)

Central requires every artifact to be GPG-signed.

```sh
# 1. Generate a key (pick your own passphrase when prompted):
gpg --full-generate-key            # choose RSA 4096, no expiry, your name + email

# 2. Find its long key id (the part after rsa4096/):
gpg --list-secret-keys --keyid-format=long

# 3. Publish the PUBLIC key so Central can verify signatures:
gpg --keyserver keyserver.ubuntu.com --send-keys <LONG_KEY_ID>

# 4. Export the private key in the ascii-armored form Gradle needs:
gpg --armor --export-secret-keys <LONG_KEY_ID>
```

### C. Put credentials in `~/.gradle/gradle.properties` (NOT in the repo)

```properties
mavenCentralUsername=<portal token username>
mavenCentralPassword=<portal token password>

signingInMemoryKey=<paste the armored private key from step B4;\
  replace real newlines with \n so it is one line>
signingInMemoryKeyId=<last 8 chars of the long key id>
signingInMemoryKeyPassword=<your key passphrase>
```

> Tip: instead of editing the multi-line key by hand, you can pass it as an env
> var when publishing:
> `export ORG_GRADLE_PROJECT_signingInMemoryKey="$(gpg --armor --export-secret-keys <KEY_ID>)"`

---

## Publishing the engine AAR (only when the engine changes)

The Android engine is built from the engine fork, `fred-apina/organicmaps`, by
the workflow `.github/workflows/sdk-publish.yaml`. It builds two Maven
artifacts, both under `io.github.fred-apina`: `organicmaps-sdk` and the module it
depends on, `organicmaps-sdk-location-core`. The fork's
`android/groovy/fork-publishing.gradle` sets the coordinates (upstream's own
publishing helper uses `app.organicmaps.sdk`), keeps apps on `compileSdk 36`, and
adds the Central Portal upload.

1. **Build only** (no secrets needed). Check that it is green and download the
   artifact if you want to test it:

   ```sh
   gh workflow run sdk-publish.yaml -R fred-apina/organicmaps --ref <branch> \
     -f version=<version> -f publish=false
   ```

   It builds all four ABIs, checks that the native library is stripped and that the
   consumer ProGuard rules are in the AAR, and attaches both AARs.

2. **Publish** (needs the repository secrets `MAVEN_CENTRAL_USERNAME`,
   `MAVEN_CENTRAL_PASSWORD`, `SIGNING_KEY`, `SIGNING_KEY_ID`,
   `SIGNING_KEY_PASSWORD`). This stages the signed modules as one deployment (the
   log prints a single deployment id):

   ```sh
   gh workflow run sdk-publish.yaml -R fred-apina/organicmaps --ref <branch> \
     -f version=<version> -f publish=true
   ```

   Open <https://central.sonatype.com/publishing>, check that the deployment lists
   **both** components (`organicmaps-sdk` and `organicmaps-sdk-location-core`) at
   the new version, then press *Publish*. If only one is listed, do not publish:
   the missing module would break every build that resolves the first. Never
   publish a release candidate version.
   After it completes the artifacts appear on Maven Central within about 10-30
   minutes (the search index can take a few hours). Central deployments are
   immutable: use a new version for every release.

3. Set the plugin's `omSdkVersion` default in `android/build.gradle` to the new
   version, and the plugin version in `pubspec.yaml` and `ios/offline_navigation.podspec`.

To try the engine locally before any of that, in the fork's `android` folder (JDK
17, Python 3.11 or newer first on `PATH`, `ANDROID_HOME` set):

```sh
./gradlew :sdk:publishToMavenLocal :sdk:location:core:publishToMavenLocal \
  -PsdkVersion=0.3.1-local -Parm64-v8a --no-configuration-cache
```

then put `offlineNavigation.sdkVersion=0.3.1-local` in the example app's
`android/gradle.properties` (do not commit it). `-Parm64-v8a` builds one ABI in a
couple of minutes. The older `tool/publish_sdk_aar.sh` and
`tool/organicmaps-sdk.build.gradle.kts.reference` belong to the previous local
build tree and are kept only for reference.

## Building the iOS engine (only when the engine changes)

The iOS side lives in the engine fork, `iphone/OfflineNav` (an Objective-C++
layer, one dynamic framework linked from the engine's static libraries). On a
Mac with Xcode and the Metal Toolchain (`xcodebuild -downloadComponent
MetalToolchain`), from a checkout of the fork **at a path without spaces**:

```sh
iphone/OfflineNav/build_xcframework.sh --out /path/to/ios-engine
```

This builds the libraries for the device and the simulator (the first run takes
a while and uses about 5 GB of derived data), links and creates
`Frameworks/OfflineNavEngine.xcframework`, copies the data files into
`Resources/`, and records the engine commit in `ENGINE_COMMIT`. Copy the result
into the plugin:

```sh
rsync -a --delete /path/to/ios-engine/Frameworks /path/to/ios-engine/Resources /path/to/ios-engine/ENGINE_COMMIT \
  <plugin>/ios/
```

`ios/Frameworks` and `ios/Resources` are ignored by git on purpose and included
by `.pubignore`. Then run the on-device checks (below) before publishing.

### Checking an iOS build

```sh
cd example
flutter test integration_test/region_maps_test.dart -d <simulator UDID> \
  --dart-define=PHASE=all --dart-define=REGION_URL=http://localhost:8765/serengeti.mwm \
  --dart-define=REGION_SHA256=<hex> --dart-define=REGION_SIZE=<bytes> --dart-define=SKIP_BASE_MAPS=true
# or, to also look at the route preview:
PLATFORM=ios tool/check_preview_framing.sh
```

Serve the map with `python3 -m http.server 8765 --bind 127.0.0.1 --directory <dir>`
first (the check script does it for you). With Xcode 27 and Flutter 3.44,
`flutter build ios --simulator` without `-d <simulator>` fails in Flutter's own
architecture check (`lipo -verify_arch` changed); always name the simulator.
A device build needs a signing team in `example/ios/Runner.xcodeproj`.

## Publishing the Flutter plugin

Once the AAR version it depends on is live on Central (see
`android/build.gradle`), from the `offline_navigation/` package root:

Check that `ios/Frameworks/OfflineNavEngine.xcframework` and `ios/Resources/`
are present and that `ios/ENGINE_COMMIT` is the engine commit the AAR was built
from, then:

```sh
flutter pub publish --dry-run   # the archive must be about 29 MB, not 1 MB
flutter pub publish
```

The first `flutter pub publish` opens a browser to sign in with your Google
account and claims the package name permanently.
