#!/bin/bash
set -e

if [ -f "build/web/index.html" ]; then
  echo "Prebuilt web artifacts found in build/web. Proceeding with deployment."
  exit 0
fi

echo "Downloading Flutter SDK..."
git clone https://github.com/flutter/flutter.git --depth 1 -b stable flutter-sdk
export PATH="$PATH:$(pwd)/flutter-sdk/bin"

echo "Configuring Flutter..."
flutter config --no-analytics

echo "Building Flutter Web for RescuPath Paramedic App..."
flutter build web --release --dart-define=API_BASE_URL=https://rescupath-app-1.onrender.com

echo "Build completed successfully!"
