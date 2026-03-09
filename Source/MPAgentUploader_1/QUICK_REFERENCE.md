# Quick Reference - Native APIs

Quick reference for the new native networking and logging APIs.

---

## Networking (NetworkService)

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

## Logging (AppLogger)

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

## Viewing Logs in Console.app

1. Open `/Applications/Utilities/Console.app`
2. Select your Mac in sidebar
3. Filter by:
   - **Subsystem**: `com.macpatch`
   - **Category**: `AgentUploader`
   - **Process**: Your app name

Or search: `subsystem:com.macpatch AND category:AgentUploader`

---

## Common Patterns

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

### Conditional Logging
```swift
#if DEBUG
log.setMinimumLevel(.debug)
#else
log.setMinimumLevel(.info)
#endif
```

### Error Handling
```swift
do {
    try someOperation()
    log.info("Operation succeeded")
} catch {
    log.error("Operation failed: \(error)")
}
```

---

## File Locations

### Log Files
- Current: `~/Library/Logs/AgentUploader.log`
- Rotated: `~/Library/Logs/1_AgentUploader.log`, `2_AgentUploader.log`, etc.

### Console Logs
- View in Console.app
- System logs in `/var/log/`
- User logs in `~/Library/Logs/`

---

## HTTP Methods

```swift
.get        // GET request
.post       // POST request
.put        // PUT request
.delete     // DELETE request
.patch      // PATCH request
```

## Parameter Encoding

```swift
.url        // URL query parameters (GET)
.json       // JSON body (POST/PUT)
```

## Log Levels (by severity)

```
.debug      ← Lowest priority
.info
.notice
.warning
.error
.critical   ← Highest priority
```

---

## Troubleshooting

### Network Issues
```swift
// Check response
if let statusCode = response.statusCode {
    log.error("HTTP \(statusCode)")
}

// Check error
if case .failure(let error) = response.result {
    log.error("Error: \(error.localizedDescription)")
}
```

### Logging Issues
```swift
// Verify log level
log.setMinimumLevel(.debug)

// Check file path
print(log.currentLogFileURL())

// Check in Console.app
// Filter: subsystem:com.macpatch
```

---

## Performance Tips

### Networking
- Use async methods when possible
- Implement proper error handling
- Cache responses when appropriate
- Configure timeout values in NetworkService

### Logging
- Use appropriate log levels
- Avoid logging in tight loops
- Use `@autoclosure` for expensive computations
- Let rotation handle file size

---

## Security Best Practices

### Networking
```swift
// Only trust specific hosts
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: "specific-host.com"  // Not "*"
)

// Validate status codes
guard NetworkService.shared.validateStatusCode(code, in: 200..<300) else {
    log.error("Invalid response code: \(code)")
    return
}
```

### Logging
```swift
// Don't log sensitive data
log.debug("User logged in")  // ✓ Good
log.debug("Password: \(pass)")  // ✗ Bad

// Consider log level
log.debug("Detailed data: \(json)")  // Only in debug builds
```

---

## Migration Checklist

- [ ] Replace Alamofire imports with NetworkService
- [ ] Replace LogKit imports with AppLogger
- [ ] Update network requests to new API
- [ ] Update logging initialization
- [ ] Test all network operations
- [ ] Test all log levels
- [ ] Verify Console.app integration
- [ ] Remove old dependencies
- [ ] Delete deprecated files

---

## Quick Links

- [Full Networking Guide](MIGRATION_GUIDE.md)
- [Full Logging Guide](LOGGING_MIGRATION_GUIDE.md)
- [Complete Summary](MIGRATION_SUMMARY.md)
