//
//  MPauthrestartVC.m
/*
Copyright (c) 2024, Lawrence Livermore National Security, LLC.
Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
Written by Charles Heizer <heizer1 at llnl.gov>.
LLNL-CODE-636469 All rights reserved.

This file is part of MacPatch, a program for installing and patching
software.

MacPatch is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License (as published by the Free
Software Foundation) version 2, dated June 1991.

MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License along
with MacPatch; if not, write to the Free Software Foundation, Inc.,
59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*/

#import "MPauthrestartVC.h"
#import "MacPatch.h"

@interface MPauthrestartVC ()

// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation MPauthrestartVC

@synthesize useRecoveryKeyCheckBox;

- (void)viewDidLoad
{
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
	__block BOOL useKey = NO;
	
	isValidUser =  [self validFileVaultUser:self.userName.stringValue];
	useKey = (int)[useRecoveryKeyCheckBox state] == 1 ? YES : NO;
	qlinfo(@"useRecoveryKeyCheckBox: %@",useKey ? @"YES" : @"NO");
	// Check if account is in FV user array.
	if (!isValidUser) {
		dispatch_async(dispatch_get_main_queue(), ^{
			self.errImage.hidden = NO;
			self.errMsg.stringValue = @"Error, not a FileVault user.";
		});
		return;
	}
	
	if (!useKey) { // If using a recovery key, ignore ... for now ;)
		if (![self validUserPassword]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				self.errImage.hidden = NO;
				self.errMsg.stringValue = @"Error, password does not match system.";
			});
			return;
		}
	}
	
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError)
	{
		if (connectError != nil)
		{
			qlerror(@"connectError: %@",connectError.localizedDescription);
			dispatch_semaphore_signal(sem);
		}
		else
		{
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"proxyError: %@",proxyError.localizedDescription);
				dispatch_async(dispatch_get_main_queue(), ^{
					self->_errImage.hidden = NO;
					self->_errMsg.stringValue = [NSString stringWithFormat:@"Error Saving Credentials. %@",proxyError.localizedDescription];
				});
				dispatch_semaphore_signal(sem);
				
			}] setAuthrestartDataForUser:self.userName.stringValue userPass:self.userPass.stringValue useRecoveryKey:useKey withReply:^(NSError *err, NSInteger result) {
				if (err) {
					qlerror(@"%@",err.localizedDescription);
					dispatch_async(dispatch_get_main_queue(), ^{
						self.errImage.hidden = NO;
						self.errMsg.stringValue = @"Error Saving Credentials.";
					});
				} else {
					if (result != 0) {
						qlerror(@"Unable to set user and password for authrestart.");
                    } else {
                        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
                        [d setBool:YES forKey:@"authRestartEnabled"];
                        [d synchronize];
                    }
				}
				dispatch_semaphore_signal(sem);
			}];
		}
	}];
	
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"authStateNotify" object:nil userInfo:@{}];
	[self.view.window close];
}

- (IBAction)closeWindow:(id)sender
{
	[self.view.window close];
}

- (BOOL)clearAuthStatus
{
	__block BOOL res = NO;
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
			}] clearAuthrestartData:^(NSError *err, BOOL result) {
				if (err) {
					qlerror(@"%@",err.localizedDescription);
				} else {
                    if (result) {
                        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
                        [d setBool:NO forKey:@"authRestartEnabled"];
                        [d synchronize];
                    }
					res = result;
				}
				dispatch_semaphore_signal(sem);
			}];
		}
	}];
	
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"authStateNotify" object:nil userInfo:@{}];
	return res;
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
