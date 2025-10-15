#!/bin/bash

# Build script for Opra - Cross-platform PDF Reader AI

set -e

echo "Building Opra - Cross-platform PDF Reader AI"

# Function to build macOS app
build_macos() {
    echo "Building macOS app..."
    cd macos
    xcodebuild -project Opra.xcodeproj -scheme Opra -configuration Release -derivedDataPath build
    echo "macOS build completed"
    cd ..
}

# Function to build Windows app
build_windows() {
    echo "Building Windows app..."
    cd windows
    dotnet build -c Release
    echo "Windows build completed"
    cd ..
}

# Main build logic
case "${1:-all}" in
    "macos")
        build_macos
        ;;
    "windows")
        build_windows
        ;;
    "all")
        build_macos
        build_windows
        ;;
    *)
        echo "Usage: $0 [macos|windows|all]"
        echo "  macos   - Build macOS app only"
        echo "  windows - Build Windows app only"
        echo "  all     - Build everything (default)"
        exit 1
        ;;
esac

echo "Build completed successfully!"
