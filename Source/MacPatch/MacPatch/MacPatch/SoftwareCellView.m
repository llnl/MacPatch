//
//  SoftwareCellView.m
//  TestTable
//
//  Created by Heizer, Charles on 12/18/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

#import "SoftwareCellView.h"
#import "GlobalQueueManager.h"
#import "MacPatch.h"
#import "SoftwareInstallOperation.h"
#import "SoftwareUninstallOperation.h"

@interface SoftwareCellView ()
{
    NSUserDefaults *defaults;
}

@property (atomic, strong, readwrite) NSXPCConnection *worker;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end


@implementation SoftwareCellView

#pragma mark - Main

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
	
	if (_isAppInstalled) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.actionButton setTitle:@"Uninstall"];
			self->_installedStateImage.image = [NSImage imageNamed:@"GoodImage"];
		});
	}
	
	[self connectToHelperTool];
	//[self setupCell];
    // Drawing code here.
}

// Setup User Notification for Software Install Operation
- (void)setupNotification
{
	NSString *cellStartNote = [NSString stringWithFormat:@"swStart-%@",_rowData[@"id"]];
	NSString *cellProgressNote = [NSString stringWithFormat:@"swProg-%@",_rowData[@"id"]];
	NSString *cellStopNote = [NSString stringWithFormat:@"swStop-%@",_rowData[@"id"]];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 //NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 [self->_actionButton setTitle:@"Installing..."];
		 });
	 }];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		NSDictionary *userInfo = note.userInfo;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (userInfo[@"status"]) {
				self->_swActionStatusText.stringValue = userInfo[@"status"];
			}
		});
	 }];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:cellStopNote object:nil queue:nil usingBlock:^(NSNotification *note)
	{
		NSDictionary *userInfo = note.userInfo;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (userInfo[@"error"]) {
				self->_swActionStatusText.stringValue = userInfo[@"status"];
				[self stopInstallWithError:YES];
			} else {
				[self stopInstallWithError:NO];
			}
		});
	 }];
}

- (void)setupUninstallNotification
{
	NSString *cellStartNote = [NSString stringWithFormat:@"swUnStart-%@",_rowData[@"id"]];
	NSString *cellProgressNote = [NSString stringWithFormat:@"swUnProg-%@",_rowData[@"id"]];
	NSString *cellStopNote = [NSString stringWithFormat:@"swUnStop-%@",_rowData[@"id"]];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 //NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 [self->_actionButton setTitle:@"Uninstalling..."];
		 });
	 }];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 if (userInfo[@"status"]) {
				 self->_swActionStatusText.stringValue = userInfo[@"status"];
			 }
		 });
	 }];
	
	[[NSNotificationCenter defaultCenter] addObserverForName:cellStopNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 if (userInfo[@"error"]) {
				 self->_swActionStatusText.stringValue = userInfo[@"status"];
				 [self stopUninstallWithError:YES];
			 } else {
				 [self stopUninstallWithError:NO];
			 }
		 });
	 }];
}

- (void)removeNotificationObserver
{
	NSString *cellStartNote = [NSString stringWithFormat:@"swStart-%@",_rowData[@"id"]];
	NSString *cellProgressNote = [NSString stringWithFormat:@"swProg-%@",_rowData[@"id"]];
	NSString *cellStopNote = [NSString stringWithFormat:@"swStop-%@",_rowData[@"id"]];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:cellStartNote object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:cellProgressNote object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:cellStopNote object:nil];
}

- (void)removeUninstallNotificationObserver
{
	NSString *cellStartNote = [NSString stringWithFormat:@"swUnStart-%@",_rowData[@"id"]];
	NSString *cellProgressNote = [NSString stringWithFormat:@"swUnProg-%@",_rowData[@"id"]];
	NSString *cellStopNote = [NSString stringWithFormat:@"swUnStop-%@",_rowData[@"id"]];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:cellStartNote object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:cellProgressNote object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:cellStopNote object:nil];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    //NSColor *textColor = (backgroundStyle == NSBackgroundStyleDark) ? [NSColor windowBackgroundColor] : [NSColor controlShadowColor];
    [super setBackgroundStyle:backgroundStyle];
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
	

	NSString *title = [(NSButton *)sender title];
	if ([title isEqualToString:@"Install"])
	{
		[self setupNotification];
		[self setupCellUIForInstall];
		
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			qldebug(@"Operation Queue Count: %lu",(unsigned long)q.globalQueue.operationCount);
			if (q.globalQueue.operationCount > 1) {
			   [self.actionButton setTitle:@"Waiting..."];
			   [self.actionButton setEnabled:NO];
			   [self.actionButton display];
			}
		});
		
		SoftwareInstallOperation *swInst = [[SoftwareInstallOperation alloc] init];
		swInst.swTask = [self.rowData copy];
		[q.globalQueue addOperation:swInst];
	}
	else if ([title isEqualToString:@"Uninstall"])
	{
		[self setupUninstallNotification];
		[self setupCellUIForUninstall];
		
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			qldebug(@"Operation Queue Count: %lu",(unsigned long)q.globalQueue.operationCount);
			if (q.globalQueue.operationCount > 1) {
				[self.actionButton setTitle:@"Waiting..."];
				[self.actionButton setEnabled:NO];
				[self.actionButton display];
			}
		});
		
		SoftwareUninstallOperation *swInst = [[SoftwareUninstallOperation alloc] init];
		swInst.swTask = [self.rowData copy];
		[q.globalQueue addOperation:swInst];
	}
}

- (void)workerStatusText:(NSString *)aStatus
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self->_swActionStatusText.stringValue = aStatus;
	});
}

#pragma mark - Progress Methods
// This is called to clean up the cell on refresh and load
- (void)setupCell
{
	// This will need code to check install state etc
	dispatch_async(dispatch_get_main_queue(), ^{
		// Reset Progressbar and text
		self->_swActionStatusText.stringValue = @" ";
		[self->_progressBar setIndeterminate:YES];
		[self->_progressBar setHidden:YES];
		[self->_progressBar display];
		
		[self.errorImage setHidden:YES];
		//[self.actionButton setTitle:@"Install"];
		[self.actionButton setEnabled:YES];
		[self->_swDescription setFrameSize:NSMakeSize(500.0, 86.0)];
	});
}

- (void)setupCellUIForInstall
{
    dispatch_async(dispatch_get_main_queue(), ^{
		[self->_errorImage setHidden:YES];
		[self->_swDescription setFrameSize:NSMakeSize(350.0, 86.0)]; // Resize the Description Field
        [self->_progressBar setHidden:NO];
        [self->_progressBar startAnimation:nil];
        
        [self->_swActionStatusText setHidden:NO];
        self->_swActionStatusText.stringValue = @"Starting install...";
        [self->_swActionStatusText display];
        
        [self.actionButton setTitle:@"Installing"];
        [self.actionButton setEnabled:NO];
    });
}

- (void)setupCellUIForUninstall
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_errorImage setHidden:YES];
		[self->_swDescription setFrameSize:NSMakeSize(350.0, 86.0)]; // Resize the Description Field
		[self->_progressBar setHidden:NO];
		[self->_progressBar startAnimation:nil];
		
		[self->_swActionStatusText setHidden:NO];
		self->_swActionStatusText.stringValue = @"Starting uninstall...";
		[self->_swActionStatusText display];
		
		[self.actionButton setTitle:@"Uninstalling"];
		[self.actionButton setEnabled:NO];
	});
}

- (void)stopInstallWithError:(BOOL)hadError
{
	[self stopInstallWithError:hadError errorString:nil];
}

- (void)stopInstallWithError:(BOOL)hadError errorString:(NSString *)errStr
{
	BOOL isUninstall = NO;
	if ([self.actionButton.title containsString:@"Uninstall"]) {
		isUninstall = YES;
	}

    dispatch_async(dispatch_get_main_queue(), ^{
        // Reset Progressbar and text
        self->_swActionStatusText.stringValue = @" ";
        [self->_progressBar setIndeterminate:YES];
        [self->_progressBar setHidden:YES];
        [self->_progressBar display];
        
        if (hadError)
		{
			[self.errorImage setHidden:NO];
			if (isUninstall) {
            	[self.actionButton setTitle:@"Uninstall"];
			} else {
				[self.actionButton setTitle:@"Install"];
				self->_installedStateImage.image = [NSImage imageNamed:@"EmptyImage"];
			}
			if (errStr) self->_swActionStatusText.stringValue = errStr;
        }
		else
		{
			if (isUninstall) {
            	[self.actionButton setTitle:@"Install"];
			} else {
				[self.actionButton setTitle:@"Uninstall"];
				self->_installedStateImage.image = [NSImage imageNamed:@"GoodImage"];
			}
        }
		
		[self.actionButton setNextState];
        [self.actionButton setEnabled:YES];
        [self->_swDescription setFrameSize:NSMakeSize(500.0, 86.0)];
    });
	
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil)
		{
			qlerror(@"connectError: %@",connectError.localizedDescription);
		}
		else
		{
			if (!isUninstall)
			{
				[[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
					qlerror(@"proxyError: %@",proxyError.localizedDescription);
				}] recordSoftwareInstallAdd:self->_rowData withReply:^(NSInteger result) {
					qlinfo(@"Code %ld",(long)result);
					[[NSNotificationCenter defaultCenter] postNotificationName:kRefreshSoftwareTable object:nil userInfo:@{}];
				}];
			}
			
		}
	}];
	
	[self removeNotificationObserver];
	
}

- (void)stopUninstallWithError:(BOOL)hadError
{
	[self stopUninstallWithError:hadError errorString:nil];
}

- (void)stopUninstallWithError:(BOOL)hadError errorString:(NSString *)errStr
{
	dispatch_async(dispatch_get_main_queue(), ^{
		// Reset Progressbar and text
		self->_swActionStatusText.stringValue = @" ";
		[self->_progressBar setIndeterminate:YES];
		[self->_progressBar setHidden:YES];
		[self->_progressBar display];
		
		if (hadError)
		{
			[self.errorImage setHidden:NO];
			[self.actionButton setTitle:@"Uninstall"];
			self->_installedStateImage.image = [NSImage imageNamed:@"GoodImage"];
			if (errStr) self->_swActionStatusText.stringValue = errStr;
		}
		else
		{
			[self.actionButton setTitle:@"Install"];
			self->_installedStateImage.image = [NSImage imageNamed:@"EmptyImage"];
		}
		
		[self.actionButton setNextState];
		[self.actionButton setEnabled:YES];
		[self->_swDescription setFrameSize:NSMakeSize(500.0, 86.0)];
	});
	
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil)
		{
			qlerror(@"connectError: %@",connectError.localizedDescription);
		}
		else
		{
			[[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"proxyError: %@",proxyError.localizedDescription);
			}] recordSoftwareInstallRemove:self->_rowData[@"name"] taskID:self->_rowData[@"id"] withReply:^(BOOL result) {
				qlinfo(@"Code %ld",(long)result);
				[[NSNotificationCenter defaultCenter] postNotificationName:kRefreshSoftwareTable object:nil userInfo:@{}];
			}];
		}
	}];
	
	[self removeUninstallNotificationObserver];
}
@end
