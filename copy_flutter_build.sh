#!/bin/bash
# Script to copy Flutter web build to the server

set -e

FLUTTER_APP_PATH="../trufi-app"
BUILD_PATH="$FLUTTER_APP_PATH/build/web"
TARGET_PATH="./web"

echo "=== Copying Flutter Web Build to Trufi Server Planner ==="

# Check if Flutter app path exists
if [ ! -d "$FLUTTER_APP_PATH" ]; then
    echo "❌ Error: Flutter app not found at $FLUTTER_APP_PATH"
    exit 1
fi

# Check if build exists
if [ ! -d "$BUILD_PATH" ]; then
    echo "⚠️  Warning: Build directory not found. Building now..."
    cd "$FLUTTER_APP_PATH"
    flutter build web --release
    cd - > /dev/null
fi

# Backup existing web directory
if [ -d "$TARGET_PATH" ] && [ "$(ls -A $TARGET_PATH 2>/dev/null)" ]; then
    echo "📦 Backing up existing web directory..."
    mv "$TARGET_PATH" "${TARGET_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create target directory
mkdir -p "$TARGET_PATH"

# Copy build files
echo "📋 Copying files from $BUILD_PATH to $TARGET_PATH..."
cp -r "$BUILD_PATH"/* "$TARGET_PATH/"

echo "✅ Flutter web build copied successfully!"
echo ""
echo "Files in web directory:"
ls -lh "$TARGET_PATH" | head -20
echo ""
echo "🚀 Now restart the server:"
echo "   dart run bin/server.dart"
echo "   or"
echo "   docker-compose up -d --build"
