#!/usr/bin/env bash
# Builds the Organic Maps SDK AAR (all ABIs, release), signs it, and publishes
# it to Maven Central via the Sonatype Central Portal.
#
# See PUBLISHING.md for the full runbook, including the one-time account,
# namespace, GPG key, and credential setup this script assumes is already done.
#
# Prerequisites:
#   - An organicmaps checkout containing the publishable ':sdk' Gradle module
#     (see SDK_BUILD_DIR below) with Android SDK/NDK configured.
#   - ~/.gradle/gradle.properties (or ORG_GRADLE_PROJECT_* env vars) holding the
#     Central Portal token (mavenCentralUsername/Password) and the signing key
#     (signingInMemoryKey/KeyId/KeyPassword).
#
# Usage:
#   SDK_VERSION=0.1.0 ./tool/publish_sdk_aar.sh            # upload + auto-release
#   RELEASE=manual SDK_VERSION=0.1.0 ./tool/publish_sdk_aar.sh  # stage only; release in the Portal UI
set -euo pipefail

# Gradle build that contains the ':sdk' module (the module's build.gradle.kts has
# the vanniktech mavenPublishing config; the C++ core comes from the repo root).
SDK_BUILD_DIR="${SDK_BUILD_DIR:-$HOME/Development/Flutter Projects/organicmaps/flutter_organic_nav/android}"
# Version to publish. Bump for every release — Central deployments are immutable.
SDK_VERSION="${SDK_VERSION:?Set SDK_VERSION, e.g. SDK_VERSION=0.1.0}"
ABIS="${ABIS:-armeabi-v7a,arm64-v8a,x86_64,x86}"
# "manual" leaves the deployment staged in the Portal for you to review + release.
RELEASE="${RELEASE:-auto}"

if [ "${RELEASE}" = "manual" ]; then
  TASK="publishToMavenCentral"
else
  TASK="publishAndReleaseToMavenCentral"
fi

echo "Publishing organicmaps-sdk ${SDK_VERSION} (${ABIS}) to Maven Central [${TASK}] ..."
(
  cd "${SDK_BUILD_DIR}"
  ./gradlew ":sdk:${TASK}" \
    "-Pom.sdkVersion=${SDK_VERSION}" \
    "-Pom.abiFilters=${ABIS}" \
    --no-configuration-cache
)

echo "Done. Artifact: io.github.fred-apina:organicmaps-sdk:${SDK_VERSION}"
echo "It appears on Maven Central within ~10-30 min (search index may lag a few hours)."
