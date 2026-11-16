# Code Signing and Notarization Guide

## Overview

Starting with macOS 10.15 (Catalina), Apple requires all software distributed outside the Mac App Store to be **notarized**. This guide explains how to sign and notarize the Lazarus package using the `build_pkg.sh` script with **keychain profiles**.

## Prerequisites

### 1. Apple Developer Account

You need an active Apple Developer Program membership ($99/year):
- Enroll at: https://developer.apple.com/programs/

### 2. Developer Certificates

Install two certificates from your Apple Developer account:

#### Developer ID Application Certificate
- Used to sign the Lazarus binary
- Download from: https://developer.apple.com/account/resources/certificates
- Install in Keychain Access

#### Developer ID Installer Certificate
- Used to sign the .pkg installer
- Download from: https://developer.apple.com/account/resources/certificates
- Install in Keychain Access

To verify your certificates are installed:
```bash
security find-identity -p basic -v
```

Look for entries like:
```
1) ABCD1234... "Developer ID Application: Your Name (TEAM_ID)"
2) EFGH5678... "Developer ID Installer: Your Name (TEAM_ID)"
```

### 3. Store Notarization Credentials in Keychain

The build script uses `notarytool` with a **keychain profile**. You must store your credentials once, then reference the profile name.

#### Method 1: App Store Connect API Key (Recommended)

**Advantages:**
- More secure (no password storage)
- Can be scoped to specific permissions
- Doesn't expire with password changes

**Setup API Key:**
1. Go to: https://appstoreconnect.apple.com/access/api
2. Click "Keys" → "+" to generate a new key
3. Name: "Notarization Key"
4. Access: "Developer"
5. Download the .p8 file (only available once!)
6. Note your:
   - Key ID (e.g., ABC123XYZ)
   - Issuer ID (e.g., 12345678-1234-1234-1234-123456789012)

**Store in Keychain:**
```bash
xcrun notarytool store-credentials "AC_NOTARY" \
    --key ~/path/to/AuthKey_ABC123XYZ.p8 \
    --key-id "ABC123XYZ" \
    --issuer "12345678-1234-1234-1234-123456789012"
```

Replace `AC_NOTARY` with any profile name you prefer.

#### Method 2: Apple ID with App-Specific Password

**Setup App-Specific Password:**
1. Go to: https://appleid.apple.com/account/manage
2. Sign in with your Apple ID (the one used for Developer account)
3. Under "Security" → "App-Specific Passwords" → "Generate Password"
4. Label: "Lazarus Notarization"
5. Note the generated password (format: xxxx-xxxx-xxxx-xxxx)

**Find your Team ID:**
```bash
# From your Developer ID certificate
security find-identity -p basic -v | grep "Developer ID"
# Team ID is in parentheses (10 characters)
```

Or check: https://developer.apple.com/account → Membership

**Store in Keychain:**
```bash
xcrun notarytool store-credentials "AC_NOTARY" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

Replace `AC_NOTARY` with any profile name you prefer.

#### Verify Stored Credentials

List all stored profiles:
```bash
xcrun notarytool history --keychain-profile "AC_NOTARY"
```

If successful, you'll see your notarization history (or an empty list if this is your first time).

## Building a Notarized Package

### Interactive Mode

Run the build script:
```bash
./build_pkg.sh
```

When prompted:

**1. Sign and notarize package? [y/N]:**
- Answer `y` for production/distribution builds
- Answer `n` for development/testing builds

**2. Developer ID Application identity:**
- Enter: `Developer ID Application: Your Name (TEAM_ID)`
- Or just: `Developer ID Application` (picks the first match)

**3. Developer ID Installer identity:**
- Enter: `Developer ID Installer: Your Name (TEAM_ID)`
- Or just: `Developer ID Installer` (picks the first match)

**4. Keychain profile name:**
- Enter the profile name you created with `notarytool store-credentials`
- Default: `AC_NOTARY`
- Example: If you ran `xcrun notarytool store-credentials "MyProfile" ...`, enter `MyProfile`

### Non-Interactive Mode

First, store credentials once:
```bash
# One-time setup
xcrun notarytool store-credentials "AC_NOTARY" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

Then use the saved config file (`.build_config`) or set defaults:
```bash
# Create .build_config with your defaults
cat > .build_config << 'EOF'
SAVED_DO_NOTARIZE="y"
SAVED_SIGN_APP_IDENTITY="Developer ID Application"
SAVED_SIGN_PKG_IDENTITY="Developer ID Installer"
SAVED_KEYCHAIN_PROFILE="AC_NOTARY"
SAVED_MP_SERVER="mp.example.com"
SAVED_MIN_VERSION="4.2.2.0"
SAVED_DAYS_RANGE="15"
SAVED_IGNORE_SSL="false"
SAVED_AGENT_HASH=""
EOF

# Build will use saved defaults without prompting
./build_pkg.sh
```

## Build Process

When signing and notarization are enabled, the build process:

1. **Cleans** build directory
2. **Compiles** Lazarus binary with Xcode
3. **Signs** the binary with Developer ID Application certificate
4. **Creates** a zip archive of the signed binary
5. **Submits** the binary to Apple for notarization (waits for approval)
6. **Copies** signed binary to package root
7. **Creates** configuration files
8. **Builds** the .pkg with Developer ID Installer signature
9. **Submits** the package to Apple for notarization (waits for approval)
10. **Staples** the notarization ticket to the package
11. **Finalizes** and copies package to script directory

**Note:** 
- Notarization steps (5 and 9) can take several minutes each. The script waits for Apple's servers to process the submission.
- Credentials are read from the keychain profile, not passed on the command line.
- The binary cannot be stapled (only bundles like .app or .pkg can be stapled). Stapling happens only on the final .pkg, which includes the notarized binary.

## Verification

After building, verify the package is properly signed and notarized:

### Check Package Signature
```bash
pkgutil --check-signature MPLazarus-1.0.0.pkg
```

Expected output:
```
Package "MPLazarus-1.0.0.pkg":
   Status: signed by a developer certificate issued by Apple for distribution
   Certificate Chain:
    1. Developer ID Installer: Your Name (TEAM_ID)
       Expires: 2027-01-01 00:00:00 +0000
       SHA256 Fingerprint: ...
```

### Check Notarization
```bash
spctl --assess --verbose --type install MPLazarus-1.0.0.pkg
```

Expected output:
```
MPLazarus-1.0.0.pkg: accepted
source=Notarized Developer ID
```

### Check Binary Signature
```bash
codesign -dvv /usr/local/sbin/lazarus
```

After installation:
```bash
spctl --assess --verbose /usr/local/sbin/lazarus
```

## Troubleshooting

### "Could not find the specified Developer ID certificate"

**Solution:** Verify certificates are installed:
```bash
security find-identity -p basic -v
```

If missing, download from https://developer.apple.com/account/resources/certificates

### "Notarization failed with status: Invalid"

**Check the detailed log:**
```bash
# Get the submission ID from build/notarize_app.log or build/notarize_pkg.log
xcrun notarytool log <submission-id> --keychain-profile "AC_NOTARY"
```

Common issues:
- Binary not signed with `--options runtime`
- Missing entitlements
- Unsigned dependencies

**Solution:** Check `build/notarize_app.log` or `build/notarize_pkg.log` for details

### "Error: authentication failed" or "Profile not found"

**Check if profile exists:**
```bash
xcrun notarytool history --keychain-profile "AC_NOTARY"
```

If this fails, the profile doesn't exist or credentials are invalid.

**Re-create the profile:**
```bash
# For Apple ID method
xcrun notarytool store-credentials "AC_NOTARY" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"

# For API Key method
xcrun notarytool store-credentials "AC_NOTARY" \
    --key ~/path/to/AuthKey_ABC123XYZ.p8 \
    --key-id "ABC123XYZ" \
    --issuer "12345678-1234-1234-1234-123456789012"
```

**Common issues:**
- Wrong profile name in build script vs what you created
- App-specific password expired or revoked
- API key file moved or deleted
- Wrong Team ID

### "Stapling failed"

Stapling can fail if:
- Network connection issues
- Package already stapled
- Notarization not yet complete (though script waits)

**This is usually not critical:** The package will still work if the client has an internet connection. Stapling just allows offline verification.

## Best Practices

1. **Store credentials securely**
   - Use `notarytool store-credentials` to store in macOS keychain
   - Keep .p8 files in a secure location (they're referenced, not copied)
   - Never commit credentials or `.p8` files to version control
   - The `.build_config` only stores the profile name, not actual secrets

2. **Use API Key method for CI/CD**
   - More reliable for automation
   - Easier to rotate if compromised
   - Doesn't expire when you change your Apple ID password

3. **Profile management**
   - Use descriptive names: `PROD_NOTARY`, `DEV_NOTARY`, etc.
   - One profile per environment if you have multiple Apple Developer accounts
   - List profiles: `xcrun notarytool history --keychain-profile <name>`

4. **Test unsigned builds first**
   - Verify package works without signing
   - Only add signing/notarization when distributing

5. **Keep certificates updated**
   - Developer ID certificates expire after 5 years
   - Renew before expiration to avoid disruption

6. **Verify after building**
   - Always run `pkgutil --check-signature`
   - Test installation on a clean system

7. **Share profiles across machines**
   - Credentials are stored in the login keychain
   - To use on another Mac, run `notarytool store-credentials` again
   - Or export/import keychain items (advanced)

## Additional Resources

- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [notarytool Manual](https://keith.github.io/xcode-man-pages/notarytool.1.html)
- [Troubleshooting Notarization](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/resolving_common_notarization_issues)
