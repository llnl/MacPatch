//
//  UpdatesVC.m
/*
Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "UpdatesVC.h"
#import "UpdatesCellView.h"
#import "AppDelegate.h"
#import "GlobalQueueManager.h"
#import "MPFileMonitor.h"

@interface UpdatesVC () <MPFileMonitorDelegate>

@property (nonatomic)         IBOutlet NSButton                *scanButton;
@property (nonatomic)         IBOutlet NSButton                *updateAllButton;

@property (nonatomic, retain) IBOutlet  NSProgressIndicator     *mainScanProgressWheel;
@property (nonatomic, retain) IBOutlet  NSTextField             *mainScanStatusText;
@property (nonatomic, retain) IBOutlet  NSImageView             *mainNetworkStatusImage;

@property (nonatomic, retain) IBOutlet  NSProgressIndicator     *mainPatchProgressWheel;
@property (nonatomic, retain) IBOutlet  NSTextField             *mainPatchStatusText;
@property (nonatomic, retain) IBOutlet  NSTextField             *pausedPatchingText;

// For Patch All
@property (nonatomic, retain) IBOutlet  NSProgressIndicator     *patchAllProgressBar;
@property (nonatomic, retain) IBOutlet  NSProgressIndicator     *patchAllProgressWheel;
@property (nonatomic, retain) IBOutlet  NSTextField             *patchAllPatchStatusText;

@property (nonatomic, assign) BOOL isPatchingPaused;
@property (nonatomic, assign) BOOL showRebootWarningDialog;
@property (nonatomic, assign) int countRebootPatch;

@property (weak) IBOutlet NSScrollView *scrollview;
@property (nonatomic) NSTask *task;

// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation UpdatesVC
{
	NSMutableArray* _content;
}

- (IBAction)resizeIt:(id)sender
{
	[self resizeTableViewForPatchAll];
}

-(IBAction)backToDefault:(id)sender
{
	[self resizeTableViewToDefaultSize];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do view setup here.
	
	_content = [NSMutableArray array];
    _showRebootWarningDialog = 0;
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(patchingStateChanged:)
												 name:@"PatchingStateChangedNotification"
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(scanForPatches:)
												 name:@"PatchScanNotification"
											   object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(disableButtons:)
                                                 name:@"disablePatchButtons"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(enableButtons:)
                                                 name:@"enablePatchButtons"
                                               object:nil];
}

- (void)viewDidAppear
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_mainScanStatusText setStringValue:@""];
		MPPatching *p = [MPPatching new];
		[self setIsPatchingPaused:[p patchingForHostIsPaused]];
		p = nil;
		if (self->_isPatchingPaused)
		{
			[self.pausedPatchingText setStringValue:@"NOTICE: Patching is paused. Change in preferences."];
			[self.pausedPatchingText setHidden:NO];
		} else {
			[self.pausedPatchingText setHidden:YES];
		}
		//[self.tableView reloadData];
	});
}

- (IBAction)scanForPatches:(id)sender
{
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_mainScanStatusText setStringValue:@"Begin patch scan"];
	});
		 
	[self startScan];
	
	__block MPPatchContentType patchContentType = kAllPatches;
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL allPatches = [defaults boolForKey:@"showAllPatches"];
	if (allPatches) {
		patchContentType = kAllActivePatches;
	}
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"%@",connectError);
			[self stopScan];
		} else {
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"%@",proxyError);
				[self stopScan];
			}] scanForPatchesUsingFilter:patchContentType withReply:^(NSError *error, NSData *patches,
																 NSData *patchGroupData) {
				
				if (error) {
					qlerror(@"error: %@",error.localizedDescription);
				}
				
				NSDictionary *patchDict = [NSKeyedUnarchiver unarchiveObjectWithData:patches];
				NSArray *approvedPatches = patchDict[@"required"];

				[self->_content removeAllObjects];
				[self->_content addObjectsFromArray:[NSMutableArray array]];
				
				// If there array has content, we need to remove all objects
				dispatch_async(dispatch_get_main_queue(), ^{
					[self.tableView reloadData];
				});
				
				// If we have content to add, add it
				if (approvedPatches && approvedPatches.count > 0)
				{
					[self->_content addObjectsFromArray:approvedPatches];
				} else {
					[self->_content addObjectsFromArray:[NSArray array]];
				}
				
				dispatch_async(dispatch_get_main_queue(), ^{
					[self.tableView reloadData];
					if (self->_content.count > 1)
					{
						[self.updateAllButton setHidden:NO];
						[self.updateAllButton setEnabled:YES];
						if (self->_isPatchingPaused) {
							[self.updateAllButton setEnabled:NO];
							[self.pausedPatchingText setFrame:NSMakeRect(540, 570, 354, 17)]; // Move it over
						}
					} else {
						[self.pausedPatchingText setFrame:NSMakeRect(628, 570, 354, 17)]; // Move it over
					}
				});
				
				[self stopScan];
			}];
		}
	}];
}

- (IBAction)updateAllPatches:(id)sender
{
    __block int rebootPatchCount = 0;
    __block int allowInstallInt = 0;
	__block BOOL hasRebootPatch = NO;
	
	//NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	//BOOL allowInstall = [defaults boolForKey:@"allowRebootPatchInstalls"];
    BOOL allowInstall = YES;
	//if (allowInstall) allowInstallInt = 1;
	
    for (int i = 0; i < _tableView.numberOfRows; i++) {
        UpdatesCellView *_cell = [_tableView viewAtColumn:0 row:i makeIfNecessary:FALSE];
        if ([_cell.rowData[@"restart"] isEqualToString:@"Yes"])
        {
            rebootPatchCount++;
        }
    }
    
    
    if (rebootPatchCount >= 1)
    {
        NSString *title = @"Patch requires reboot...";
        if (rebootPatchCount >= 2) title = @"Patches requires reboot...";
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Patch"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setMessageText:title];
        [alert setInformativeText:@"Please save and exit any applications that are going to be patched, to prevent any loss of data."];
        if([alert runModal] == NSAlertFirstButtonReturn) {
            [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"AlertOnRebootPatch"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        } else {
            // Hit cancel ...
            return;
        }
    }
        
	// Get an array of all patch dictionaries
	NSMutableArray *allPatches = [NSMutableArray new];
	for (int i = 0; i < _tableView.numberOfRows; i++)
	{
		UpdatesCellView *cell = [_tableView viewAtColumn:0 row:i makeIfNecessary:FALSE];
		if ([cell.rowData[@"restart"] isEqualToString:@"No"] || allowInstall) {
			[allPatches addObject:cell.rowData];
			dispatch_async(dispatch_get_main_queue(), ^{
				[cell.updateButton setHidden:YES];
			});
		} else if ([cell.rowData[@"restart"] isEqualToString:@"Yes"]) {
			hasRebootPatch = YES;
            rebootPatchCount++;
			dispatch_async(dispatch_get_main_queue(), ^{
				[cell.updateButton setTitle:@"On Reboot"];
				[cell.updateButton setEnabled:NO];
			});
		} else {
			qlerror(@"Error, restart attribute value was not set properly.");
			qlerror(@"Row Data: %@",cell.rowData);
		}
	}
 
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.scanButton setEnabled:NO];
		[self.updateAllButton setHidden:YES];
		[self.patchAllProgressBar setMaxValue:allPatches.count];
		[self resizeTableViewForPatchAll];
	});
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
		} else {
			
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"%@",proxyError);
			}] installPatches:(NSArray *)allPatches userInstallRebootPatch:allowInstallInt withReply:^(NSError *error, NSInteger resultCode) {

                [self->_task terminate];
                [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleDataAvailableNotification object:nil];
                
				if (error) {
					qlerror(@"Result Code(%ld): %@",resultCode,error.localizedDescription);
				}
				
				if (resultCode == 0) {
					qlinfo(@"Install was sucessful");
				} else {
					qlerror(@"resultCode: %ld",resultCode);
					if (!error) {
						// No error obj, need to create one
						error = [NSError errorWithDomain:@"gov.llnl.patch.oper" code:1001 userInfo:@{NSLocalizedDescriptionKey:@"Error installing patch. See helper logs for more details."}];
					}
					
					qlerror(@"Error[%ld] installing patches.", resultCode);
				}
				
				dispatch_async(dispatch_get_main_queue(), ^{
					if (hasRebootPatch) {
						[self showRebootPatchActions];
					}
				});
				
				dispatch_async(dispatch_get_main_queue(), ^{
					[self->_scanButton setEnabled:YES];
					[self resizeTableViewToDefaultSize];
					if (allowInstallInt) {
						AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
						[appDelegate showRestartWindow:0];
					}
				});
			}];
		}
	}];
	
}

- (void)progressData:(NSNotification *)notification
{
    NSData *newData = [notification.object availableData];
    if (newData && newData.length)
    {
        NSString *tmpStr = [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding];
        if ([[tmpStr trim] length] != 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_patchAllPatchStatusText setStringValue:tmpStr];
            });
        }
        tmpStr = nil;
    }
    
    [notification.object waitForDataInBackgroundAndNotify];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
	return YES;
}

#pragma mark - Private Methods
- (NSArray *)filterApprovedPatches:(NSArray *)foundPatches
{
	return nil;
}

- (void)resizeTableViewForPatchAll
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NSRect frame = self->_scrollview.frame;
		frame.size.height = frame.size.height - 67;
		[self->_scrollview setFrame: frame];
		[self->_patchAllProgressWheel startAnimation:nil];
		[self.scanButton setEnabled:NO];
	});
}

- (void)resizeTableViewToDefaultSize
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NSRect frame = self->_scrollview.frame;
		frame.size.height = frame.size.height + 67;
		[self->_scrollview setFrame: frame];
		[self->_patchAllProgressWheel stopAnimation:nil];
		[self.scanButton setEnabled:YES];
	});
}

- (void)showRebootPatchActions
{
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRebootRequiredNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
	
	AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
	[appDelegate showRebootWindow];
}

#pragma mark - Progress Methods
- (void)startScan
{
	for (int i = 0; i < _tableView.numberOfRows; i++)
	{
		UpdatesCellView *cell = [_tableView viewAtColumn:0 row:i makeIfNecessary:FALSE];
		dispatch_async(dispatch_get_main_queue(), ^{
			[cell.updateButton setHidden:YES];
		});
	}
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		[self->_scanButton setTitle:@"Scanning..."];
		[self->_scanButton setEnabled:NO];
		[self->_updateAllButton setHidden:YES];
		
		NSRect progWheelRect = self->_mainScanProgressWheel.frame;
		[self->_mainScanStatusText.animator setFrame:NSMakeRect(progWheelRect.origin.x + 22, progWheelRect.origin.y, 389, 17)];
		self->_mainScanStatusText.stringValue = @"";
		[self->_mainScanStatusText setHidden:NO];
		[self->_mainScanStatusText setStringValue:@"Begin patch scan"];
		
		self->_mainPatchStatusText.stringValue = @"";
		[self->_mainPatchStatusText setHidden:NO];
		
		[self->_mainScanProgressWheel setHidden:NO];
		[self->_mainScanProgressWheel startAnimation:nil];
		//[_swNetworkStatusImage setHidden:YES];
	});
}

- (void)stopScan
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NSRect progWheelRect = self->_mainScanProgressWheel.frame;
		[self->_mainScanStatusText.animator setFrame:NSMakeRect(progWheelRect.origin.x, progWheelRect.origin.y, 389, 17)];
		[self->_mainScanProgressWheel stopAnimation:nil];
		[self->_mainScanProgressWheel setHidden:YES];
		[self->_mainScanStatusText setStringValue:@"Patch scan completed. No patches needed."];
        
        // Scan is done, clear alert for reboot patch
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"AlertOnRebootPatch"];
        [[NSUserDefaults standardUserDefaults] synchronize];
		
		if (self->_content && [self->_content count] >= 0)
		{
			// Maybe add number of patches needed.
			[[NSUserDefaults standardUserDefaults] setInteger:[self->_content count] forKey:@"PatchCount"];
			[[NSUserDefaults standardUserDefaults] synchronize];
			
			// And post a notification so the plug-in sees the change.
			[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"gov.llnl.mp.MacPatch.MacPatchTile" object:nil];
			
			if ([self->_content count] >= 1) {
				[self->_mainScanStatusText setStringValue:@"Patch scan completed."];
				[[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)[self->_content count]]];
			} else {
				[self->_mainScanStatusText setStringValue:@"Patch scan completed. No patches needed."];
				[[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
			}
		}
		
		MPFileCheck *fu = [MPFileCheck new];
		if ([fu fExists:MP_AUTHSTATUS_FILE])
		{
			NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
			if ([d[@"enabled"] boolValue])
			{
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
						}] fvAuthrestartAccountIsValid:^(NSError *err, BOOL result) {
							if (err) {
								qlerror(@"%@",err.localizedDescription);
							}
							// User account is out of sync, post notification.
							if (!result) {
								[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kFileVaultUserOutOfSync"
																							   object:nil
																							 userInfo:nil
																							  options:NSNotificationPostToAllSessions];
							}
							dispatch_semaphore_signal(sem);
						}];
					}
				}];
				dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
			}
		}

		[self->_scanButton setTitle:@"Scan"];
		[self->_scanButton setNextState];
		[self->_scanButton setEnabled:YES];
		
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
	});
}

#pragma mark - NSTableViewDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return _content.count;
}

#pragma mark - NSTableViewDelegate
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
		
	NSString *identifier = [tableColumn identifier];
	if ([identifier isEqualToString:@"MainCell"])
	{
		NSDictionary *d = _content[row];
		UpdatesCellView* cell = [tableView makeViewWithIdentifier:@"MainCell" owner:self];
		// Set some defaults
		cell.updateButton.title = @"Install";
		[cell.updateButton setState:0];
		[cell.updateButton setEnabled:YES];
		[cell.updateButton setHidden:NO];
		[cell.patchCompletionIcon setImage:[NSImage imageNamed:@"EmptyImage"]];
		
		cell.patchName.stringValue = d[@"patch"];
		cell.patchVersion.stringValue = [NSString stringWithFormat:@"Version: %@",d[@"version"]];
		cell.patchDescription.stringValue = d[@"description"];
		long lSize;
		if ([d[@"type"] isEqualToString:@"Apple"]) {
			lSize = ([[d[@"size"] stringByReplacingOccurrencesOfString:@"K" withString:@""] longLongValue] * 1000);
		} else {
			lSize = ([d[@"patchData"][@"pkg_size"] longLongValue] * 1000);
		}
		NSString *xSize = [NSByteCountFormatter stringFromByteCount:lSize countStyle:NSByteCountFormatterCountStyleFile];
		cell.patchSize.stringValue = [NSString stringWithFormat:@"Size: %@",xSize];
		if (d[@"restart"]) {
			if ([[d[@"restart"] uppercaseString] isEqualToString:@"NO"]) {
				cell.patchRestart.stringValue = @"";
			} else {
				cell.patchRestart.stringValue = @"Restart Required";
				cell.patchCompletionIcon.image = [NSImage imageNamed:@"RebootImage"];
				cell.patchCompletionIcon.hidden = NO;
			}
		}
		if ([[d[@"type"] uppercaseString] isEqualToString:@"APPLE"]) {
			cell.patchTypeIcon.image = [NSImage imageNamed:@"appleImage"];
		} else {
			cell.patchTypeIcon.image = [NSImage imageNamed:@"macPatchImage"];
		}
		if (self->_isPatchingPaused)
		{
			[cell.updateButton setEnabled:NO];
		}
		
		cell.rowData = [d copy];
		return cell;
	}
		
		
	return nil;
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

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
    //qlinfo(@"postStatus[%d]: %@",type,status);
    
	if (type == kMPPatchProcessStatus)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->_mainScanStatusText setStringValue:status];
		});
	}
	else if (type == kMPProcessStatus)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->_mainScanStatusText setStringValue:status];
		});
	}
	else if (type == kMPPatchAllProcessProgress)
	{
        //qlinfo(@"postStatus[kMPPatchAllProcessProgress]: %@",status);
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->_patchAllProgressBar setDoubleValue:[status doubleValue]];
		});
	}
	else if (type == kMPPatchAllProcessStatus)
	{
        //qlinfo(@"postStatus[kMPPatchAllProcessStatus]: %@",status);
		dispatch_async(dispatch_get_main_queue(), ^{
			[self->_patchAllPatchStatusText setStringValue:status];
		});
    }
}

- (void)postPatchInstallStatus:(NSString *)patchID type:(MPPostDataType)type
{
    //qlinfo(@"postPatchInstallStatus: %@",patchID);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    __block NSInteger pCount = [defaults integerForKey:@"PatchCount"];
    __block NSString *cellPatchID = @"";
    __block UpdatesCellView *cell;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (type == kMPPatchAllInstallComplete)
        {
            
			for (int i = 0; i < self->_tableView.numberOfRows; i++)
			{
				cell = [self->_tableView viewAtColumn:0 row:i makeIfNecessary:FALSE];
                if ([[cell.rowData[@"type"] uppercaseString] isEqualToString:@"APPLE"]) {
                    cellPatchID = cell.rowData[@"patch"];
                } else {
                    cellPatchID = cell.rowData[@"patch_id"];
                }
                
                if ([cellPatchID isEqual:patchID]) {
                    [cell.updateButton setTitle:@"Installed"];
                    [cell.updateButton setHidden:NO];
                    [cell.updateButton setEnabled:NO];
                    cell.patchCompletionIcon.hidden = NO;
                    cell.patchCompletionIcon.image = [NSImage imageNamed:@"GoodImage"];
                }
			}
            
            pCount = pCount - 1;
            [defaults setInteger:pCount forKey:@"PatchCount"];
            [defaults synchronize];
            
            // Now update the dock tile. Note that a more general way to do this would be to observe the highScore property, but we're just keeping things short and sweet here, trying to demo how to write a plug-in.
            if (pCount >= 1) {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)pCount]];
            } else {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
            }
            
        } else if (type == kMPPatchAllInstallError) {
            
			for (int i = 0; i < self->_tableView.numberOfRows; i++)
			{
				cell = [self->_tableView viewAtColumn:0 row:i makeIfNecessary:FALSE];
                if ([[cell.rowData[@"type"] uppercaseString] isEqualToString:@"APPLE"]) {
                    cellPatchID = cell.rowData[@"patch"];
                } else {
                    cellPatchID = cell.rowData[@"patch_id"];
                }
                
                if ([cellPatchID isEqual:patchID]) {
					[cell.updateButton setTitle:@"Error"];
					[cell.updateButton setHidden:NO];
					[cell.updateButton setEnabled:NO];
					cell.patchCompletionIcon.hidden = NO;
					cell.patchCompletionIcon.image = [NSImage imageNamed:@"ErrorImage"];
				}
			}
        }
    });
}

- (NSString*)formatTypeToString:(MPPostDataType)formatType
{
    NSString *result = nil;

    switch(formatType) {
        case kMPInstallStatus:
            result = @"kMPInstallStatus";
            break;
        case kMPProcessStatus:
            result = @"kMPProcessStatus";
            break;
        case kMPProcessProgress:
            result = @"kMPProcessProgress";
            break;
        case kMPPatchProcessStatus:
            result = @"kMPPatchProcessStatus";
            break;
		case kMPPatchProcessProgress:
            result = @"kMPPatchProcessProgress";
            break;
        case kMPPatchAllProcessProgress:
            result = @"kMPPatchAllProcessProgress";
            break;
        case kMPPatchAllProcessStatus:
            result = @"kMPPatchAllProcessStatus";
            break;
		case kMPPatchAllInstallComplete:
			result = @"kMPPatchAllInstallComplete";
			break;
		default: ;
            //[NSException raise:NSGenericException format:@"Unexpected FormatType."];
    }

    return result;
}

#pragma mark - Post to Server
- (void)postPatchesFound:(NSArray *)aPatches
{
	qldebug(@"Patches: %@",aPatches);
}

- (void)postPatchInstall:(NSDictionary *)aPatch sucess:(BOOL)sucess
{
	
}

#pragma mark - Notifications

- (void)patchingStateChanged:(NSNotification *)notification
{
	if ([[notification name] isEqualToString:@"PatchingStateChangedNotification"])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			MPPatching *p = [MPPatching new];
			[self setIsPatchingPaused:[p patchingForHostIsPaused]];
			if (self->_isPatchingPaused)
			{
				[self.pausedPatchingText setStringValue:@"NOTICE: Patching is paused. Change in preferences."];
				[self.pausedPatchingText setHidden:NO];
				
				if (![self.updateAllButton isHidden]) {
					[self.updateAllButton setEnabled:NO];
					[self.pausedPatchingText setFrame:NSMakeRect(540, 570, 354, 17)]; // Move it over
				}
			} else {
				[self.pausedPatchingText setHidden:YES];
				if (![self.updateAllButton isHidden]) {
					[self.updateAllButton setEnabled:YES];
				}
			}
			[self.tableView reloadData];
			p = nil;
		});
	}
}

- (void)disableButtons:(NSNotification *)notification
{
    if ([[notification name] isEqualToString:@"disablePatchButtons"])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updateAllButton setHidden:YES];
            [self.mainScanStatusText setStringValue:@""];
            [self.scanButton setEnabled:NO];
        });
    }
}

- (void)enableButtons:(NSNotification *)notification
{
    if ([[notification name] isEqualToString:@"enablePatchButtons"])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.scanButton setEnabled:YES];
        });
    }
}

@end
