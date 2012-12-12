#!/bin/sh

# LipoLibrary.sh
#
# Copyright 2012 InMobi Inc. All rights reserved.
#
# Combine the libraries for the various architectures using lipo.

set -o errexit
set -o nounset
set -o xtrace

# Expected base library name for input and output files
lib_name=libAim.a
build_lib_name=${CONFIGURATION}/${lib_name}

# Library expected locations
# Ex: (Project)/build/(ARCHS)/Debug/lib(LIBRARY_BASE_NAME).a
armv7_lib="${BUILD_ROOT}/armv7/${build_lib_name}"
armv7s_lib="${BUILD_ROOT}/armv7s/${build_lib_name}"
i386_lib="${BUILD_ROOT}/i386/${build_lib_name}"

# Final library location
final_lib_dir="${BUILD_ROOT}/${CONFIGURATION}"
final_lib="${final_lib_dir}/${lib_name}"

# Remove existing product lib file, just in case
rm -rf "$final_lib"

# Create the final library directory
mkdir -p "$final_lib_dir"

# Combine lib files for various platforms into one
lipo -create "$i386_lib" "$armv7_lib" "$armv7s_lib" -output "$final_lib"

lib_name=lib${PRODUCT_NAME}
final_lib_dir="${SYMROOT}/${CONFIGURATION}"
final_lib="${final_lib_dir}/${lib_name}.a"
public_dir="${SRCROOT}/Public"

# Clean up the destination dir
# Somtimes the 'rm -rf' command below fails because of lingering
# .nfs files. Ignore these failures so as not to fail the build process.
rm -f ${LIBRARY_DESTINATION_DIR}/*

# Create the destination dir
mkdir -p ${LIBRARY_DESTINATION_DIR}

# Copy the fat library
cp "${final_lib_dir}/libAim.a" "${LIBRARY_DESTINATION_DIR}/libAim.a"

# Make all of the destination files read-only
chmod a-w ${LIBRARY_DESTINATION_DIR}/*
