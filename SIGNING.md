# SIGNING

Instruction for workflow of notarization of the macos app.

## For Developers: Setting Up Notarization

If you fork this repository and want to enable automatic notarization in GitHub Actions, you'll need to set up the following secrets in your repository settings:

### Required Secrets

1. **`APPLE_CERTIFICATE_BASE64`** - Your Developer ID Application certificate
   - Export your certificate from Keychain Access as a `.p12` file
   - Convert to base64: `base64 -i certificate.p12 | pbcopy`
   - Paste the result as the secret value

2. **`APPLE_CERTIFICATE_PASSWORD`** - Password for the `.p12` certificate file

3. **`APPLE_ID`** - Your Apple ID email address

4. **`APPLE_ID_PASSWORD`** - App-specific password (not your regular password)
   - Generate at: https://appleid.apple.com/account/manage
   - Go to "Sign-In and Security" > "App-Specific Passwords"

5. **`APPLE_TEAM_ID`** - Your Apple Developer Team ID
   - Found in your Apple Developer account settings

### How to Add Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Add each secret with the exact names listed above

Once configured, the GitHub Actions workflow will automatically code sign and notarize your builds!