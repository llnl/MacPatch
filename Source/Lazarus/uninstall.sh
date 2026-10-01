#!/bin/bash

# Lazarus Uninstallation Script
# This script removes the Lazarus daemon

set -e

INSTALL_PATH="/usr/local/sbin/lazarus"
LAUNCHDAEMON_DIR="/Library/LaunchDaemons"
LAUNCHDAEMON_LABEL="com.llnl.mp.lazarus"

echo "=== MacPatch Lazarus Uninstallation ==="
echo

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Stop and unload daemon
echo "1. Stopping daemon..."
if launchctl list | grep -q "$LAUNCHDAEMON_LABEL"; then
    launchctl stop "$LAUNCHDAEMON_LABEL" 2>/dev/null || true
    launchctl unload "$LAUNCHDAEMON_DIR/$LAUNCHDAEMON_LABEL.plist" 2>/dev/null || true
    echo "   ✓ Daemon stopped and unloaded"
else
    echo "   ℹ Daemon not running"
fi

# Remove LaunchDaemon plist
echo "2. Removing LaunchDaemon plist..."
if [ -f "$LAUNCHDAEMON_DIR/$LAUNCHDAEMON_LABEL.plist" ]; then
    rm "$LAUNCHDAEMON_DIR/$LAUNCHDAEMON_LABEL.plist"
    echo "   ✓ Plist removed"
else
    echo "   ℹ Plist not found"
fi

# Remove binary
echo "3. Removing binary..."
if [ -f "$INSTALL_PATH" ]; then
    rm "$INSTALL_PATH"
    echo "   ✓ Binary removed"
else
    echo "   ℹ Binary not found"
fi

# Ask about logs
echo
read -p "Remove log files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "4. Removing log..."
    rm -f /Library/Logs/mp_lazarus.log
    echo "   ✓ Log removed"
else
    echo "4. Keeping log..."
    echo "   ℹ Log preserved at /Library/Logs/mp_lazarus.log"
fi

# Ask about config
echo
read -p "Remove configuration file? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "5. Removing configuration..."
    rm -f "/Library/Application Support/MacPatch/gov.llnl.mp.lazarus.plist"
    echo "   ✓ Configuration removed"
else
    echo "5. Keeping configuration..."
    echo "   ℹ Configuration preserved at /Library/Application Support/MacPatch/gov.llnl.mp.lazarus.plist"
fi

echo
echo "=== Uninstallation Complete ==="
echo
echo "Lazarus daemon has been removed."
echo
