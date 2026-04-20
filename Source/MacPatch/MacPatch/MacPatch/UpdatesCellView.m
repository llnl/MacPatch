//
//  UpdatesCellView.m
/*
Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "UpdatesCellView.h"
#import "GlobalQueueManager.h"
#import "UpdateInstallOperation.h"
#import "AppDelegate.h"
#import "MPOProgressBar.h"

@interface UpdatesCellView ()
{
	NSUserDefaults *defaults;
	NSNotificationCenter *nc;
}

@property (atomic, strong, readwrite) NSXPCConnection *worker;

@property (atomic, strong) NSString *cellStartNote;
@property (atomic, strong) NSString *cellProgressNote;
@property (atomic, strong) NSString *cellStopNote;
@property (nonatomic, strong) MPOProgressBar *progressBarNew;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation UpdatesCellView

- (void)awakeFromNib
{
    [super awakeFromNib];
    if (!_progressBarNew) {
        _progressBarNew = [[MPOProgressBar alloc] init];
        _progressBarNew.backgroundColor = [NSColor colorWithRed:180.0/255 green:207.0/255 blue:240.0/255 alpha:1.0].CGColor;
        _progressBarNew.fillColor = [NSColor colorWithRed:66.0/255 green:139.0/255 blue:237.0/255 alpha:1.0].CGColor;
        [self.layer addSublayer:_progressBarNew];
        
        NSRect pbar = _patchProgressBar.frame;
        _progressBarNew.frame = CGRectMake(pbar.origin.x, pbar.origin.y + 8, pbar.size.width, 4);
        [_progressBarNew setHidden:YES];
    }
}

// Configure cell UI based on rowData state - called every time cell is reused
- (void)configureCellUI
{
    [self connectToHelperTool];
    
    // Check if this patch is currently installing
    BOOL isInstalling = [_rowData[@"isInstalling"] boolValue];
    
    if (isInstalling) {
        // Patch is currently installing - restore the operation UI from model
        NSNumber *progress = _rowData[@"progress"] ?: @0;
        NSString *statusText = _rowData[@"statusText"] ?: @"Installing...";
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Configure progress bars based on progress value
            if (progress.doubleValue > 0) {
                [self->_patchProgressBar setHidden:YES];
                self.progressBarNew.progressMode = MPOProgressBarModeDeterminate;
                self.progressBarNew.progress = progress.doubleValue / 100.0;
                [self.progressBarNew setHidden:NO];
            } else {
                [self->_patchProgressBar setHidden:YES];
                self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
                [self.progressBarNew startAnimation];
                [self.progressBarNew setHidden:NO];
            }
            
            [self.patchStatus setHidden:NO];
            self.patchStatus.stringValue = statusText;
            
            [self.updateButton setEnabled:NO];
            [self.updateButton setTitle:@"Installing"];
        });
        
        // Re-setup notifications for this specific patch
        [self setupNotification];
        
    } else {
        // Normal state - no operation in progress
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_patchProgressBar setHidden:YES];
            [self.progressBarNew stopAnimation];
            [self.progressBarNew setHidden:YES];
            [self.patchStatus setHidden:YES];
            self.patchStatus.stringValue = @"";
            
            [self.updateButton setTitle:@"Install"];
            [self.updateButton setEnabled:YES];
        });
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    // Drawing code here.
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // CRITICAL: Remove notification observers to prevent cross-cell updates
    [self removeNotificationObserver];
    
    // Reset progress indicators
    [_patchProgressBar stopAnimation:nil];
    [_patchProgressBar setIndeterminate:YES];
    [_patchProgressBar setHidden:YES];
    
    // Reset custom progress bar
    if (self.progressBarNew) {
        [self.progressBarNew stopAnimation];
        [self.progressBarNew setHidden:YES];
    }
    
    // Reset status text and images
    _patchStatus.hidden = YES;
    _patchStatus.stringValue = @"";
    [self.updateButton setEnabled:YES];
    
    // Reset button state
    [self.updateButton setTitle:@"Install"];
    [self.updateButton setState:0];
    
    // Reset completion icon
    [self.patchCompletionIcon setImage:[NSImage imageNamed:@"EmptyImage"]];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:@"disablePatchButtons" object:self];
    
    // If MacOS 11 or later than skip Apple Update
    // We will open the apple sys prefs SU pane
    //if (@available(macOS 11.0, *)) {
    if ([_rowData[@"type"] isEqualToString:@"Apple"]) {
        [NSWorkspace.sharedWorkspace openURL: [NSURL fileURLWithPath:ASUS_PREF_PANE]];
        return;
    }
    //}

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([self.patchRestart.stringValue isEqualToString:@"Restart Required"]) {
        if ([defaults integerForKey:@"AlertOnRebootPatch"] == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle:@"Patch"];
            [alert setMessageText:@"Patch requires reboot..."];
            [alert setInformativeText:@"Please save and exit the associated application that is going to be patched, to prevent any loss of data."];
            if([alert runModal] == NSAlertFirstButtonReturn) {
                [defaults setInteger:1 forKey:@"AlertOnRebootPatch"];
                [defaults synchronize];
            }
        }
    }
    
	GlobalQueueManager *q = [GlobalQueueManager sharedInstance];
	
	if (![sender isKindOfClass:[NSButton class]])
		return;
	
	// Call delegate to mark install start
	if ([self.delegate respondsToSelector:@selector(updatesCellViewDidStartInstall:rowData:)]) {
		[self.delegate updatesCellViewDidStartInstall:self rowData:self.rowData];
	}
	
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
	
    BOOL allowInstall = YES;
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

- (IBAction)runInstallAlt:(NSButton *)sender
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self setupNotification];
		[self setupCellInstall];
	});
	
	
	GlobalQueueManager *q = [GlobalQueueManager sharedInstance];

	
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		qldebug(@"Operation Queue Count: %lu",(unsigned long)q.globalQueue.operationCount);
		if (q.globalQueue.operationCount > 1) {
			[self.updateButton setTitle:@"Waiting..."];
			[self.updateButton setEnabled:NO];
			[self.updateButton display];
		}
	});
	
	//NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	//BOOL allowInstall = [defaults boolForKey:@"allowRebootPatchInstalls"];
    BOOL allowInstall = YES;
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
	qlinfo(@"WST: %@",aStatus);
	dispatch_async(dispatch_get_main_queue(), ^{
		self->_patchStatus.stringValue = aStatus;
	});
}

// Setup User Notification for Patch Install Operation
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
	
	// Remove any existing observers first to prevent duplicates
	[self removeNotificationObserver];
	
	__weak typeof(self) weakSelf = self;
	[nc addObserverForName:_cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 dispatch_async(dispatch_get_main_queue(), ^{
			 // Verify this cell still represents the same patch
			 NSString *notificationPatchID = note.userInfo[@"patch_id"];
			 NSString *currentPatchID = [weakSelf.rowData[@"type"] isEqualToString:@"Apple"] ? 
			                            weakSelf.rowData[@"patch"] : weakSelf.rowData[@"patch_id"];
			 if (!notificationPatchID || [currentPatchID isEqualToString:notificationPatchID]) {
				 [weakSelf.updateButton setTitle:@"Installing..."];
			 }
		 });
	 }];
	
	[nc addObserverForName:_cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 // Verify this cell still represents the same patch
			 NSString *notificationPatchID = userInfo[@"patch_id"];
			 NSString *currentPatchID = [weakSelf.rowData[@"type"] isEqualToString:@"Apple"] ? 
			                            weakSelf.rowData[@"patch"] : weakSelf.rowData[@"patch_id"];
			 if (!notificationPatchID || [currentPatchID isEqualToString:notificationPatchID]) {
				 if (userInfo[@"status"]) {
					 weakSelf.patchStatus.stringValue = userInfo[@"status"];
				 }
				 // Call delegate to update model
				 if ([weakSelf.delegate respondsToSelector:@selector(updatesCellView:didUpdateProgress:status:rowData:)]) {
					 NSNumber *prog = userInfo[@"progress"] ?: @0;
					 [weakSelf.delegate updatesCellView:weakSelf didUpdateProgress:prog.doubleValue 
					                             status:(userInfo[@"status"] ?: @"") rowData:weakSelf.rowData];
				 }
			 }
		 });
	 }];
	
	[nc addObserverForName:_cellStopNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 // Verify this cell still represents the same patch
			 NSString *notificationPatchID = userInfo[@"patch_id"];
			 NSString *currentPatchID = [weakSelf.rowData[@"type"] isEqualToString:@"Apple"] ? 
			                            weakSelf.rowData[@"patch"] : weakSelf.rowData[@"patch_id"];
			 if (!notificationPatchID || [currentPatchID isEqualToString:notificationPatchID]) {
				 if (userInfo[@"error"]) {
					 weakSelf.patchStatus.stringValue = userInfo[@"status"];
					 [weakSelf stopCellInstallWithError:YES];
				 } else {
					 [weakSelf stopCellInstallWithError:NO];
				 }
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
		self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
		[self.progressBarNew startAnimation];
		[self.progressBarNew setHidden:NO];
		[self.progressBarNew display];
		
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
	qlinfo(@"stopCellInstallWithError");
	
	dispatch_async(dispatch_get_main_queue(), ^{
		// Reset Progressbar and text
		self->_patchStatus.stringValue = @" ";
		[self->_patchProgressBar setIndeterminate:YES];
		[self->_patchProgressBar setHidden:YES];
		[self->_patchProgressBar display];
		
		[self.progressBarNew stopAnimation];
		[self.progressBarNew setHidden:YES];
		
		if (hadError)
		{
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
		
		// Call delegate to notify install finished
		if ([self.delegate respondsToSelector:@selector(updatesCellViewDidFinish:success:errorMessage:rowData:)]) {
			BOOL success = !hadError;
			[self.delegate updatesCellViewDidFinish:self success:success errorMessage:errStr rowData:self.rowData];
		}
	});
	
	/*
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
     */
	[self removeNotificationObserver];
    
    // Add Reboot Notification
    /*
    if ([self.patchRestart.stringValue isEqualToString:@"Restart Required"]) {
        qlinfo(@"GlobalQueueManager sharedInstance].globalQueue.operationCount = %lu",(unsigned long)[GlobalQueueManager sharedInstance].globalQueue.operationCount);
        if ([GlobalQueueManager sharedInstance].globalQueue.operationCount <= 0) {
            AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
            [appDelegate showRebootWindow];
        }
    }
    */
}

- (void)stopCellInstallIsRebootPatch
{
	qlinfo(@"stopCellInstallIsRebootPatch");
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
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		 if (connectError != nil)
		 {
			 qlerror(@"connectError: %@",connectError.localizedDescription);
		 }
		 else
		 {
			 [[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				 qlerror(@"proxyError: %@",proxyError.localizedDescription);
			 }] setPatchOnLogoutWithReply:^(BOOL result) {
				 qldebug(@"setPatchOnLogoutWithReply: returned=%@",result ? @"YES":@"NO");
			 }];
		 }
	 }];

    // Reboot window is called from operation
	//AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
	//[appDelegate showRebootWindow];
}

@end
