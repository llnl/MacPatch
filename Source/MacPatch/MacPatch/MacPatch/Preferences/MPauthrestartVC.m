//
//  MPauthrestartVC.m
//  MacPatch
//
//  Created by Charles Heizer on 2/26/20.
//  Copyright © 2020 Heizer, Charles. All rights reserved.
//

#import "MPauthrestartVC.h"
#import "MacPatch.h"

@interface MPauthrestartVC ()

// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation MPauthrestartVC

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
	dispatch_async(dispatch_get_main_queue(), ^{
		[[self.view.window standardWindowButton:NSWindowCloseButton] setHidden:YES];
		[[self.view.window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
		[[self.view.window standardWindowButton:NSWindowZoomButton] setHidden:YES];
		self.errImage.hidden = YES;
		self.errMsg.stringValue = @"";
	});
}

- (IBAction)saveAuthrestart:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self.errImage.hidden = YES;
		self.errMsg.stringValue = @"";
	});
	
	// Check is user account is valid
	BOOL isValidUser = NO;
	isValidUser =  [self validFileVaultUser:self.userName.stringValue];
	
	// Check if account is in FV user array.
	if (!isValidUser) {
		dispatch_async(dispatch_get_main_queue(), ^{
			self.errImage.hidden = NO;
			self.errMsg.stringValue = @"Error, not a FileVault user.";
		});
		return;
	}
	
	if (![self validUserPassword]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			self.errImage.hidden = NO;
			self.errMsg.stringValue = @"Error, password does not match system.";
		});
		return;
	}
	
	NSError *err = nil;
	MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
	[kc createKeyChain:MP_AUTHSTATUS_KEYCHAIN];
	
	MPPassItem *pi = [MPPassItem new];
	[pi setUserName:self.userName.stringValue];
	[pi setUserPass:self.userPass.stringValue];
	
	[kc savePassItemWithService:pi service:@"mpauthrestart" error:&err];
	if (err) {
		qlerror(@"%@",err.localizedDescription);
		dispatch_async(dispatch_get_main_queue(), ^{
			self.errImage.hidden = NO;
			self.errMsg.stringValue = @"Error Saving Credentials.";
		});
		return;
	} else {
		[self writeAuthStatusToPlist:self.userName.stringValue enabled:YES];
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"authStateNotify" object:nil userInfo:@{}];
	[self.view.window close];
}

- (IBAction)showAuthrestart:(id)sender
{
	NSError *err = nil;
	MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
	MPPassItem *pi = [kc retrievePassItemForService:@"mpauthrestart" error:&err];
	NSDictionary *d = [pi toDictionary];
	NSLog(@"%@",d);
	
}

- (IBAction)closeWindow:(id)sender
{
	[self.view.window close];
}

- (void)writeAuthStatusToPlist:(NSString *)authUser enabled:(BOOL)aEnabled
{
	NSDictionary *authStatus = @{@"user":authUser,@"enabled":[NSNumber numberWithBool:aEnabled],@"outOfSync":[NSNumber numberWithBool:NO]};
	[authStatus writeToFile:MP_AUTHSTATUS_FILE atomically:NO];
}

- (BOOL)clearAuthStatus
{
	NSError *err = nil;
	NSFileManager *fs = [NSFileManager defaultManager];
	if ([fs fileExistsAtPath:MP_AUTHSTATUS_KEYCHAIN]) {
		[fs removeItemAtPath:MP_AUTHSTATUS_KEYCHAIN error:&err];
	}
	if ([fs fileExistsAtPath:MP_AUTHSTATUS_FILE]) {
		NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
		[d setObject:[NSNumber numberWithBool:NO] forKey:@"enabled"];
		[d setObject:@"" forKey:@"user"];
		[d setObject:[NSNumber numberWithBool:NO] forKey:@"outOfSync"];
		[d writeToFile:MP_AUTHSTATUS_FILE atomically:NO];
	}
	if (err) {
		qlerror(@"Error clearing authrestart from keychain.");
		qlerror(@"%@",err.localizedDescription);
		return FALSE;
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"authStateNotify" object:nil userInfo:@{}];
	return YES;
}

- (BOOL)validFileVaultUser:(NSString *)user
{
	__block BOOL result = NO;
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError)
	{
		if (connectError != nil)
		{
			qlerror(@"connectError: %@",connectError.localizedDescription);
		}
		else
		{
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"proxyError: %@",proxyError.localizedDescription);
			}] getFileVaultUsers:^(NSArray *users) {
				
				if (users.count > 0) {
					for (NSString *u in users) {
						if ([u isEqualToString:user]) {
							result = YES;
							break;
						}
					}
				}
				
				dispatch_semaphore_signal(sem);
			}];
		}
	}];
	
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	return result;
}

- (BOOL)validUserPassword
{
	BOOL result = NO;
	DHCachedPasswordUtil *dhc = [DHCachedPasswordUtil new];
	result = [dhc checkPassword:self.userPass.stringValue forUserWithName:self.userName.stringValue];
	return result;
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	assert([NSThread isMainThread]);
	if (self.workerConnection == nil) {
		self.workerConnection = [[NSXPCConnection alloc] initWithMachServiceName:kHelperServiceName options:NSXPCConnectionPrivileged];
		self.workerConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProtocol)];
		
		// Register Progress Messeges From Helper
		self.workerConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProgress)];
		self.workerConnection.exportedObject = self;
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
		// We can ignore the retain cycle warning because a) the retain taken by the
		// invalidation handler block is released by us setting it to nil when the block
		// actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
		// will be released when that operation completes and the operation itself is deallocated
		// (notably self does not have a reference to the NSBlockOperation).
		self.workerConnection.invalidationHandler = ^{
			// If the connection gets invalidated then, on the main thread, nil out our
			// reference to it.  This ensures that we attempt to rebuild it the next time around.
			self.workerConnection.invalidationHandler = nil;
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				self.workerConnection = nil;
			}];
		};
#pragma clang diagnostic pop
		[self.workerConnection resume];
	}
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
{
	assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}
@end
