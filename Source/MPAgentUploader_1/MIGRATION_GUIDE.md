# Alamofire to Native URLSession Migration Guide

## Overview

This project has been migrated from using Alamofire to native URLSession APIs. This document outlines the changes made and how to use the new networking layer.

## What Changed

### Files Added
- **NetworkService.swift** - New networking service using URLSession with the same interface as Alamofire

### Files Modified
- **AppDelegate.swift** - Removed Alamofire import and global session
- **Constants.swift** - Removed Alamofire import
- **AuthViewController.swift** - Updated to use NetworkService
- **ViewController.swift** - Updated all network calls to use NetworkService
- **FileUploader.swift** - Marked as deprecated (already commented out)
- **Alamofire-Synchronous.swift** - Marked as deprecated (can be removed)

### Files to Remove from Project
After verifying everything works, you can safely delete:
- **Alamofire-Synchronous.swift**
- **FileUploader.swift**
- Remove Alamofire from your project dependencies (Package.swift or Podfile)

## NetworkService API

The new `NetworkService` class provides a familiar API that closely matches Alamofire's interface:

### Basic Usage

```swift
// Async GET request
NetworkService.shared.request("https://api.example.com/data") { response in
    switch response.result {
    case .success(let data):
        print("Success: \(data)")
    case .failure(let error):
        print("Error: \(error)")
    }
}

// Async POST request with JSON parameters
NetworkService.shared.request(
    url,
    method: .post,
    parameters: ["key": "value"],
    encoding: .json
) { response in
    // Handle response
}

// Synchronous request (uses semaphore internally)
let response = NetworkService.shared.requestSync(url)
switch response.result {
case .success(let data):
    print("Success: \(data)")
case .failure(let error):
    print("Error: \(error)")
}
```

### Self-Signed Certificate Support

```swift
// Configure once at app startup or before making requests
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: "yourdomain.com"
)
```

### Multipart Form Data Upload

```swift
let multipartFormData = MultipartFormData()

// Append files
multipartFormData.append(
    fileData,
    withName: "file",
    fileName: "document.pdf",
    mimeType: "application/pdf"
)

// Append JSON data
multipartFormData.append(jsonData, withName: "data")

// Upload
NetworkService.shared.upload(
    multipartFormData: multipartFormData,
    to: url,
    method: .post,
    headers: ["Accept": "application/json"]
) { response in
    // Handle response
}
```

### Status Code Validation

```swift
let response = NetworkService.shared.requestSync(url)

// Check status code
if let statusCode = response.statusCode {
    if NetworkService.shared.validateStatusCode(statusCode, in: 200..<300) {
        // Success
    } else {
        // Handle error
    }
}
```

## Migration Changes Made

### Before (Alamofire)
```swift
import Alamofire

var MPAlamofire = Alamofire.Session()

// Configure for self-signed certs
MPAlamofire = {
    let manager = ServerTrustManager(evaluators: [host: DisabledTrustEvaluator()])
    let session = Session(serverTrustManager: manager)
    return session
}()

// Make request
MPAlamofire.request(url, method: .post, parameters: params, encoding: JSONEncoding.default)
    .validate()
    .responseJSON { response in
        // Handle response
    }

// Upload
AF.upload(multipartFormData: { multipartFormData in
    multipartFormData.append(data, withName: "file")
}, to: url, method: .post, headers: headers)
.validate(statusCode: 200..<300)
.responseJSON { response in
    // Handle response
}
```

### After (Native URLSession)
```swift
// Configure for self-signed certs
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: host
)

// Make request
NetworkService.shared.request(
    url,
    method: .post,
    parameters: params,
    encoding: .json
) { response in
    // Handle response (same structure)
}

// Upload
let formData = MultipartFormData()
formData.append(data, withName: "file")

NetworkService.shared.upload(
    multipartFormData: formData,
    to: url,
    method: .post,
    headers: headers
) { response in
    // Handle response (same structure)
}
```

## Benefits of Native URLSession

1. **No External Dependencies** - One less third-party dependency to maintain
2. **Smaller App Size** - No need to bundle Alamofire framework
3. **Better Performance** - Direct use of Apple's networking APIs
4. **Future-Proof** - Native APIs are maintained by Apple
5. **Same Interface** - Familiar API makes migration painless

## Testing Checklist

After migration, test the following functionality:

- [ ] Authentication requests (POST with JSON)
- [ ] Token validation requests (GET)
- [ ] Agent configuration requests (GET)
- [ ] File upload with multipart form data
- [ ] Self-signed certificate handling
- [ ] Error handling and status code validation
- [ ] Synchronous request operations

## Troubleshooting

### SSL/TLS Issues
If you encounter SSL certificate issues:
```swift
NetworkService.shared.configureSession(
    allowSelfSigned: true,
    trustedHost: "your-server-hostname"
)
```

### Timeout Issues
Adjust timeouts in NetworkService.swift:
```swift
configuration.timeoutIntervalForRequest = 30  // Increase if needed
configuration.timeoutIntervalForResource = 300  // Increase if needed
```

### Content-Type Issues
The NetworkService automatically sets proper Content-Type headers:
- `application/json` for JSON encoding
- `multipart/form-data; boundary=...` for uploads

## Next Steps

1. Build and test the application
2. Remove Alamofire from your dependencies
3. Delete the deprecated files (Alamofire-Synchronous.swift, FileUploader.swift)
4. Update your package manager files (Package.swift, Podfile, or Cartfile)

## Support

If you encounter any issues with the migration, check:
- NetworkService.swift implementation
- Console logs for detailed error messages
- HTTP status codes in the response objects
