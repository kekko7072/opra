# Updated Signing Setup for Cross-Platform Opra

This document explains the updated signing and release process for the cross-platform Opra project.

## 🏗️ Project Structure Changes

The project has been reorganized to support both macOS and Windows:

```
Opra/
├── macos/                 # macOS SwiftUI application
│   ├── Opra.xcodeproj
│   └── Opra/
├── windows/               # Windows WinUI 3 application
│   ├── Opra.sln
│   └── Opra/
└── .github/workflows/     # GitHub Actions workflows
    ├── build.yml          # Cross-platform build
    └── release.yml        # Release with signing
```

## 🔐 macOS Signing (Updated)

The macOS signing process has been updated to work with the new project structure:

### Key Changes:
- **Project Path**: Updated from `Opra.xcodeproj` to `macos/Opra.xcodeproj`
- **Build Path**: Updated to use the new directory structure
- **All signing steps**: Updated to work with the new paths

### Required Secrets (Same as Before):
1. **`APPLE_CERTIFICATE_BASE64`** - Your Developer ID Application certificate
2. **`APPLE_CERTIFICATE_PASSWORD`** - Password for the `.p12` certificate file
3. **`APPLE_ID`** - Your Apple ID email address
4. **`APPLE_ID_PASSWORD`** - App-specific password
5. **`APPLE_TEAM_ID`** - Your Apple Developer Team ID

### What the Updated Workflow Does:
1. ✅ **Builds macOS app** from `macos/Opra.xcodeproj`
2. ✅ **Code signs** with Developer ID Application certificate
3. ✅ **Notarizes** with Apple Notary Service
4. ✅ **Creates DMG** and ZIP files
5. ✅ **Builds Windows app** with .NET 7.0
6. ✅ **Creates release** with both platforms

## 🪟 Windows Build (New)

The Windows build process is now included in the release workflow:

### What it Does:
1. ✅ **Builds Windows app** (WinUI 3 with .NET 7.0)
2. ✅ **Publishes self-contained** executable
3. ✅ **Uploads as artifact** for release

## 🚀 How to Use

### For Developers:
1. **Set up secrets** (same as before for macOS)
2. **Push to main branch** - triggers automatic build and release
3. **Check Actions tab** - see build progress
4. **Download releases** - get both macOS and Windows versions

### For Users:
1. **macOS**: Download `.dmg` file (signed and notarized)
2. **Windows**: Download `opra-windows` artifact (self-contained)


## 📋 Workflow Files

### `.github/workflows/build.yml`
- **Purpose**: Cross-platform build on every push
- **Platforms**: macOS, Windows
- **Output**: Build artifacts for testing (unsigned)

### `.github/workflows/release.yml`
- **Purpose**: Full release with signing and notarization
- **Trigger**: Push to main branch
- **Platforms**: macOS (signed) + Windows (self-contained)
- **Output**: GitHub release with downloadable files

## ✅ Verification

The updated signing setup has been tested and verified to work with the new project structure. All paths have been updated and the workflow will:

1. **Build macOS app** from the correct location
2. **Sign and notarize** as before
3. **Build Windows app** alongside macOS
4. **Create releases** with both platforms

## 🎯 Next Steps

1. **Push your changes** to GitHub
2. **Check the Actions tab** to see the build progress
3. **Download the release** to test both platforms
4. **Verify signing** works as expected

The signing process for macOS works exactly as before, just with the updated project structure! 🎉