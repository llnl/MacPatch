# LogKit to Native OSLog Migration Guide

## Overview

This project has been migrated from using LogKit to native OSLog (Apple's unified logging system). This provides better integration with macOS, improved performance, and removes an external dependency.

## What Changed

### Files Added
- **AppLogger.swift** - New logging service using OSLog with file rotation

### Files Modified
- **AppDelegate.swift** - Updated to use AppLogger instead of LXLogger
- **ViewController.swift** - Updated to use AppLogger
- **Loggers.swift** - Marked as deprecated (can be removed)

### Files to Remove from Project
After verifying everything works, you can safely delete:
- **Loggers.swift** (and all other LogKit files)
- Remove LogKit from your project dependencies

## AppLogger API

The new `AppLogger` class provides the same API as LogKit with these improvements:

### Key Features

✅ **OSLog Integration** - Logs appear in Console.app with proper categorization  
✅ **File Rotation** - Automatic log file rotation based on size  
✅ **Thread-Safe** - All file operations use a dedicated queue  
✅ **Log Levels** - Debug, Info, Notice, Warning, Error, Critical  
✅ **File & Line Info** - Automatic capture of source location  
✅ **Performance** - Uses native Apple APIs for better efficiency  

### Basic Usage

The API is identical to LogKit, so no code changes are needed for log calls:

```swift
// All these work exactly as before
log.debug("Debug message")
log.info("Info message")
log.notice("Notice message")
log.warning("Warning message")
log.error("Error message")
log.critical("Critical message")
```

### Initialization

```swift
// Simple initialization (uses defaults)
log = AppLogger()

// Full initialization with configuration
log = AppLogger(
    subsystem: "com.macpatch",
    category: "AgentUploader",
    fileURL: URL(fileURLWithPath: logPath),
    numberOfFiles: 7,
    maxFileSizeKB: 10 * 1024,
    minimumLevel: .info
)
```

### Log Levels

```swift
public enum LogLevel: Int {
    case debug      // Detailed debugging information
    case info       // Informational messages
    case notice     // Normal but significant events
    case warning    // Warning messages
    case error      // Error conditions
    case critical   // Critical conditions
}
```

### Setting Minimum Log Level

```swift
// Change log level at runtime
log.setMinimumLevel(.debug)  // Show all logs including debug
log.setMinimumLevel(.info)   // Hide debug logs
```

### File Rotation

Log files are automatically rotated when they reach the maximum size:
- Default: 10MB per file
- Default: 7 files kept in rotation
- Naming: `AgentUploader.log`, `1_AgentUploader.log`, `2_AgentUploader.log`, etc.

### Accessing Log Files

```swift
// Get current log file
let currentLog = log.currentLogFileURL()

// Get all log files (current + rotated)
let allLogs = log.allLogFileURLs()
```

## Migration Changes Made

### Before (LogKit)
```swift
import LogKit

var log = LXLogger()

// In applicationDidFinishLaunching
log = LXLogger(endpoints: [
    LXRotatingFileEndpoint(
        baseURL: URL(fileURLWithPath: logPath),
        numberOfFiles: 7,
        maxFileSizeKiB: (10 * 1024 * 1024),
        minimumPriorityLevel: .all,
        dateFormatter: LXDateFormatter(formatString: "yyyy-MM-dd HH:mm:ss", timeZone: NSTimeZone.local),
        entryFormatter: LXEntryFormatter({ entry in return
            "\(entry.dateTime) [\(entry.level)] [\(entry.fileName)] \(entry.functionName):\(entry.lineNumber) --- \(entry.message)"
        })
    )
])

// Usage
log.debug("Debug message")
log.info("Info message")
log.error("Error message")
```

### After (Native OSLog)
```swift
// No import needed - AppLogger is in the project

var log = AppLogger()

// In applicationDidFinishLaunching
log = AppLogger(
    fileURL: URL(fileURLWithPath: logPath),
    numberOfFiles: 7,
    maxFileSizeKB: 10 * 1024,
    minimumLevel: .info
)

// Usage (identical!)
log.debug("Debug message")
log.info("Info message")
log.error("Error message")
```

## Benefits of Native OSLog

### 1. System Integration
- Logs appear in **Console.app** with proper categorization
- Can filter by subsystem and category
- Uses native log levels (Debug, Info, Default, Error, Fault)

### 2. Performance
- More efficient than file-based logging alone
- Optimized by Apple for minimal overhead
- Automatic log compression

### 3. No External Dependencies
- One less third-party framework to maintain
- Smaller app size
- No breaking changes when updating dependencies

### 4. Better Debugging
- View logs in real-time in Console.app
- Filter by process, subsystem, category, or level
- Search and export capabilities

### 5. Privacy Controls
- Supports public/private log annotations
- Redacts sensitive information automatically
- Complies with Apple's privacy guidelines

## Log File Format

The log file format remains similar to LogKit:

```
2026-03-06 14:30:45 [INFO] [ViewController.swift] processAndUploadAgent(sender:):275 --- Begin Processing Agent Packages
2026-03-06 14:30:46 [DEBUG] [ViewController.swift] getPackagesFromArchiveDir(path:):733 --- Working directory is /tmp/MPAgent/MacPatch
2026-03-06 14:30:47 [ERROR] [ViewController.swift] uploadPackagesToServer(packages:formData:):1389 --- Upload error[500]: Internal Server Error
```

Format: `timestamp [LEVEL] [filename] function:line --- message`

## Viewing Logs

### In Console.app

1. Open **Console.app** (in /Applications/Utilities/)
2. Select your Mac in the sidebar
3. Filter by:
   - **Subsystem**: `com.macpatch` (or your bundle ID)
   - **Category**: `AgentUploader`
   - **Process**: Your app name

### In Log Files

Log files are stored in the same location as before:
- Default: `~/Library/Logs/AgentUploader.log`
- Rotated files: `1_AgentUploader.log`, `2_AgentUploader.log`, etc.

You can still use the "View Log File" menu item to open in Console.app.

## Testing Checklist

After migration, verify:

- [ ] Logs appear in Console.app with correct subsystem/category
- [ ] Log files are created in the correct location
- [ ] File rotation works when files exceed size limit
- [ ] Debug/Info log level switching works
- [ ] All log methods (debug, info, error, etc.) work correctly
- [ ] Source file/line information is captured correctly
- [ ] "View Log File" menu item opens logs in Console.app

## Advanced Usage

### Custom Subsystem and Category

```swift
log = AppLogger(
    subsystem: "com.mycompany.macpatch",
    category: "Networking"
)
```

This helps organize logs in Console.app, especially for larger apps with multiple modules.

### Multiple Loggers

You can create separate loggers for different parts of your app:

```swift
let networkLogger = AppLogger(category: "Network")
let databaseLogger = AppLogger(category: "Database")
let uiLogger = AppLogger(category: "UI")
```

### Dynamic Log Level Changes

```swift
// Enable debug logging
log.setMinimumLevel(.debug)

// Disable debug logging
log.setMinimumLevel(.info)
```

## Troubleshooting

### Logs Not Appearing in Console.app

1. Make sure Console.app is filtering correctly
2. Check that the subsystem matches your bundle identifier
3. Verify the category name is correct
4. Try clearing filters and searching for your process name

### File Permission Issues

If log files can't be written:
```swift
// The logger automatically creates the directory
// But you can verify manually:
let logDir = URL(fileURLWithPath: logPath).deletingLastPathComponent()
try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
```

### Log Rotation Not Working

- Check that `maxFileSizeKB` is set appropriately
- Verify the log directory is writable
- Ensure the app has permission to create/delete files in the log directory

## Performance Considerations

OSLog is designed for high performance:
- Messages are formatted lazily (only if they will be logged)
- File I/O happens on a background queue
- No blocking of the main thread
- Efficient binary format for console logs

## Privacy and Security

OSLog includes privacy features:
- By default, all strings are marked as `%{public}@` in this implementation
- For sensitive data, you can modify the AppLogger to support private logging
- Redaction can be added for PII (Personally Identifiable Information)

## Next Steps

1. **Test the application** with the new logging system
2. **Remove LogKit** from your dependencies
3. **Delete deprecated files** (Loggers.swift and other LogKit files)
4. **Update documentation** if you have any logging guidelines
5. **Configure Console.app** filters for easier debugging

## Additional Resources

- [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging)
- [WWDC Videos on Unified Logging](https://developer.apple.com/videos/play/wwdc2016/721/)
- [Console User Guide](https://support.apple.com/guide/console/)

## Support

If you encounter any issues:
1. Check the Console.app for system-level log messages
2. Verify file permissions in the log directory
3. Review the AppLogger.swift implementation
4. Ensure the log level is set appropriately for the messages you want to see
