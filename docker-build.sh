#!/bin/bash

# Docker build script for cross-platform development

set -e

echo "Building Windows version using Docker..."

# Build Windows app using Docker
docker build -f Dockerfile.windows -t opra-windows .

# Create output directory
mkdir -p dist/windows

# Copy built files from container
docker create --name opra-windows-temp opra-windows
docker cp opra-windows-temp:/app/. dist/windows/
docker rm opra-windows-temp

echo "Windows build completed! Check dist/windows/ for the built files."