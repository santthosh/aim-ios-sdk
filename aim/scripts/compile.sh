#!/bin/sh

# Compile.sh
#
# Copyright 2012 InMobi Inc. All rights reserved.
#
# Build the architectures separately and we'll glue them all together with
# lipo in the next step.

set -o errexit
set -o nounset
set -o xtrace

xcodebuild_arch() {
  xcodebuild \
    -project aim.xcodeproj \
    -scheme "${LIBRARY_TARGET_NAME}" \
    -configuration "${CONFIGURATION}" \
    -sdk $1 \
    ARCHS="$2" \
    CACHE_ROOT="${CACHE_ROOT}" \
    OBJROOT="${OBJROOT}/$2" \
    SYMROOT="${SYMROOT}/$2" \
    EFFECTIVE_PLATFORM_NAME=
  echo "---> DONE"
}

# Built each architecture via xcodebuild. This will place the build objects into
# seperate directories so that we don't have to rebuild everything every time.
cd "${SRCROOT}"

# Do the armv7 build
xcodebuild_arch iphoneos armv7

# Do the armv7 build
xcodebuild_arch iphoneos armv7s

# Do the Simulator build.  We need to specify the SDK build here because the
# default one for the project could be for the device SDK.
xcodebuild_arch iphonesimulator i386
