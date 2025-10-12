# GitHub Actions Release Workflows

This directory contains GitHub Actions workflows for automatically releasing your macOS application.

## Available Workflows

### 1. `release-simple.yml` (Recommended for beginners)
- **File**: `.github/workflows/release-simple.yml`
- **Description**: Simple release workflow that builds and packages your app without code signing
- **Requirements**: None (uses GitHub's built-in secrets)
- **Best for**: Development releases, testing, or when you don't have Apple Developer account

### 2. `release-signed.yml` (For production releases)
- **File**: `.github/workflows/release-signed.yml`
- **Description**: Full release workflow with code signing and notarization
- **Requirements**: Apple Developer account and certificates
- **Best for**: Production releases distributed to end users

### 3. `release.yml` (Basic archive workflow)
- **File**: `.github/workflows/release.yml`
- **Description**: Basic workflow that creates archives
- **Requirements**: None
- **Best for**: Simple builds without DMG creation

## Setup Instructions

### For Simple Releases (No Code Signing)

1. **Enable the workflow**:
   - Rename `release-simple.yml` to `release.yml` (or keep both)
   - The workflow will automatically trigger on pushes to `main` branch

2. **No additional setup required** - the workflow uses GitHub's built-in secrets

### For Signed Releases (With Code Signing)

1. **Get Apple Developer Certificates**:
   - Export your Developer ID Application certificate as a `.p12` file
   - Convert it to base64: `base64 -i certificate.p12 -o certificate.txt`

2. **Set up GitHub Secrets**:
   Go to your repository → Settings → Secrets and variables → Actions, and add:
   - `CERTIFICATE_BASE64`: Base64 encoded certificate
   - `CERTIFICATE_PASSWORD`: Password for the certificate
   - `CODE_SIGN_IDENTITY`: Your certificate name (e.g., "Developer ID Application: Your Name")
   - `PROVISIONING_PROFILE_SPECIFIER`: Provisioning profile name
   - `APPLE_ID`: Your Apple ID email
   - `APPLE_PASSWORD`: App-specific password for your Apple ID
   - `TEAM_ID`: Your Apple Developer Team ID

3. **Enable the workflow**:
   - Rename `release-signed.yml` to `release.yml`
   - The workflow will automatically trigger on pushes to `main` branch

## How It Works

### Trigger Events
- **Push to main branch**: Creates a release automatically
- **Merge PR to main**: Creates a release when a pull request is merged into main

### Release Process
1. **Checkout code** from the repository
2. **Setup Xcode** with the latest stable version
3. **Extract version** from your Xcode project settings
4. **Build the app** in Release configuration
5. **Create DMG** installer for easy distribution
6. **Create GitHub release** with the DMG and app files
7. **Upload assets** to the release

### Release Assets
- **DMG file**: macOS installer (recommended for users)
- **App ZIP**: Direct application bundle for developers

## Customization

### Version Number
The workflow automatically extracts the version from your Xcode project's `MARKETING_VERSION` setting. Make sure this is set in your project.

### Release Notes
You can customize the release notes by editing the `body` section in the workflow files.

### Build Configuration
Modify the `xcodebuild` commands to match your project's specific build requirements.

## Troubleshooting

### Common Issues

1. **Build fails**: Check that your Xcode project builds successfully locally
2. **Version not found**: Ensure `MARKETING_VERSION` is set in your Xcode project
3. **Code signing fails**: Verify your certificates and provisioning profiles are correct
4. **Notarization fails**: Check your Apple ID credentials and team ID

### Debug Steps

1. Check the Actions tab in your GitHub repository for detailed logs
2. Test the build locally with the same commands used in the workflow
3. Verify all secrets are correctly set in the repository settings

## Security Notes

- Never commit certificates or passwords to your repository
- Use GitHub Secrets for all sensitive information
- Regularly rotate your Apple ID app-specific passwords
- Keep your certificates secure and up to date

## Support

If you encounter issues with the workflows, check:
1. GitHub Actions documentation
2. Xcode build settings
3. Apple Developer documentation for code signing
4. Your project's specific requirements