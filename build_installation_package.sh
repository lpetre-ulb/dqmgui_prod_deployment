#!/bin/bash

# Script for creating a single compressed deployment archive, once download_dependencies.sh
# has been executed.
# It will create an archive named $ARCHIVE_NAME using the files in $SOURCE_DIRECTORY,
# stored in $TARGET_DIRECTORY.

set -ex

SOURCE_DIRECTORY="."
TARGET_DIRECTORY="/tmp/dqmgui"
ARCHIVE_NAME="dqmgui_installation_package.tar.gz"

# Parse command line arguments -- use <key>=<value> to override the flags mentioned above.
# e.g. ARCHIVE_NAME="test.tar.gz"
for ARGUMENT in "$@"; do
    KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
    KEY_LENGTH=${#KEY}
    VALUE="${ARGUMENT:$KEY_LENGTH+1}"
    eval "$KEY=$VALUE"
done

mkdir -p "$TARGET_DIRECTORY"
tar -cf "$TARGET_DIRECTORY/$ARCHIVE_NAME" --exclude "$SOURCE_DIRECTORY/.git" --exclude "$SOURCE_DIRECTORY/.github" "$SOURCE_DIRECTORY" -I "gzip --best"
