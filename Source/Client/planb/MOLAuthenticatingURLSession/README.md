# MOLAuthenticatingURLSession
A wrapper around `NSURLSession` providing validation of server certificates 
and easy-to-use client certificate authentication.

Requires ARC. Tested on OS X 10.11+.

## Usage

```objc

#import <MOLAuthenticatingURLSession/MOLAuthenticatingURLSession.h>

- (void)postToServer {
  MOLAuthenticatingURLSession *authURLSession = [[MOLAuthenticatingURLSession alloc] init];
  authURLSession.userAgent = @"MyUserAgent";
  authURLSession.refusesRedirects = YES;
  authURLSession.serverHostname = @"my-hostname.com";
  NSURLSession *session = authURLSession.session;
  // You can use the NSURLSession as you would normally..
}
```

If you'd like to print status/error information:

```objc
  authURLSession.loggingBlock = ^(NSString *line) {
    NSLog(@"%@", line);
  };
```

## Installation

Install using CocoaPods.

```
pod 'MOLAuthenticatingURLSession'
```

You can also import the project manually but this isn't tested.

## Documentation

Reference documentation is at CocoaDocs.org:

http://cocoadocs.org/docsets/MOLAuthenticatingURLSession

## Contributing

Patches to this library are very much welcome.
Please see the [CONTRIBUTING](https://github.com/google/macops-molauthenticatingurlsession/blob/master/CONTRIBUTING.md) file.
