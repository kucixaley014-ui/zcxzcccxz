#!/usr/bin/env bash
set -e
echo "Bootstrap: ensure android project exists."
if [ ! -d "android" ]; then
  if command -v flutter >/dev/null 2>&1; then
    echo "Flutter detected — running 'flutter create . --platforms android'"
    flutter create . --platforms android
    echo "Flutter project created."
  else
    echo "Flutter CLI not found. To generate the android folder locally run:"
    echo "  flutter create . --platforms android"
    echo "This script will then be able to continue."
    exit 0
  fi
else
  echo "android/ already exists — nothing to do."
fi
