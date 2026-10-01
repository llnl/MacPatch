# Lazarus - MacPatch Recovery Daemon

Lazarus is a background daemon that monitors the health of the MacPatch agent and automatically downloads and installs the latest agent when issues are detected.

## Overview

The lazarus daemon that does:
- Runs continuously as a background daemon
- Performs health checks every hour
- Downloads and installs the latest MacPatch installer when checks fail (instead of running planb)

## Health Checks

Lazarus performs the following checks:

1. **Agent Existence**: Verifies `/Library/MacPatch/Client/MPAgent` exists
2. **Minimum Version**: Ensures agent version meets minimum requirements
3. **Check-in Status**: Verifies client has checked in within the configured time range
4. **Agent Hash**: Validates agent binary hash (if configured)

## PKG Installation

### Compile lazarus, create native package and sign.
This will be the most common option. Also please see the NOTARIZATION.md file if you are going to be signing the application and package.

```bash
cd MacPatch/Source/Client/Lazarus
./build_pkg.sh
```

## Manual Installation 

### 1. Build the Swift daemon

```bash
cd MacPatch/Source/Client/Lazarus
swift build -c release
```

### 2. Install the binary

```bash
sudo cp .build/release/Lazarus /usr/local/sbin/lazarus
sudo chmod 755 /usr/local/sbin/lazarus
sudo chown root:wheel /usr/local/sbin/lazarus
```

### 3. Install the LaunchDaemon

```bash
sudo cp com.llnl.mp.lazarus.plist /Library/LaunchDaemons/
sudo chmod 644 /Library/LaunchDaemons/com.llnl.mp.lazarus.plist
sudo chown root:wheel /Library/LaunchDaemons/com.llnl.mp.lazarus.plist
```

### 4. Load the LaunchDaemon

```bash
sudo launchctl load /Library/LaunchDaemons/com.llnl.mp.lazarus.plist
```

## Configuration

Create or edit `/Library/Application Support/MacPatch/gov.llnl.mp.lazarus.plist` with the following optional keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>minversion</key>
    <string>4.2.2.0</string>
    
    <key>daysrange</key>
    <integer>15</integer>
    
    <key>mpserver</key>
    <string>localhost</string>
    
    <key>ignoressl</key>
    <false/>
    
    <key>mphash</key>
    <string>0</string>
</dict>
</plist>
```

### Configuration Keys

- **minversion**: Minimum required agent version (default: "4.2.2.0")
- **daysrange**: Number of days for check-in validation (default: 15)
- **mpserver**: MacPatch server hostname (default: "localhost")
  - Used for client check-in API: `https://{mpserver}/api/v1/client/checkin/info/{clientID}`
  - Used for package downloads: `https://{mpserver}/mp-content/lazarus/...`
  - **Important**: Set this to your actual MacPatch server (e.g., "mpprod.llnl.gov")
- **ignoressl**: Ignore SSL certificate validation (default: false)
- **mphash**: Expected SHA-256 hash of agent binary (default: "0" = disabled)

**Note:** The configuration file must be created manually. The installer will copy the sample if it doesn't exist.

**Location:** `/Library/Application Support/MacPatch/gov.llnl.mp.lazarus.plist`

To create the directory:
```bash
sudo mkdir -p "/Library/Application Support/MacPatch"
```

## Server Setup

For Lazarus to download and install packages, you need to host two files on your MacPatch server.

**Important**: The server hostname is configured via the `mpserver` key in the configuration file. The examples below use `mpprod.llnl.gov` but you should replace this with your actual server.

### 1. Package Information Plist

**Location:** `https://{mpserver}/mp-content/lazarus/gov.llnl.lazarus.plist`

Where `{mpserver}` is the value from your configuration file (e.g., `mpprod.llnl.gov`).

This plist contains information about the latest package:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Package</key>
    <array>
        <dict>
            <key>MacPatch</key>
            <string>MacPatch.pkg</string>
            <key>Version</key>
            <string>4.4.2.0</string>
            <key>MinVersion</key>
            <string>4.3.3.0</string>
            <key>PkgHash</key>
            <string>e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855</string>
        </dict>
    </array>
</dict>
</plist>
```

**Fields:**
- `MacPatch`: Package filename
- `Version`: Package version (must be parseable like "4.4.2.0")
- `MinVersion`: **NEW** - Minimum required agent version (optional, overrides client config)
- `PkgHash`: SHA-256 hash of the package file (used for verification)

**Important**: The `MinVersion` field allows you to centrally manage the minimum version requirement:
- If present, it overrides the `minversion` in the client's config file
- When you release version 4.4.0, set `MinVersion` to 4.3.3 to require all agents upgrade
- All clients automatically get the new requirement without touching their configs
- If omitted, clients fall back to their local `minversion` setting

### 2. Package File

**Location:** `https://{mpserver}/mp-content/lazarus/pkg/{MacPatch}`

Where:
- `{mpserver}` is the value from your configuration file
- `{MacPatch}` is the filename from the plist (e.g., `MacPatch.pkg`)

**Important:**
- The SHA-256 hash of this file MUST match the `PkgHash` in the plist
- Lazarus will refuse to install if the hash doesn't match
- To generate the hash: `shasum -a 256 MacPatch.pkg`

### Server Directory Structure

On your MacPatch server, create this structure:

```
/opt/MacPatch/Content/Web/lazarus/
├── gov.llnl.lazarus.plist          # Package information
└── pkg/
    └── MacPatch.pkg                # Actual installer package
```

The files will be accessible at:
- `https://{your-server}/mp-content/lazarus/gov.llnl.lazarus.plist`
- `https://{your-server}/mp-content/lazarus/pkg/MacPatch.pkg`

See `sample-lazarus-server.plist` for a complete example.

## Logs

All output (application logs, stdout, and stderr) is written to:
- `/Library/Logs/mp_lazarus.log`

## Usage

### Command-Line Options

```bash
lazarus [OPTIONS]
```

**OPTIONS:**
- `--dry-run`, `--test`, `-n` - Check if installation is needed without installing
- `--once` - Run checks once and exit (don't loop)
- `--version`, `-v` - Show version information
- `--help`, `-h` - Show help message

### Examples

**Test if installation is needed (dry-run):**
```bash
sudo /usr/local/sbin/lazarus --dry-run --once
```

Example output when checks pass:
```
🔍 Lazarus - Dry Run Mode
   No changes will be made

✅ Health checks PASSED

All checks:
  ✓ Agent binary exists
  ✓ Agent version meets minimum requirement
  ✓ Agent has checked in recently

Action: No installation needed
```

Example output when checks fail:
```
🔍 Lazarus - Dry Run Mode
   No changes will be made

❌ Health checks FAILED (2 issues)

Failed checks:
  1. Agent version below minimum required (3.6.1.11)
  2. Agent hasn't checked in within 15 days

Action: Installation WOULD be triggered
        Package would be downloaded from: https://mpprod.llnl.gov/mp-content/lazarus/
```

**Run checks once:**
```bash
sudo /usr/local/sbin/lazarus --once
```

**Show help:**
```bash
/usr/local/sbin/lazarus --help
```

## Management

### Check daemon status
```bash
sudo launchctl list | grep lazarus
```

### Restart the daemon
```bash
sudo launchctl kickstart -k system/com.llnl.mp.lazarus
```

### Unload the daemon
```bash
sudo launchctl unload /Library/LaunchDaemons/com.llnl.mp.lazarus.plist
```

### View logs
```bash
tail -f /Library/Logs/mp_lazarus.log
```

## Troubleshooting

### Daemon not running
Check if the daemon is loaded:
```bash
sudo launchctl list | grep lazarus
```

If not loaded, load it:
```bash
sudo launchctl load /Library/LaunchDaemons/com.llnl.mp.lazarus.plist
```

### Check logs for errors
```bash
tail -50 /Library/Logs/mp_lazarus.log
```

### Manual test
Run the daemon manually (will run continuously, press Ctrl+C to stop):
```bash
sudo /usr/local/sbin/lazarus
```

### Permissions
Ensure the binary and plist have correct ownership:
```bash
ls -la /usr/local/sbin/lazarus
ls -la /Library/LaunchDaemons/com.llnl.mp.lazarus.plist
```

### Daemon keeps restarting
If the daemon exits unexpectedly, LaunchDaemon will automatically restart it (KeepAlive: true). Check the logs to see why it's exiting.

## Development

To test during development:
```bash
swift run
```

To build for release:
```bash
swift build -c release
```
