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
FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General
Public License for more details.

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
- (BOOL)isRowDataValidForInstall;
- (NSString *)currentPatchIdentifier;
- (BOOL)isCellBusy;
- (void)notifyDelegateInstallStartedIfPossible;
- (void)queueInstallOperation;

@end

@implementation UpdatesCellView

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // CRITICAL: Ensure the view is layer-backed
    [self setWantsLayer:YES];
    
    if (!_progressBarNew) {
        _progressBarNew = [[MPOProgressBar alloc] init];
        _progressBarNew.backgroundColor = [NSColor colorWithRed:180.0/255 green:207.0/255 blue:240.0/255 alpha:1.0].CGColor;
        _progressBarNew.fillColor = [NSColor colorWithRed:66.0/255 green:139.0/255 blue:237.0/255 alpha:1.0].CGColor;
        
        // CRITICAL: Ensure layer is properly configured
        _progressBarNew.masksToBounds = YES;
        _progressBarNew.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        
        [self.layer addSublayer:_progressBarNew];
        
        // Set frame - use dispatch_async to ensure layout is complete
        dispatch_async(dispatch_get_main_queue(), ^{
            NSRect pbar = self->_patchProgressBar.frame;
            
            // CRITICAL: Check if frame is valid
            if (NSIsEmptyRect(pbar) || pbar.size.width <= 0) {
                qlwarning(@"[awakeFromNib] _patchProgressBar frame is invalid, using fallback positioning");
                // Use a fallback position relative to the cell view
                pbar = NSMakeRect(20, 20, self.bounds.size.width - 40, 4);
            }
            
            self->_progressBarNew.frame = CGRectMake(pbar.origin.x, pbar.origin.y + 8, pbar.size.width, 4);
            
            // CRITICAL: Ensure the layer is at the correct z-position
            self->_progressBarNew.zPosition = 100; // Put it on top
            
            [self->_progressBarNew setHidden:YES];
        });
    }
}

// CRITICAL: Override this to ensure progress bar is positioned correctly after layout
- (void)layout
{
    [super layout];
    
    // Reposition progress bar if needed
    if (self.progressBarNew && !CGRectIsEmpty(self.progressBarNew.frame)) {
        NSRect pbar = _patchProgressBar.frame;
        if (!NSIsEmptyRect(pbar) && pbar.size.width > 0) {
            CGRect newFrame = CGRectMake(pbar.origin.x, pbar.origin.y + 8, pbar.size.width, 4);
            if (!CGRectEqualToRect(self.progressBarNew.frame, newFrame)) {
                self.progressBarNew.frame = newFrame;
            }
        }
    }
}

// Configure cell UI based on rowData state - called every time cell is reused
- (void)configureCellUI
{
    [self connectToHelperTool];
    
    BOOL isInstalling = [_rowData[@"isInstalling"] boolValue];
    
    qldebug(@"[configureCellUI] self=%p delegate=%@ rowData=%@", self, self.delegate, self.rowData);
    
    if (isInstalling) {
        NSNumber *progress = _rowData[@"progress"] ?: @0;
        NSString *statusText = _rowData[@"statusText"] ?: @"Installing...";
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progress.doubleValue > 0) {
                [self->_patchProgressBar setHidden:YES];
                self.progressBarNew.progressMode = MPOProgressBarModeDeterminate;
                
                [CATransaction begin];
                [CATransaction setDisableActions:NO];
                [CATransaction setAnimationDuration:0.3];
                self.progressBarNew.progress = progress.doubleValue / 100.0;
                [CATransaction commit];
                
                self.progressBarNew.opacity = 1.0;
                [self.progressBarNew setHidden:NO];
                [self.progressBarNew setNeedsDisplay];
            } else {
                [self->_patchProgressBar setHidden:YES];
                self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
                self.progressBarNew.opacity = 1.0;
                [self.progressBarNew setHidden:NO];
                [self.progressBarNew startAnimation];
                [self.progressBarNew setNeedsDisplay];
            }
            
            [self.patchStatus setHidden:NO];
            self.patchStatus.stringValue = statusText ?: @"";
            
            [self.updateButton setEnabled:NO];
            [self.updateButton setTitle:@"Installing"];
        });
        
        [self setupNotification];
        
    } else {
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
    
    qldebug(@"[prepareForReuse] self=%p delegate=%@ rowData=%@", self, self.delegate, self.rowData);
    
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
		self.worker.invalidationHandler = ^{
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
{
	assert([NSThread isMainThread]);
	[self connectToHelperTool];
	commandBlock(nil);
}

- (BOOL)isRowDataValidForInstall
{
    if (![self.rowData isKindOfClass:[NSDictionary class]] || self.rowData.count == 0) {
        qlerror(@"[runInstall] rowData is nil or invalid");
        return NO;
    }
    
    NSString *patchType = self.rowData[@"type"];
    if (![patchType isKindOfClass:[NSString class]] || patchType.length == 0) {
        qlerror(@"[runInstall] rowData missing or invalid type");
        return NO;
    }
    
    NSString *patchIdentifier = [self currentPatchIdentifier];
    if (patchIdentifier.length == 0) {
        qlerror(@"[runInstall] rowData missing patch identifier");
        return NO;
    }
    
    return YES;
}

- (NSString *)currentPatchIdentifier
{
    NSString *patchType = self.rowData[@"type"];
    if ([patchType isEqualToString:@"Apple"]) {
        return self.rowData[@"patch"] ?: @"";
    }
    return self.rowData[@"patch_id"] ?: @"";
}

- (BOOL)isCellBusy
{
    BOOL isInstalling = [self.rowData[@"isInstalling"] boolValue];
    NSString *title = self.updateButton.title ?: @"";
    return isInstalling || [title isEqualToString:@"Installing"] || [title isEqualToString:@"Waiting..."];
}

- (void)notifyDelegateInstallStartedIfPossible
{
    qldebug(@"[notifyDelegateInstallStartedIfPossible] self=%p delegate=%@ delegateClass=%@ rowData=%@",
            self, self.delegate, NSStringFromClass([self.delegate class]), self.rowData);
    
    if (self.delegate == nil) {
        qlerror(@"[notifyDelegateInstallStartedIfPossible] delegate is nil");
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(updatesCellViewDidStartInstall:rowData:)]) {
        qlinfo(@"[notifyDelegateInstallStartedIfPossible] calling delegate updatesCellViewDidStartInstall:rowData:");
        [self.delegate updatesCellViewDidStartInstall:self rowData:self.rowData];
    } else {
        qlerror(@"[notifyDelegateInstallStartedIfPossible] delegate %@ does not respond to updatesCellViewDidStartInstall:rowData:",
                NSStringFromClass([self.delegate class]));
    }
}

- (void)queueInstallOperation
{
    GlobalQueueManager *q = [GlobalQueueManager sharedInstance];
    if (q.globalQueue == nil) {
        qlerror(@"[queueInstallOperation] globalQueue is nil");
        [self stopCellInstallWithError:YES errorString:@"Install queue is unavailable"];
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        qldebug(@"[queueInstallOperation] Operation Queue Count: %lu", (unsigned long)q.globalQueue.operationCount);
        if (q.globalQueue.operationCount > 1) {
            [self.updateButton setTitle:@"Waiting..."];
            [self.updateButton setEnabled:NO];
            [self.updateButton display];
        }
    });
    
    BOOL allowInstall = YES;
    BOOL needsReboot = [self.rowData[@"restart"] stringToBoolValue];
    
    if (needsReboot && !allowInstall) {
        qlinfo(@"[queueInstallOperation] patch requires reboot and allowInstall is NO");
        [self stopCellInstallIsRebootPatch];
        return;
    }
    
    UpdateInstallOperation *inst = [[UpdateInstallOperation alloc] init];
    if (!inst) {
        qlerror(@"[queueInstallOperation] Failed to create UpdateInstallOperation");
        [self stopCellInstallWithError:YES errorString:@"Failed to create install operation"];
        return;
    }
    
    inst.patch = [self.rowData copy];
    if (!inst.patch) {
        qlerror(@"[queueInstallOperation] Failed to assign patch to UpdateInstallOperation");
        [self stopCellInstallWithError:YES errorString:@"Patch data is invalid"];
        return;
    }
    
    qlinfo(@"[queueInstallOperation] Queueing patch install operation for %@", [self currentPatchIdentifier]);
    qldebug(@"[queueInstallOperation] queued patch: %@", inst.patch);
    [q.globalQueue addOperation:inst];
}

#pragma mark - XPC Methods

- (IBAction)runInstall:(NSButton *)sender
{
    NSString *buttonTitle = sender.title ?: @"";
    qlinfo(@"[runInstall] called");
    qlinfo(@"[runInstall] self=%p delegate=%@ delegateClass=%@ buttonTitle=%@ rowData=%@",
           self, self.delegate, NSStringFromClass([self.delegate class]), buttonTitle, self.rowData);
    
    if (![sender isKindOfClass:[NSButton class]]) {
        qlerror(@"[runInstall] sender was not NSButton");
        return;
    }
    
    if (![self isRowDataValidForInstall]) {
        return;
    }
    
    if ([self isCellBusy]) {
        qlwarning(@"[runInstall] ignoring request because cell is already busy");
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"disablePatchButtons" object:self];
    
    NSString *patchType = self.rowData[@"type"];
    
    // Apple patches are handled by System Settings / Software Update.
    if ([patchType isEqualToString:@"Apple"]) {
        qlinfo(@"[runInstall] Apple patch selected, opening Software Update preference pane");
        
        [self notifyDelegateInstallStartedIfPossible];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.patchStatus setHidden:NO];
            self.patchStatus.stringValue = @"Opening Software Update…";
            [self.updateButton setTitle:@"Open Software Update"];
            [self.updateButton setEnabled:YES];
        });
        
        BOOL opened = [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:ASUS_PREF_PANE]];
        if (!opened) {
            qlerror(@"[runInstall] Failed to open Software Update preference pane: %@", ASUS_PREF_PANE);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.patchStatus.stringValue = @"Failed to open Software Update";
                [self.updateButton setTitle:@"Install"];
                [self.updateButton setEnabled:YES];
            });
        }
        return;
    }

    defaults = [NSUserDefaults standardUserDefaults];
    if ([self.patchRestart.stringValue isEqualToString:@"Restart Required"]) {
        if ([defaults integerForKey:@"AlertOnRebootPatch"] == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle:@"Patch"];
            [alert setMessageText:@"Patch requires reboot..."];
            [alert setInformativeText:@"Please save and exit the associated application that is going to be patched, to prevent any loss of data."];
            if([alert runModal] == NSAlertFirstButtonReturn) {
                [defaults setInteger:1 forKey:@"AlertOnRebootPatch"];
                [defaults synchronize];
            } else {
                qlinfo(@"[runInstall] User cancelled reboot patch alert");
                [self.updateButton setEnabled:YES];
                return;
            }
        }
    }
    
    [self notifyDelegateInstallStartedIfPossible];
    
    qlinfo(@"[runInstall] setting up notifications");
    [self setupNotification];
    
    qlinfo(@"[runInstall] setting up install UI");
    [self setupCellInstall];
    
    [self queueInstallOperation];
}

- (IBAction)runInstallAlt:(NSButton *)sender
{
    qlinfo(@"[runInstallAlt] called self=%p delegate=%@ buttonTitle=%@ rowData=%@",
           self, self.delegate, sender.title ?: @"", self.rowData);
    
    if (![sender isKindOfClass:[NSButton class]]) {
        qlerror(@"[runInstallAlt] sender was not NSButton");
        return;
    }
    
    if (![self isRowDataValidForInstall]) {
        return;
    }
    
    if ([self isCellBusy]) {
        qlwarning(@"[runInstallAlt] ignoring request because cell is already busy");
        return;
    }
    
    [self notifyDelegateInstallStartedIfPossible];
    [self setupNotification];
    [self setupCellInstall];
    [self queueInstallOperation];
}

- (void)workerStatusText:(NSString *)aStatus
{
	qlinfo(@"WST: %@",aStatus);
	dispatch_async(dispatch_get_main_queue(), ^{
		self->_patchStatus.stringValue = aStatus ?: @"";
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
    
    qldebug(@"[setupNotification] self=%p patchID=%@ start=%@ progress=%@ stop=%@",
            self, pID, _cellStartNote, _cellProgressNote, _cellStopNote);
	
	// Remove any existing observers first to prevent duplicates
	[self removeNotificationObserver];
	
	__weak typeof(self) weakSelf = self;
	[nc addObserverForName:_cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 dispatch_async(dispatch_get_main_queue(), ^{
			 NSString *notificationPatchID = note.userInfo[@"patch_id"];
			 NSString *currentPatchID = [weakSelf currentPatchIdentifier];
			 if (!notificationPatchID || [currentPatchID isEqualToString:notificationPatchID]) {
				 [weakSelf.updateButton setTitle:@"Installing..."];
			 }
		 });
	 }];
	
	[nc addObserverForName:_cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 NSString *notificationPatchID = userInfo[@"patch_id"];
			 NSString *currentPatchID = [weakSelf currentPatchIdentifier];
			 if (!notificationPatchID || [currentPatchID isEqualToString:notificationPatchID]) {
				 if (userInfo[@"status"]) {
					 weakSelf.patchStatus.stringValue = userInfo[@"status"];
				 }
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
			 NSString *notificationPatchID = userInfo[@"patch_id"];
			 NSString *currentPatchID = [weakSelf currentPatchIdentifier];
			 if (!notificationPatchID || [currentPatchID isEqualToString:notificationPatchID]) {
				 if (userInfo[@"error"]) {
					 weakSelf.patchStatus.stringValue = userInfo[@"status"] ?: @"Error";
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
    if (_cellStartNote.length > 0) {
        [nc removeObserver:self name:_cellStartNote object:nil];
    }
    if (_cellProgressNote.length > 0) {
        [nc removeObserver:self name:_cellProgressNote object:nil];
    }
    if (_cellStopNote.length > 0) {
        [nc removeObserver:self name:_cellStopNote object:nil];
    }
}

- (void)setupCellInstall
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
		self.progressBarNew.opacity = 1.0;
		[self.progressBarNew setHidden:NO];
		[self.progressBarNew startAnimation];
		[self.progressBarNew setNeedsDisplay];
		
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
			
			if (pCount >= 1) {
				[[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)pCount]];
			} else {
				[[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
			}
		}
		
		if ([self.delegate respondsToSelector:@selector(updatesCellViewDidFinish:success:errorMessage:rowData:)]) {
			BOOL success = !hadError;
			[self.delegate updatesCellViewDidFinish:self success:success errorMessage:errStr rowData:self.rowData];
		}
	});
	
	[self removeNotificationObserver];
}

- (void)stopCellInstallIsRebootPatch
{
	qlinfo(@"stopCellInstallIsRebootPatch");
	dispatch_async(dispatch_get_main_queue(), ^{
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
}

@end
