# SwiftShell to Native Process Migration Guide

## Overview

This project has been migrated from using SwiftShell (Spawn) to native Foundation `Process` API. This provides better integration with macOS, improved error handling, and removes an external dependency.

## What Changed

### Files Added
- **ProcessRunner.swift** - Native Process-based command execution

### Files Modified
- **ViewController.swift** - Removed SwiftShell import
- **Spawn.swift** - Marked as deprecated (can be removed)

### Files to Remove from Project
After verifying everything works, you can safely delete:
- **Spawn.swift** (or the entire SwiftShell directory)
- Remove SwiftShell from your project dependencies

## ProcessRunner API

The new `ProcessRunner` class provides the same API as SwiftShell's `Spawn` with improvements:

### Key Features

✅ **Same API** - Drop-in replacement for `Spawn`  
✅ **Native Process** - Uses Foundation's `Process` class  
✅ **Better Error Handling** - Typed errors with descriptions  
✅ **Async Support** - Swift Concurrency support (macOS 12+)  
✅ **Thread-Safe** - Proper queue management for output  
✅ **Exit Codes** - Easy access to termination status  

### Basic Usage

The API is nearly identical to SwiftShell, requiring minimal code changes:

```swift
// Before (SwiftShell)
_ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", source, dest]) { output in
    log.debug(output)
}

// After (ProcessRunner) - EXACTLY THE SAME!
_ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", source, dest]) { output in
    log.debug(output)
}

// Or use the new name
_ = try ProcessRunner(args: ["/usr/bin/ditto", "-x", "-k", source, dest]) { output in
    log.debug(output)
}
```

**Note:** `Spawn` is provided as a typealias to `ProcessRunner` for backward compatibility!

## Migration Examples

### Example 1: Extract Package (ditto)

#### Before (SwiftShell)
```swift
do {
    log.info("Extracting package, \(package)")
    _ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", package, tmpDir]) { str in
        log.debug(str)
    }
} catch {
    log.error("\(error)")
    return false
}
```

#### After (Native Process)
```swift
do {
    log.info("Extracting package, \(package)")
    _ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", package, tmpDir]) { str in
        log.debug(str)
    }
} catch {
    log.error("\(error)")
    return false
}
```

**No changes required!** The code is identical.

### Example 2: Expand Package (pkgutil)

#### Before (SwiftShell)
```swift
_ = try Spawn(args: ["/usr/sbin/pkgutil", "--expand", pkgName, expandedPkgDir]) { str in
    log.debug(str)
}
```

#### After (Native Process)
```swift
_ = try Spawn(args: ["/usr/sbin/pkgutil", "--expand", pkgName, expandedPkgDir]) { str in
    log.debug(str)
}
```

**No changes required!**

### Example 3: Sign Package (productsign)

#### Before (SwiftShell)
```swift
_ = try Spawn(args: ["/usr/bin/productsign", "--sign", identity, package, signedPackage]) { str in
    log.debug("Sign result: \(str)")
    if str.contains(find: "error:") {
        log.error("\(str)")
        hasErr = true
    }
}
```

#### After (Native Process)
```swift
_ = try Spawn(args: ["/usr/bin/productsign", "--sign", identity, package, signedPackage]) { str in
    log.debug("Sign result: \(str)")
    if str.contains(find: "error:") {
        log.error("\(str)")
        hasErr = true
    }
}
```

**No changes required!**

## Advanced Features

### New Features Not in SwiftShell

#### 1. Check Exit Code
```swift
let runner = try ProcessRunner(args: ["/usr/bin/some-command"])
if runner.isSuccess {
    print("Command succeeded!")
} else {
    print("Command failed with exit code: \(runner.exitCode)")
}
```

#### 2. Capture Output
```swift
var output = ""
let runner = try ProcessRunner(args: ["/usr/bin/which", "swift"]) { output += $0 }
print("Swift path: \(output)")
```

#### 3. Convenience Functions
```swift
// Run a command with arguments
try runCommand("/usr/bin/ditto", arguments: ["-c", "-k", source, dest])

// Run and capture output
let (exitCode, output) = try runCommandWithOutput("/usr/bin/sw_vers", arguments: ["-productVersion"])
print("macOS version: \(output)")
```

#### 4. Shell Scripts
```swift
// Run a shell script
let runner = try ProcessRunner.runScript("echo 'Hello' && ls -la")

// Run a bash command
let runner = try ProcessRunner.runBash("for i in {1..5}; do echo $i; done")
```

#### 5. Command Existence Check
```swift
if ProcessRunner.commandExists("git") {
    print("Git is installed")
}

if let gitPath = ProcessRunner.which("git") {
    print("Git location: \(gitPath)")
}
```

#### 6. Async/Await (macOS 12+)
```swift
if #available(macOS 12.0, *) {
    let (exitCode, output) = try await ProcessRunner.runAsync(
        args: ["/usr/bin/sw_vers"],
        streamOutput: true
    )
    print("Exit code: \(exitCode)")
}
```

## Error Handling

ProcessRunner provides typed errors with better descriptions:

```swift
public enum ProcessError: Error {
    case couldNotLaunch(String)      // Failed to start process
    case terminatedAbnormally(Int32)  // Process crashed or was killed
    case outputError(String)          // Error reading output
}
```

### Example Error Handling
```swift
do {
    let runner = try ProcessRunner(args: ["/usr/bin/some-command"])
    if !runner.isSuccess {
        log.error("Command failed with exit code \(runner.exitCode)")
    }
} catch ProcessError.couldNotLaunch(let reason) {
    log.error("Could not launch: \(reason)")
} catch ProcessError.terminatedAbnormally(let code) {
    log.error("Process crashed with code: \(code)")
} catch {
    log.error("Unknown error: \(error)")
}
```

## Properties and Methods

### ProcessRunner Properties

```swift
.exitCode: Int32                          // Exit code of the process
.terminationReason: TerminationReason     // How the process ended
.isSuccess: Bool                          // true if exit code is 0
.output: String                           // All accumulated output
```

### ProcessRunner Static Methods

```swift
.runScript(_:output:)                     // Run a shell script
.runBash(_:output:)                       // Run a bash command
.commandExists(_:)                        // Check if command exists
.which(_:)                                // Get path to command
.runAsync(args:streamOutput:)             // Run asynchronously (macOS 12+)
```

## Comparison: SwiftShell vs ProcessRunner

| Feature | SwiftShell (Spawn) | ProcessRunner |
|---------|-------------------|---------------|
| **Execute commands** | ✅ | ✅ |
| **Capture output** | ✅ | ✅ |
| **Output closure** | ✅ | ✅ |
| **Error handling** | Basic | Enhanced |
| **Exit code access** | ❌ | ✅ |
| **Thread safety** | ❌ | ✅ |
| **Async/await** | ❌ | ✅ |
| **Helper methods** | Limited | Extensive |
| **Type safety** | ❌ | ✅ |
| **Native API** | ❌ | ✅ |

## Benefits of Native Process API

### 1. No External Dependencies
- ✅ One less third-party framework
- ✅ Smaller app binary
- ✅ Faster build times
- ✅ Easier maintenance

### 2. Better Integration
- ✅ Native Foundation API
- ✅ Proper process lifecycle management
- ✅ Built-in pipe handling
- ✅ macOS security features

### 3. Enhanced Features
- ✅ Better error handling
- ✅ Exit code inspection
- ✅ Termination reason tracking
- ✅ Swift Concurrency support

### 4. Safety
- ✅ Thread-safe output handling
- ✅ Proper memory management
- ✅ No unsafe pointer manipulation
- ✅ Type-safe API

## Testing Checklist

After migration, verify:

- [ ] Package extraction (ditto -x -k)
- [ ] Package expansion (pkgutil --expand)
- [ ] Package flattening (pkgutil --flatten)
- [ ] Package signing (productsign)
- [ ] Package compression (ditto -c -k)
- [ ] Output is captured correctly
- [ ] Errors are handled properly
- [ ] No crashes or hangs

## Common Patterns

### Pattern 1: Execute and Log Output
```swift
try ProcessRunner(args: ["/usr/bin/command", "arg1", "arg2"]) { output in
    log.debug(output)
}
```

### Pattern 2: Execute and Check Success
```swift
let runner = try ProcessRunner(args: ["/usr/bin/command"])
guard runner.isSuccess else {
    log.error("Command failed with exit code \(runner.exitCode)")
    return false
}
return true
```

### Pattern 3: Execute and Capture Output
```swift
var capturedOutput = ""
let runner = try ProcessRunner(args: ["/usr/bin/command"]) { output in
    capturedOutput += output
}
print("Output: \(capturedOutput)")
```

### Pattern 4: Execute and Check for Errors in Output
```swift
var hasError = false
let runner = try ProcessRunner(args: ["/usr/bin/productsign", ...]) { output in
    log.debug(output)
    if output.contains("error:") {
        log.error(output)
        hasError = true
    }
}
```

## Troubleshooting

### Process Not Found
```swift
// Check if command exists
guard ProcessRunner.commandExists("some-command") else {
    log.error("Command not found")
    return false
}

// Or get full path
guard let commandPath = ProcessRunner.which("some-command") else {
    log.error("Command not found")
    return false
}
```

### Permission Denied
```swift
do {
    try ProcessRunner(args: ["/usr/bin/command"])
} catch ProcessError.couldNotLaunch(let reason) {
    if reason.contains("Permission denied") {
        log.error("Need elevated permissions")
    }
}
```

### Command Hangs
```swift
// ProcessRunner automatically handles process completion
// If a command hangs, it's likely the command itself
// You may need to add timeout logic at a higher level
```

## Migration Steps

1. **Add ProcessRunner.swift** to your project
2. **Build the project** - no code changes needed!
3. **Test all functionality** using the checklist above
4. **Remove SwiftShell** from dependencies:
   ```bash
   # Swift Package Manager
   # Remove from Package.swift dependencies
   
   # CocoaPods
   # Remove from Podfile
   
   # Carthage
   # Remove from Cartfile
   ```
5. **Delete Spawn.swift** or SwiftShell directory
6. **Update package manager**:
   ```bash
   swift package update  # SPM
   pod install          # CocoaPods
   carthage update      # Carthage
   ```

## Performance Considerations

### SwiftShell (Spawn)
- Used `posix_spawn` directly
- Manual pthread management
- Unsafe pointer manipulation
- Manual pipe handling

### ProcessRunner (Native Process)
- Uses Foundation's `Process` class
- Automatic thread management via GCD
- Safe Swift APIs
- Built-in pipe handling

**Result:** Similar or better performance with safer code.

## API Reference

### Initialization

```swift
// Basic usage (same as Spawn)
try ProcessRunner(args: ["/usr/bin/command", "arg1", "arg2"])

// With output closure
try ProcessRunner(args: ["/usr/bin/command"]) { output in
    print(output)
}

// Using Spawn alias (backward compatible)
try Spawn(args: ["/usr/bin/command"]) { output in
    print(output)
}
```

### Convenience Functions

```swift
// Run command with arguments
try runCommand("/usr/bin/ditto", arguments: ["-c", "-k", source, dest])

// Run and capture output
let (exitCode, output) = try runCommandWithOutput("/usr/bin/command", arguments: ["arg"])

// Run shell script
try ProcessRunner.runScript("echo 'Hello World'")

// Run bash command
try ProcessRunner.runBash("for i in {1..5}; do echo $i; done")

// Check command existence
if ProcessRunner.commandExists("git") { }

// Get command path
if let path = ProcessRunner.which("swift") { }
```

### Async/Await (macOS 12+)

```swift
let (exitCode, output) = try await ProcessRunner.runAsync(
    args: ["/usr/bin/command"],
    streamOutput: true
)
```

## Best Practices

### 1. Always Handle Errors
```swift
do {
    try ProcessRunner(args: [...])
} catch {
    log.error("Process failed: \(error)")
    return false
}
```

### 2. Check Exit Codes
```swift
let runner = try ProcessRunner(args: [...])
guard runner.isSuccess else {
    log.error("Failed with code: \(runner.exitCode)")
    return false
}
```

### 3. Log Output for Debugging
```swift
try ProcessRunner(args: [...]) { output in
    log.debug(output)
}
```

### 4. Use Full Paths
```swift
// Good
try ProcessRunner(args: ["/usr/bin/ditto", ...])

// Avoid (PATH-dependent)
try ProcessRunner(args: ["ditto", ...])
```

## Next Steps

1. Build and test your application
2. Verify all process execution works correctly
3. Remove SwiftShell from dependencies
4. Delete deprecated Spawn.swift file
5. Consider using new features like exit code checking

## Support

If you encounter any issues:
- Check the command exists: `ProcessRunner.commandExists("command")`
- Verify the path: `ProcessRunner.which("command")`
- Check exit codes: `runner.exitCode`
- Review error messages in catch blocks
- Enable debug logging to see command output

## Additional Resources

- [Apple Process Documentation](https://developer.apple.com/documentation/foundation/process)
- [Foundation Pipes](https://developer.apple.com/documentation/foundation/pipe)
- [Task Management Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TaskManagement/)
