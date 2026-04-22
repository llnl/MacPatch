# MacPatch Agent Uploader

# Prerequisites

- Apple Developer Account (paid membership required)
- App-specific password for notarization (https://support.apple.com/en-us/102654)
- Developer ID certificate for code signing
- Find your Team ID at developer.apple.com/account

##### Create App-Specific Password

1. Go to appleid.apple.com
2. Sign in with your Apple ID
3. Go to Security → App-Specific Passwords
4. Click Generate an app-specific password
5. Name it (e.g., "Notarization")
6. Save the password securely

---

### MacPatch Server Info
Please fill out all of the fields. The default port should be 3600.

## Options
The Package option is the only required option. Notorize will not work unless the package is signed.

When notorizing the installer packages. You will need to setup a KeyChain profile.

###### Store Credentials in Keychain
`xcrun notarytool store-credentials "notary-profile" \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password"
`
