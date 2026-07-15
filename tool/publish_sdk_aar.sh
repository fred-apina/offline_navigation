#!/usr/bin/env bash
# Builds the Organic Maps SDK AAR (all ABIs, release) and publishes it into a
# git-backed Maven repository served via GitHub Pages.
#
# Prerequisites:
#   - An organicmaps checkout containing the publishable sdk Gradle module
#     (see SDK_BUILD_DIR below) with Android SDK/NDK configured.
#   - A clone of the Maven repository (github.com/fred-apina/maven-repo).
#
# Usage:
#   SDK_VERSION=0.2.0 ./tool/publish_sdk_aar.sh
set -euo pipefail

# Gradle build that contains the ':sdk' module (module dir holds build.gradle.kts
# with the maven-publish configuration; C++ core comes from the repo root).
SDK_BUILD_DIR="${SDK_BUILD_DIR:-$HOME/Development/Flutter Projects/organicmaps/flutter_organic_nav/android}"
# Local clone of the GitHub-Pages Maven repository.
MAVEN_REPO_DIR="${MAVEN_REPO_DIR:-$HOME/Development/Flutter Projects/organicmaps/maven-repo}"
# Version to publish (must be bumped for every release; Pages caches aggressively).
SDK_VERSION="${SDK_VERSION:?Set SDK_VERSION, e.g. SDK_VERSION=0.1.0}"
ABIS="${ABIS:-armeabi-v7a,arm64-v8a,x86_64,x86}"

echo "Building organicmaps-sdk ${SDK_VERSION} (${ABIS}) ..."
(
  cd "${SDK_BUILD_DIR}"
  ./gradlew :sdk:publishReleasePublicationToPagesDirRepository \
    "-Pom.sdkVersion=${SDK_VERSION}" \
    "-Pom.abiFilters=${ABIS}" \
    "-Pom.mavenRepoDir=${MAVEN_REPO_DIR}"
)

echo "Committing and pushing the Maven repository ..."
(
  cd "${MAVEN_REPO_DIR}"
  git add -A
  git commit -m "organicmaps-sdk ${SDK_VERSION}"
  git push
)

echo "Done. Artifact: io.github.fred-apina:organicmaps-sdk:${SDK_VERSION}"
echo "Served at:      https://fred-apina.github.io/maven-repo/ (allow a few minutes for Pages to deploy)"
