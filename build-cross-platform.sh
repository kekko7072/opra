#!/bin/bash

# Cross-platform build script for macOS
# This script builds what it can locally and provides instructions for Windows

set -e

echo "Building Opra - Cross-platform PDF Reader AI"
echo "=============================================="

# Build what we can on macOS
echo "Building macOS app..."
./build.sh macos

echo ""
echo "✅ macOS build completed successfully!"
echo ""
echo "For Windows build, you have several options:"
echo ""
echo "1. 🚀 GitHub Actions (Recommended):"
echo "   - Push your code to GitHub"
echo "   - The .github/workflows/build.yml will automatically build Windows"
echo "   - Download the built app from the Actions tab"
echo ""
echo "2. 🐳 Docker (if you have Docker installed):"
echo "   ./docker-build.sh"
echo ""
echo "3. 💻 Windows VM:"
echo "   - Install Windows in a VM (Parallels, VMware, VirtualBox)"
echo "   - Install Visual Studio 2022 and .NET 8.0 SDK"
echo "   - Run: build.bat windows"
echo ""
echo "4. ☁️  Cloud Development:"
echo "   - Use GitHub Codespaces with Windows container"
echo "   - Use Azure DevOps or similar cloud build services"
echo ""
echo "Current build status:"
echo "✅ macOS: Ready (macos/build/Build/Products/Release/Opra.app)"
echo "⏳ Windows: Requires Windows environment"
