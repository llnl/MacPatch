# Quick Reference - All Native APIs

Quick reference for networking, logging, and process execution with native APIs.

---

## 📡 Networking (NetworkService)

### GET Request
```swift
NetworkService.shared.request(url) { response in
    switch response.result {
    case .success(let data):
        print(data)
    case .failure(let error):
        print(error)
    }
}
```

### POST Request with JSON
```swift
NetworkService.shared.request(
    url,
    method: .post,
    parameters: ["key": "value"],
    encoding: .json
) { response in
    // Handle response
}
```

### Synchronous Request
```swift
let response = NetworkService.shared.requestSync(url)
if response.result.isSuccess {
    // Process data
}
```

### Self-Signed Certificates
```swift
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: "yourdomain.com"
)
```

### File Upload
```swift
let formData = MultipartFormData()
formData.append(fileData, withName: "file", fileName: "doc.pdf", mimeType: "application/pdf")
formData.append(jsonData, withName: "data")

NetworkService.shared.upload(
    multipartFormData: formData,
    to: url,
    method: .post,
    headers: ["Accept": "application/json"]
) { response in
    // Handle response
}
```

### Status Code Validation
```swift
if let code = response.statusCode {
    if NetworkService.shared.validateStatusCode(code, in: 200..<300) {
        // Success
    }
}
```

---

## 📝 Logging (AppLogger)

### Log Methods
```swift
log.debug("Debug message")      // Detailed debugging
log.info("Info message")        // General information
log.notice("Notice message")    // Significant events
log.warning("Warning message")  // Warning conditions
log.error("Error message")      // Error conditions
log.critical("Critical message") // Critical conditions
```

### Initialization
```swift
// Simple (uses defaults)
log = AppLogger()

// With configuration
log = AppLogger(
    fileURL: URL(fileURLWithPath: logPath),
    numberOfFiles: 7,
    maxFileSizeKB: 10 * 1024,
    minimumLevel: .info
)
```

### Change Log Level
```swift
log.setMinimumLevel(.debug)  // Show all logs
log.setMinimumLevel(.info)   // Hide debug logs
```

### Access Log Files
```swift
let current = log.currentLogFileURL()
let all = log.allLogFileURLs()
```

---

## 🔧 Process Execution (ProcessRunner)

### Basic Execution
```swift
// Using Spawn (backward compatible)
_ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", source, dest]) { output in
    log.debug(output)
}

// Using ProcessRunner (same thing)
_ = try ProcessRunner(args: ["/usr/bin/command", "arg1", "arg2"]) { output in
    print(output)
}
```

### Check Exit Code
```swift
let runner = try ProcessRunner(args: ["/usr/bin/command"])
if runner.isSuccess {
    print("Success!")
} else {
    print("Failed with code: \(runner.exitCode)")
}
```

### Capture Output
```swift
var output = ""
let runner = try ProcessRunner(args: ["/usr/bin/which", "swift"]) { output += $0 }
print("Output: \(output)")
```

### Convenience Functions
```swift
// Run command with arguments
try runCommand("/usr/bin/ditto", arguments: ["-c", "-k", source, dest])

// Run and capture output
let (exitCode, output) = try runCommandWithOutput("/usr/bin/sw_vers")
```

### Shell Scripts
```swift
// Run shell script
try ProcessRunner.runScript("echo 'Hello' && ls -la")

// Run bash command
try ProcessRunner.runBash("for i in {1..5}; do echo $i; done")
```

### Command Checks
```swift
// Check if command exists
if ProcessRunner.commandExists("git") {
    print("Git is installed")
}

// Get command path
if let path = ProcessRunner.which("git") {
    print("Git: \(path)")
}
```

### Async/Await (macOS 12+)
```swift
if #available(macOS 12.0, *) {
    let (exitCode, output) = try await ProcessRunner.runAsync(
        args: ["/usr/bin/command"],
        streamOutput: true
    )
}
```

---

## 📋 Common Patterns

### Network + Logging
```swift
log.info("Fetching data from \(url)")

NetworkService.shared.request(url) { response in
    switch response.result {
    case .success(let data):
        log.debug("Received: \(data)")
    case .failure(let error):
        log.error("Network error: \(error.localizedDescription)")
    }
}
```

### Process + Logging
```swift
do {
    log.info("Extracting package: \(package)")
    _ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", package, dest]) { output in
        log.debug(output)
    }
    log.info("Extraction complete")
} catch {
    log.error("Extraction failed: \(error)")
    return false
}
```

### Process with Error Detection
```swift
var hasError = false
let runner = try ProcessRunner(args: ["/usr/bin/productsign", ...]) { output in
    log.debug(output)
    if output.contains("error:") {
        log.error(output)
        hasError = true
    }
}

guard runner.isSuccess && !hasError else {
    log.error("Signing failed")
    return false
}
```

---

## 🎯 Error Handling

### Network Errors
```swift
NetworkService.shared.request(url) { response in
    if let statusCode = response.statusCode {
        guard NetworkService.shared.validateStatusCode(statusCode, in: 200..<300) else {
            log.error("HTTP \(statusCode)")
            return
        }
    }
    
    switch response.result {
    case .success(let data):
        // Handle success
    case .failure(let error):
        log.error("Error: \(error.localizedDescription)")
    }
}
```

### Process Errors
```swift
do {
    let runner = try ProcessRunner(args: ["/usr/bin/command"])
    guard runner.isSuccess else {
        log.error("Command failed with code \(runner.exitCode)")
        return false
    }
} catch ProcessError.couldNotLaunch(let reason) {
    log.error("Could not launch: \(reason)")
} catch {
    log.error("Error: \(error)")
}
```

---

## 🔍 Viewing Logs in Console.app

1. Open `/Applications/Utilities/Console.app`
2. Select your Mac in sidebar
3. Filter by:
   - **Subsystem**: `com.macpatch`
   - **Category**: `AgentUploader`
   - **Process**: Your app name

Or search: `subsystem:com.macpatch AND category:AgentUploader`

---

## 📊 Reference Tables

### HTTP Methods
```swift
.get        // GET request
.post       // POST request
.put        // PUT request
.delete     // DELETE request
.patch      // PATCH request
```

### Parameter Encoding
```swift
.url        // URL query parameters (GET)
.json       // JSON body (POST/PUT)
```

### Log Levels (by severity)
```
.debug      ← Lowest priority
.info
.notice
.warning
.error
.critical   ← Highest priority
```

### Process Properties
```swift
.exitCode             // Int32 exit code
.terminationReason    // .exit or .uncaughtSignal
.isSuccess            // true if exit code is 0
.output               // Accumulated output string
```

---

## 🛠️ Common Commands

### Package Management
```swift
// Extract zip
try Spawn(args: ["/usr/bin/ditto", "-x", "-k", zipFile, destDir])

// Create zip
try Spawn(args: ["/usr/bin/ditto", "-c", "-k", sourceDir, zipFile])

// Expand package
try Spawn(args: ["/usr/sbin/pkgutil", "--expand", pkg, expandDir])

// Flatten package
try Spawn(args: ["/usr/sbin/pkgutil", "--flatten", pkg, flatPkg])
```

### Code Signing
```swift
// Sign package
try Spawn(args: ["/usr/bin/productsign", "--sign", identity, pkg, signedPkg])

// Verify signature
try Spawn(args: ["/usr/sbin/pkgutil", "--check-signature", pkg])
```

### File Operations
```swift
// Copy files
try Spawn(args: ["/bin/cp", "-R", source, dest])

// Remove files
try Spawn(args: ["/bin/rm", "-rf", path])

// Create directory
try Spawn(args: ["/bin/mkdir", "-p", path])
```

### System Info
```swift
// macOS version
let (_, version) = try runCommandWithOutput("/usr/bin/sw_vers", arguments: ["-productVersion"])

// System architecture
let (_, arch) = try runCommandWithOutput("/usr/bin/arch")

// Disk space
let (_, space) = try runCommandWithOutput("/usr/bin/df", arguments: ["-h"])
```

---

## ⚡ Performance Tips

### Networking
- Use async methods when possible
- Implement proper error handling
- Cache responses when appropriate
- Configure timeout values appropriately

### Logging
- Use appropriate log levels
- Avoid logging in tight loops
- Use `@autoclosure` for expensive computations
- Let rotation handle file size automatically

### Processes
- Check command existence before execution
- Use full paths to executables
- Capture only needed output
- Handle errors appropriately

---

## 🔒 Security Best Practices

### Networking
```swift
// Only trust specific hosts
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: "specific-host.com"  // Not "*"
)

// Validate status codes
guard NetworkService.shared.validateStatusCode(code, in: 200..<300) else {
    log.error("Invalid response: \(code)")
    return
}
```

### Logging
```swift
// Don't log sensitive data
log.debug("User authenticated")  // ✓ Good
log.debug("Password: \(pass)")   // ✗ Bad

// Use appropriate log levels
log.debug("Detailed info")       // Only in debug
log.error("Critical error")      // Always logged
```

### Processes
```swift
// Use full paths
try ProcessRunner(args: ["/usr/bin/ditto", ...])  // ✓ Good
try ProcessRunner(args: ["ditto", ...])           // ✗ Risky

// Validate input
guard FileManager.default.fileExists(atPath: path) else {
    log.error("File not found: \(path)")
    return false
}
```

---

## 📚 Migration Checklist

### All Three Migrations
- [ ] Add NetworkService.swift
- [ ] Add AppLogger.swift
- [ ] Add ProcessRunner.swift
- [ ] Update network calls
- [ ] Update logging initialization
- [ ] Test all functionality
- [ ] Remove old dependencies
- [ ] Delete deprecated files

### Specific Tests
- [ ] Authentication works
- [ ] File uploads work
- [ ] Logs appear in Console.app
- [ ] Log files rotate correctly
- [ ] Package extraction works
- [ ] Package signing works
- [ ] All error handling works

---

## 🆘 Troubleshooting

### Network Issues
```swift
// Enable detailed logging
log.setMinimumLevel(.debug)

// Check SSL configuration
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: "your-host"
)
```

### Logging Issues
```swift
// Verify log file location
print(log.currentLogFileURL())

// Check Console.app filters
// subsystem:com.macpatch category:AgentUploader
```

### Process Issues
```swift
// Check if command exists
guard ProcessRunner.commandExists("command") else {
    log.error("Command not found")
    return false
}

// Get full path
if let path = ProcessRunner.which("command") {
    log.info("Command: \(path)")
}
```

---

## 📖 Full Documentation

| Topic | Guide |
|-------|-------|
| Networking | [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) |
| Logging | [LOGGING_MIGRATION_GUIDE.md](LOGGING_MIGRATION_GUIDE.md) |
| Processes | [PROCESS_MIGRATION_GUIDE.md](PROCESS_MIGRATION_GUIDE.md) |
| Complete | [COMPLETE_MIGRATION_SUMMARY.md](COMPLETE_MIGRATION_SUMMARY.md) |

---

## 🎉 Summary

You now have **three native implementations** replacing external dependencies:

1. ✅ **NetworkService** - URLSession-based networking
2. ✅ **AppLogger** - OSLog-based logging
3. ✅ **ProcessRunner** - Process-based command execution

**Result:** Zero external dependencies for core functionality! 🚀
