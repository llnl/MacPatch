//
//  PrefsUpdatesVC.m
//  MacPatch
//
//  Created by Charles Heizer on 2/27/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import "PrefsUpdatesVC.h"
#import "MPauthrestartVC.h"

@interface PrefsUpdatesVC ()

@property (nonatomic, readwrite, retain) NSString *windowTitle;
@property (nonatomic, weak) IBOutlet NSTextField *authState;

// XPC Connection

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation PrefsUpdatesVC

@synthesize scanOnLaunchCheckBox;
@synthesize preStageRebootPatchesBox;
@synthesize allowInstallRebootPatchesCheckBox;
@synthesize pausePatchingCheckBox;
@synthesize authState;

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.windowTitle = @"Fool";
	
	[scanOnLaunchCheckBox setState:[self scanOnLaunch]];
	[preStageRebootPatchesBox setState:[self preStageRebootPatches]];
	[allowInstallRebootPatchesCheckBox setState:[self allowInstallRebootPatches]];
	[pausePatchingCheckBox setState:[self pausePatching]];
	[self checkAuthrestartState];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:@"authStateNotify" object:nil queue:nil usingBlock:^(NSNotification *note)
	{
		//NSDictionary *userInfo = note.userInfo;
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"authStateNotify");
			[self checkAuthrestartState];
		});
	}];
}

#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
	return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
	return [NSImage imageNamed:@"UpdatesTemplate"];
}

-(NSString*)toolbarItemLabel
{
	return NSLocalizedString(@"Updates", @"UpdatesToolbarItemLabel");
}

-(NSView*)initialKeyView
{
	//return self.usernameTextField;
	return self.view;
}

- (IBAction)changeScanOnLaunch:(id)sender
{
	int state = (int)[scanOnLaunchCheckBox state];
	qlinfo(@"Scan on launch state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"enableScanOnLaunch"];
	[d synchronize];
}

- (IBAction)changePreStageRebootPatches:(id)sender
{
	int state = (int)[preStageRebootPatchesBox state];
	qlinfo(@"Pre stage reboot patches state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"preStageRebootPatches"];
	[d synchronize];
}

- (IBAction)changeAllowInstallOfRebootPatches:(id)sender
{
	int state = (int)[allowInstallRebootPatchesCheckBox state];
	qlinfo(@"Allow Reboot Patch Installs state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"allowRebootPatchInstalls"];
	[d synchronize];
}

- (IBAction)changePausePatching:(id)sender
{
	int state = (int)[pausePatchingCheckBox state];
	qlinfo(@"Pause patching state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"pausePatching"];
	[d synchronize];
	
	MPPatchingPausedState _state = kPatchingPausedOff;
	if (state == 1) _state = kPatchingPausedOn;

	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
		} else {
			
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"%@",proxyError);
			}] setStateOnPausePatching:_state withReply:^(BOOL result) {
				
				if (result) {
					qlinfo(@"Patching paused state was written sucessfully.");
				} else {
					qlerror(@"Patching paused state was not written sucessfully.");
				}
			}];
			
		}
	}];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"PatchingStateChangedNotification" object:self];
}

- (BOOL)scanOnLaunch
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"enableScanOnLaunch"];
}

- (BOOL)preStageRebootPatches
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"preStageRebootPatches"];
}

- (BOOL)debugLogging
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"enableDebugLogging"];
}

- (BOOL)allowInstallRebootPatches
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"allowRebootPatchInstalls"];
}

- (BOOL)pausePatching
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"pausePatching"];
}

// Run the Auth restart setup to save the user creds
- (IBAction)setupAuthrestart:(id)sender
{
	NSDictionary *authPlist = [NSDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
	if ([authPlist[@"enabled"] boolValue]) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"MacPatch Authrestart Setup"];
		[alert setInformativeText:@"There is an account already setup. If you want to change the account or reset the password, you must clear it first."];
		[alert addButtonWithTitle:@"OK"];
		[alert setAlertStyle:NSAlertStyleCritical];
		[alert runModal];
		return;
	}
	
	MPauthrestartVC *authVC = [MPauthrestartVC new];
	authVC.title = @"";
	[self presentViewControllerAsModalWindow:authVC];
}

// Will show a message if creds are setup and being used
- (void)checkAuthrestartState
{
	NSString *authString = @"";
	NSDictionary *authPlist = [NSDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
	if ([authPlist[@"enabled"] boolValue]) {
		authString = [NSString stringWithFormat:@"%@ is used to bypass filevault for patching.",authPlist[@"user"]];
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->authState setStringValue:authString];
	});
}

// Clear the creds for auth restart
- (IBAction)clearAuthrestart:(id)sender
{
	NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    [alert setMessageText:@"Clear FileVault Authrestart"];
    [alert setInformativeText:@"Are you sure you want to clear the authrestart data?"];
    if([alert runModal] == NSAlertFirstButtonReturn) {
		MPauthrestartVC *authVC = [MPauthrestartVC new];
		[authVC clearAuthStatus];
		[self checkAuthrestartState];
    }
}


#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	//assert([NSThread isMainThread]);
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
				qlerror(@"connection invalidated");
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
	//assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}
@end
