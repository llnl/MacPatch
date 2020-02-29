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
	
	BOOL isValidUser = NO;
	MPFileVaultInfo *fvi = [MPFileVaultInfo new];
	[fvi runFDESetupCommand:@"list"];
	NSArray *fvUsers = [fvi userArray];
	for (NSString *u in fvUsers) {
		if ([u isEqualToString:self.userName.stringValue]) {
			isValidUser = YES;
		}
	}
	
	// Check if account is in FV user array.
	if (!isValidUser) {
		dispatch_async(dispatch_get_main_queue(), ^{
			self.errImage.hidden = NO;
			self.errMsg.stringValue = @"Error, not a FileVault user.";
		});
		return;
	}
	
	
	NSError *err = nil;
	MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
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

@end
