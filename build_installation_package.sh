#!/bin/bash

# Script for creating a single compressed archive, after download_dependencies.sh
# has been executed.
# It will create an archive in the $TARGET_DIRECTORY, named $ARCHIVE_NAME.

TARGET_DIRECTORY="/tmp/dqmgui"
ARCHIVE_NAME="dqmgui_installation_package.tar.gz"

mkdir -p "$TARGET_DIRECTORY"
tar -cf "$TARGET_DIRECTORY/$ARCHIVE_NAME" . -I "gzip --best" --exclude "./git" --exclude "./github"
