//
//  UpdatesCellView.m
//  MacPatch
//
//  Created by Charles Heizer on 11/15/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import "UpdatesCellView.h"
#import "GlobalQueueManager.h"
#import "UpdateInstallOperation.h"
#import "AppDelegate.h"

@interface UpdatesCellView ()
{
	NSUserDefaults *defaults;
	NSNotificationCenter *nc;
}

@property (atomic, strong, readwrite) NSXPCConnection *worker;

@property (atomic, strong) NSString *cellStartNote;
@property (atomic, strong) NSString *cellProgressNote;
@property (atomic, strong) NSString *cellStopNote;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation UpdatesCellView

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	assert([NSThread isMainThread]);
	if (self.worker == nil) {
		self.worker = [[NSXPCConnection alloc] initWithMachServiceName:kHelperServiceName options:NSXPCConnectionPrivileged];
		self.worker.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProtocol)];
		
		// Register Progress Messeges From Helper
		self.worker.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProgress)];
		self.worker.exportedObject = self;
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
		// We can ignore the retain cycle warning because a) the retain taken by the
		// invalidation handler block is released by us setting it to nil when the block
		// actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
		// will be released when that operation completes and the operation itself is deallocated
		// (notably self does not have a reference to the NSBlockOperation).
		self.worker.invalidationHandler = ^{
			// If the connection gets invalidated then, on the main thread, nil out our
			// reference to it.  This ensures that we attempt to rebuild it the next time around.
			self.worker.invalidationHandler = nil;
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				self.worker = nil;
				qlerror(@"connection invalid ated");
			}];
		};
#pragma clang diagnostic pop
		[self.worker resume];
	}
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
{
	assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	// self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}

#pragma mark - XPC Methods

- (IBAction)runInstall:(NSButton *)sender
{
	GlobalQueueManager *q = [GlobalQueueManager sharedInstance];
	
	if (![sender isKindOfClass:[NSButton class]])
		return;
	
	[self setupNotification];
	[self setupCellInstall];
	
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		qldebug(@"Operation Queue Count: %lu",(unsigned long)q.globalQueue.operationCount);
		if (q.globalQueue.operationCount > 1) {
			[self.updateButton setTitle:@"Waiting..."];
			[self.updateButton setEnabled:NO];
			[self.updateButton display];
		}
	});
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL allowInstall = [defaults boolForKey:@"allowRebootPatchInstalls"];
	BOOL needsReboot = [_rowData[@"restart"] stringToBoolValue];
	
	if (needsReboot && !allowInstall)
	{
		[self stopCellInstallIsRebootPatch];
	}
	else
	{
		UpdateInstallOperation *inst = [[UpdateInstallOperation alloc] init];
		inst.patch = [self.rowData copy];
		[q.globalQueue addOperation:inst];
	}
	
}

- (void)workerStatusText:(NSString *)aStatus
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self->_patchStatus.stringValue = aStatus;
	});
}

// Setup User Notification for Software Install Operation
- (void)setupNotification
{
	NSString *pID = @"NA";
	if ([_rowData[@"type"] isEqualToString:@"Apple"]) {
		pID = _rowData[@"patch"];
		[self->_patchProgressBar setIndeterminate:YES];
	} else {
		pID = _rowData[@"patch_id"];
	}

	nc = [NSNotificationCenter defaultCenter];
	_cellStartNote = [NSString stringWithFormat:@"patchStart-%@",pID];
	_cellProgressNote = [NSString stringWithFormat:@"patchProg-%@",pID];
	_cellStopNote = [NSString stringWithFormat:@"patchStop-%@",pID];
	
	__weak typeof(self) weakSelf = self;
	[nc addObserverForName:_cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 qlinfo(@"%@ was called.",weakSelf.cellStartNote);
		 //NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 [weakSelf.updateButton setTitle:@"Installing..."];
		 });
	 }];
	
	[nc addObserverForName:_cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 qlinfo(@"%@ was called.",weakSelf.cellProgressNote);
		 
		 NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 if (userInfo[@"status"]) {
				 weakSelf.patchStatus.stringValue = userInfo[@"status"];
			 }
		 });
	 }];
	
	[nc addObserverForName:_cellStopNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 qlinfo(@"%@ was called.",weakSelf.cellStopNote);
		 NSDictionary *userInfo = note.userInfo;
		 qlinfo(@"userInfo: %@",userInfo);
		 dispatch_async(dispatch_get_main_queue(), ^{
			 if (userInfo[@"error"]) {
				 weakSelf.patchStatus.stringValue = userInfo[@"status"];
				 [weakSelf stopCellInstallWithError:YES];
			 } else {
				 [weakSelf stopCellInstallWithError:NO];
			 }
		 });
	 }];
}

- (void)removeNotificationObserver
{
	nc = [NSNotificationCenter defaultCenter];
	[nc removeObserver:self name:_cellStartNote object:nil];
	[nc removeObserver:self name:_cellProgressNote object:nil];
	[nc removeObserver:self name:_cellStopNote object:nil];
}

- (void)setupCellInstall
{
	dispatch_async(dispatch_get_main_queue(), ^{
		//[self->_errorImage setHidden:YES];
		
		[self->_patchProgressBar setHidden:NO];
		[self->_patchProgressBar startAnimation:nil];
		
		[self->_patchStatus setHidden:NO];
		self->_patchStatus.stringValue = @"Starting install...";
		[self->_patchStatus display];
		
		[self.updateButton setTitle:@"Installing"];
		[self.updateButton setEnabled:NO];
	});
}

- (void)stopCellInstallWithError:(BOOL)hadError
{
	[self stopCellInstallWithError:hadError errorString:nil];
}

- (void)stopCellInstallWithError:(BOOL)hadError errorString:(NSString *)errStr
{	
	dispatch_async(dispatch_get_main_queue(), ^{
		// Reset Progressbar and text
		self->_patchStatus.stringValue = @" ";
		[self->_patchProgressBar setIndeterminate:YES];
		[self->_patchProgressBar setHidden:YES];
		[self->_patchProgressBar display];
		
		if (hadError)
		{
			qlinfo(@"HadErr");
			//[self.errorImage setHidden:NO];
			[self.updateButton setTitle:@"Install"];
			self->_patchCompletionIcon.hidden = NO;
			self->_patchCompletionIcon.image = [NSImage imageNamed:@"ErrorImage"];
			if (errStr) self->_patchStatus.stringValue = errStr;
			
			[self.updateButton setNextState];
			[self.updateButton setEnabled:YES];
		}
		else
		{
			[self.updateButton setTitle:@"Installed"];
			self->_patchCompletionIcon.hidden = NO;
			self->_patchCompletionIcon.image = [NSImage imageNamed:@"GoodImage"];
			
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSInteger pCount = [defaults integerForKey:@"PatchCount"];
			pCount = pCount - 1;
			[defaults setInteger:pCount forKey:@"PatchCount"];
			[defaults synchronize];
			
			// Now update the dock tile. Note that a more general way to do this would be to observe the highScore property, but we're just keeping things short and sweet here, trying to demo how to write a plug-in.
			if (pCount >= 1) {
				[[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)pCount]];
			} else {
				[[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
			}
		}
	});
	
	
	if (!hadError)
	{
		[self connectAndExecuteCommandBlock:^(NSError * connectError)
		 {
			 if (connectError != nil)
			 {
				 qlerror(@"connectError: %@",connectError.localizedDescription);
			 }
			 else
			 {
				 [[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
					 qlerror(@"proxyError: %@",proxyError.localizedDescription);
				 }] recordPatchInstall:self.rowData withReply:^(NSInteger result) {
					 qlinfo(@"Code %ld",(long)result);
				 }];
			 }
		}];
	}

	[self removeNotificationObserver];
}

- (void)stopCellInstallIsRebootPatch
{
	dispatch_async(dispatch_get_main_queue(), ^{
		// Reset Progressbar and text
		self->_patchStatus.stringValue = @" ";
		[self->_patchProgressBar setIndeterminate:YES];
		[self->_patchProgressBar setHidden:YES];
		[self->_patchProgressBar display];

		[self.updateButton setTitle:@"On Reboot"];
		self->_patchCompletionIcon.hidden = NO;
		self->_patchCompletionIcon.image = [NSImage imageNamed:@"RebootImage"];
	});
	
	[self removeNotificationObserver];
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRebootRequiredNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
	
	
	AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
	[appDelegate showRebootWindow];
	//[appDel <Your method>];
}

@end
