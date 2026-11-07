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

> **Note on where the SDK build lives.** The `:sdk` module that produces the
> AAR currently lives in a local Organic Maps build tree
> (`flutter_organic_nav/android`) that is **not** yet under version control.
> A snapshot of its `build.gradle.kts` is preserved in this repo at
> [`tool/organicmaps-sdk.build.gradle.kts.reference`](tool/organicmaps-sdk.build.gradle.kts.reference)
> so the publishing config isn't lost. Moving this build into a proper
> `organicmaps` fork with CI is a tracked follow-up (it's what will let the AAR
> be rebuilt reproducibly instead of only on one machine).

The SDK module lives in the Organic Maps build tree at
`flutter_organic_nav/android` (module `:sdk`). From there:

```sh
# Builds all ABIs, signs, uploads to the Central Portal, and releases:
./gradlew :sdk:publishAndReleaseToMavenCentral --no-configuration-cache \
  -Pom.sdkVersion=<version>
```

- Omit `-Pom.abiFilters` so all four ABIs are built (the default).
- Use `publishToMavenCentral` (without `AndReleaseTo`) if you'd rather review
  the staged deployment in the Portal and click *Publish* manually — recommended
  for your first upload.
- After it completes, the artifact appears on Maven Central within ~10–30 min
  (search index can take a few hours). Bump `-Pom.sdkVersion` for every release;
  Central deployments are immutable.

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
