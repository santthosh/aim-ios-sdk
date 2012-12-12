#!/bin/sh

# Bundle.sh
#
# Copyright 2012 InMobi Inc. All rights reserved.

set -o errexit
set -o nounset
set -o xtrace

lib_name=libAim.a
final_lib="${LIBRARY_DESTINATION_DIR}/${lib_name}"
version=$(date "+%Y-%m-%d.%H.%M.%S")
package_dir="$PRODUCT_DESTINATION_DIR/AppInMap"

# Clean up the destination dir
# Somtimes the 'rm -rf' command below fails because of lingering
# .nfs files. Ignore these failures so as not to fail the build process.
rm -rf ${PRODUCT_DESTINATION_DIR}/*

# Create the destination dir
mkdir -p ${PRODUCT_DESTINATION_DIR}
mkdir -p ${package_dir}

# Copy the fat library
cp ${final_lib} ${package_dir}/libAim.a

# Copy the associated headers

/bin/cp -P "$SRCROOT/aim/AppInMap.h" "$package_dir"

/bin/rm -rf "$PRODUCT_DESTINATION_DIR/*.zip"
cd $PRODUCT_DESTINATION_DIR
/usr/bin/zip -r -X "AppInMap-$version.zip" AppInMap

# Make all of the destination files read-only
# chmod a-w ${PRODUCT_DESTINATION_DIR}/*
