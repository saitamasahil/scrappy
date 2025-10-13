#!/bin/bash

# Run the update script to build Skyscraper
/skysource/update_skyscraper.sh

# Check if the Skyscraper binary was built successfully
if ! command -v Skyscraper &> /dev/null; then
    echo "Skyscraper binary not found. Build may have failed."
    exit 1
fi

Skyscraper -v

# Create a directory to store the binary and libraries
mkdir -p /skysource/output
mkdir -p /output

# Copy the Skyscraper binary
cp $(which Skyscraper) /skysource/output/

# Copy shared libraries needed by Skyscraper
ldd $(which Skyscraper) | grep "=>" | awk '{print $3}' | xargs -I '{}' cp '{}' /skysource/output/
cp /usr/lib/aarch64-linux-gnu/libssl.so.1.1 /skysource/output/
cp /usr/lib/aarch64-linux-gnu/libcrypto.so.1.1 /skysource/output/

# Package the binary and libraries into a .zip file
cd /skysource/output
7z a /output/skyscraper_package.zip .

echo "Packaging complete. Zip file located at /output/skyscraper_package.zip"
