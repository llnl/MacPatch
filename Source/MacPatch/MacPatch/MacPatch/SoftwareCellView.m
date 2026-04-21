//
//  SoftwareCellView.m
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

#import "SoftwareCellView.h"
#import "GlobalQueueManager.h"
#import "MacPatch.h"
#import "SoftwareInstallOperation.h"
#import "SoftwareUninstallOperation.h"
#import "AppDelegate.h"

#import "MPOProgressBar.h"

@interface SoftwareCellView ()
{
    NSUserDefaults *defaults;
}

@property (atomic, strong, readwrite) NSXPCConnection *worker;
@property (nonatomic, strong) MPOProgressBar *progressBarNew;

@property (nonatomic)         NSInteger requestCount;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end


@implementation SoftwareCellView

#pragma mark - Main

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // CRITICAL: Ensure the view is layer-backed
    [self setWantsLayer:YES];
    
    [self setupProgressBar];
}

- (void)setupProgressBar
{
    if (!self.progressBarNew) {
        self.progressBarNew = [[MPOProgressBar alloc] init];
        self.progressBarNew.backgroundColor = [NSColor colorWithRed:180.0/255 green:207.0/255 blue:240.0/255 alpha:1.0].CGColor;
        self.progressBarNew.fillColor = [NSColor colorWithRed:66.0/255 green:139.0/255 blue:237.0/255 alpha:1.0].CGColor;
        
        // CRITICAL: Ensure layer is properly configured
        self.progressBarNew.masksToBounds = YES;
        self.progressBarNew.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        
        // Add as sublayer
        [self.layer addSublayer:self.progressBarNew];
        
        // Set frame - use dispatch_async to ensure layout is complete
        dispatch_async(dispatch_get_main_queue(), ^{
            NSRect pbar = self->_progressBar.frame;
            
            // CRITICAL: Check if frame is valid
            if (NSIsEmptyRect(pbar) || pbar.size.width <= 0) {
                qlwarning(@"[setupProgressBar] _progressBar frame is invalid, using fallback positioning");
                // Use a fallback position relative to the cell view
                pbar = NSMakeRect(20, 20, self.bounds.size.width - 40, 4);
            }
            
            // Position the progress bar
            CGRect newFrame = CGRectMake(pbar.origin.x, pbar.origin.y + 8, pbar.size.width, 4);
            self.progressBarNew.frame = newFrame;
            
            // CRITICAL: Ensure the layer is at the correct z-position
            self.progressBarNew.zPosition = 100; // Put it on top
            
            [self.progressBarNew setHidden:YES];
            
            qldebug(@"[setupProgressBar] Created progressBarNew: frame = {%f, %f, %f, %f}, zPosition = %f",
                   newFrame.origin.x, newFrame.origin.y, newFrame.size.width, newFrame.size.height,
                   self.progressBarNew.zPosition);
            
            // Force a display update
            [self.progressBarNew setNeedsDisplay];
        });
    }
}

// CRITICAL: Override this to ensure progress bar is positioned correctly after layout
- (void)layout
{
    [super layout];
    
    // Reposition progress bar if needed
    if (self.progressBarNew && !CGRectIsEmpty(self.progressBarNew.frame)) {
        NSRect pbar = _progressBar.frame;
        if (!NSIsEmptyRect(pbar) && pbar.size.width > 0) {
            CGRect newFrame = CGRectMake(pbar.origin.x, pbar.origin.y + 8, pbar.size.width, 4);
            if (!CGRectEqualToRect(self.progressBarNew.frame, newFrame)) {
                qldebug(@"[layout] Repositioning progressBarNew to: {%f, %f, %f, %f}",
                       newFrame.origin.x, newFrame.origin.y, newFrame.size.width, newFrame.size.height);
                self.progressBarNew.frame = newFrame;
            }
        }
    }
}

// Configure cell UI based on rowData state - called every time cell is reused
- (void)configureCellUI
{
    [self connectToHelperTool];
    [self loadImage];
    
    // Ensure progress bar is set up
    [self setupProgressBar];
    
    // Check if this row is currently installing/uninstalling
    BOOL isInstalling = [_rowData[@"isInstalling"] boolValue];
    
    if (isInstalling) {
        // Row is currently installing/uninstalling - restore the operation UI from model
        NSNumber *progress = _rowData[@"progress"] ?: @0;
        NSString *statusText = _rowData[@"statusText"] ?: @"Processing...";
        NSString *operationType = _rowData[@"operationType"] ?: @"Install";
        
        BOOL isUninstall = [operationType isEqualToString:@"Uninstall"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_errorImage setHidden:YES];
            [self->_swDescription setFrameSize:NSMakeSize(350.0, 86.0)];
            
            // Always hide the old progress bar
            [self->_progressBar setHidden:YES];
            [self->_progressBar stopAnimation:nil];
            
            // Configure progress bars based on progress value
            if (progress.doubleValue > 0) {
                qldebug(@"[configureCellUI] Setting determinate progress: %f%%", progress.doubleValue);
                [self.progressBarNew stopAnimation];
                self.progressBarNew.progressMode = MPOProgressBarModeDeterminate;
                
                // Use CATransaction for explicit animation control
                [CATransaction begin];
                [CATransaction setDisableActions:NO];
                [CATransaction setAnimationDuration:0.3];
                self.progressBarNew.progress = progress.doubleValue / 100.0;
                [CATransaction commit];
                
                // CRITICAL: Ensure visibility
                self.progressBarNew.opacity = 1.0;
                [self.progressBarNew setHidden:NO];
                [self.progressBarNew setNeedsDisplay];
                
                qldebug(@"[configureCellUI] progressBarNew shown - opacity: %f, hidden: %d",
                       self.progressBarNew.opacity, self.progressBarNew.hidden);
            } else {
                qldebug(@"[configureCellUI] Setting indeterminate progress");
                self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
                self.progressBarNew.opacity = 1.0;
                [self.progressBarNew setHidden:NO];
                [self.progressBarNew startAnimation];
                [self.progressBarNew setNeedsDisplay];
                
                qldebug(@"[configureCellUI] progressBarNew shown (indeterminate) - opacity: %f, hidden: %d",
                       self.progressBarNew.opacity, self.progressBarNew.hidden);
            }
            
            [self->_swActionStatusText setHidden:NO];
            self->_swActionStatusText.stringValue = statusText ?: @"";
            
            [self.actionButton setEnabled:NO];
            [self.actionButton setTitle:isUninstall ? @"Uninstalling" : @"Installing"];
        });
        
        // Re-setup notifications for this specific row ID
        if (isUninstall) {
            [self setupUninstallNotification];
        } else {
            [self setupNotification];
        }
        
    } else {
        // Normal state - no operation in progress
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_progressBar setHidden:YES];
            [self.progressBarNew stopAnimation];
            [self.progressBarNew setHidden:YES];
            [self->_swActionStatusText setHidden:YES];
            self->_swActionStatusText.stringValue = @"";
            [self->_swDescription setFrameSize:NSMakeSize(500.0, 86.0)];
            
            if (self->_isAppInstalled) {
                [self.actionButton setTitle:@"Uninstall"];
                self->_installedStateImage.image = [NSImage imageNamed:@"GoodImage"];
            } else {
                [self.actionButton setTitle:@"Install"];
            }
            
            if (self->_isLocalAppInstalled) {
                self->_installedStateImage.image = [NSImage imageNamed:@"GoodImageHD"];
                self->_installedStateImage.toolTip = @"Application is installed, but not managed by MacPatch.";
            }
            
            [self.actionButton setEnabled:YES];
        });
    }
}

- (void)viewDidLoad
{
    qldebug(@"[CELL IMAGE][viewDidLoad]: %@", _rowData[@"Software"][@"sw_img_path"] ?: @"(null)");
}

- (void)viewDidMoveToWindow
{
    qldebug(@"[CELL IMAGE][viewDidMoveToWindow]: %@", _rowData[@"Software"][@"sw_img_path"] ?: @"(null)");
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    // Drawing code here.
}

- (void)loadImage
{
    NSString *imgURL = _rowData[@"Software"][@"sw_img_path"];
    if ([imgURL isEqualToString:@"None"]) return; //If no image then dont try
    qldebug(@"[CELL IMAGE][1]: %@", imgURL);
    qldebug(@"[loadImage][serverArray]: %@",self.serverArray);
    qldebug(@"[loadImage][requestCount]: %ld",self.requestCount);
    
    if (self.requestCount == -1) {
        self.requestCount++;
    } else {
        if (self.requestCount >= (self.serverArray.count - 1)) {
            qlerror(@"[SoftwareCellView][loadImage]: Error, could not complete request, failed all servers.");
            self.requestCount = -1;
            return;
        } else {
            self.requestCount++;
        }
    }
    
    Server *server = [self.serverArray objectAtIndex:self.requestCount];
    NSString *urlPath = [NSString stringWithFormat:@"/mp-content%@",imgURL.urlEncode];
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qldebug(@"[CELL IMAGE][2]: %@", url);
    //qldebug(@"[CELL IMAGE][%@]: %@", _rowData[@"name"], url);
    //qlinfo(@"[CELL IMAGE][%@]: %@", _rowData[@"name"], url);
    __block STHTTPRequest *r = [STHTTPRequest requestWithURLString:url];
    r.allowSelfSignedCert = server.allowSelfSigned;
    __weak STHTTPRequest *wr = r;
    __block __typeof(self) weakSelf = self;
    
    r.completionDataBlock = ^(NSDictionary *headers, NSData *data)
    {
        __strong STHTTPRequest *sr = wr;
        if(sr == nil) return;
        if (sr.responseStatus >= 200 && sr.responseStatus <= 299) {
            NSImage *image = [[NSImage alloc] initWithData:data];
            [self.swIcon setImage:image];
            self.requestCount = -1;
        } else {
            [weakSelf loadImage];
        }
    };
    // Error block
    r.errorBlock = ^(NSError *error)
    {
        if (![error.localizedDescription containsString:@"pretending"]) { // CEH Dont want to see the error during testing
            qlerror(@"%@",error.localizedDescription);
        }
        [weakSelf loadImage];
    };
    
    [r startAsynchronous];
}

// Setup User Notification for Software Install Operation
- (void)setupNotification
{
    NSString *cellStartNote = [NSString stringWithFormat:@"swStart-%@",_rowData[@"id"]];
    NSString *cellProgressNote = [NSString stringWithFormat:@"swProg-%@",_rowData[@"id"]];
    NSString *cellStopNote = [NSString stringWithFormat:@"swStop-%@",_rowData[@"id"]];
    
    // Remove any existing observers first to prevent duplicates
    [self removeNotificationObserver];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             // Verify this cell still represents the same row
             NSString *notificationID = note.userInfo[@"id"] ?: self->_rowData[@"id"];
             if ([self->_rowData[@"id"] isEqualToString:notificationID]) {
                 qlinfo(@"[setupNotification] Start notification received");
                 [self->_actionButton setTitle:@"Installing..."];
             }
         });
     }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
     {
        NSDictionary *userInfo = note.userInfo;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Verify this cell still represents the same row
            NSString *notificationID = userInfo[@"id"] ?: self->_rowData[@"id"];
            if ([self->_rowData[@"id"] isEqualToString:notificationID]) {
                // Update status text
                if (userInfo[@"status"]) {
                    self->_swActionStatusText.stringValue = userInfo[@"status"];
                }
                
                // FIX: Update the progress bar directly with CATransaction
                NSNumber *prog = userInfo[@"progress"] ?: @0;
                qldebug(@"[setupNotification] Progress update: %f%% (progressBarNew: %p, hidden: %d, opacity: %f)",
                       prog.doubleValue, self.progressBarNew, self.progressBarNew.hidden, self.progressBarNew.opacity);
                
                if (prog.doubleValue > 0) {
                    // Switch to determinate mode and show progress
                    if (self.progressBarNew.progressMode != MPOProgressBarModeDeterminate) {
                        qldebug(@"[setupNotification] Switching to determinate mode");
                        [self.progressBarNew stopAnimation];
                        self.progressBarNew.progressMode = MPOProgressBarModeDeterminate;
                    }
                    
                    // Use CATransaction to ensure the layer updates
                    [CATransaction begin];
                    [CATransaction setDisableActions:NO];
                    [CATransaction setAnimationDuration:0.3];
                    self.progressBarNew.progress = prog.doubleValue / 100.0;
                    [CATransaction commit];
                    
                    // CRITICAL: Ensure visibility
                    self.progressBarNew.opacity = 1.0;
                    [self.progressBarNew setHidden:NO];
                    [self.progressBarNew setNeedsDisplay];
                    
                    qldebug(@"[setupNotification] Progress bar updated to: %f (%.1f%%), opacity: %f, hidden: %d",
                           self.progressBarNew.progress, prog.doubleValue, self.progressBarNew.opacity, self.progressBarNew.hidden);
                }
                
                // Also notify the delegate
                if ([self.delegate respondsToSelector:@selector(softwareCellView:didUpdateProgress:status:rowData:)]) {
                    [self.delegate softwareCellView:self didUpdateProgress:prog.doubleValue status:(userInfo[@"status"] ?: @"") rowData:self.rowData];
                }
            }
        });
     }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:cellStopNote object:nil queue:nil usingBlock:^(NSNotification *note)
    {
        NSDictionary *userInfo = note.userInfo;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Verify this cell still represents the same row
            NSString *notificationID = userInfo[@"id"] ?: self->_rowData[@"id"];
            if ([self->_rowData[@"id"] isEqualToString:notificationID]) {
                qldebug(@"[setupNotification] Stop notification received");
                if (userInfo[@"error"]) {
                    self->_swActionStatusText.stringValue = userInfo[@"status"] ?: @"Error";
                    [self stopInstallWithError:YES];
                } else {
                    [self stopInstallWithError:NO];
                }
            }
        });
     }];
}

- (void)setupUninstallNotification
{
    NSString *cellStartNote = [NSString stringWithFormat:@"swUnStart-%@",_rowData[@"id"]];
    NSString *cellProgressNote = [NSString stringWithFormat:@"swUnProg-%@",_rowData[@"id"]];
    NSString *cellStopNote = [NSString stringWithFormat:@"swUnStop-%@",_rowData[@"id"]];
    
    // Remove any existing observers first to prevent duplicates
    [self removeUninstallNotificationObserver];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:cellStartNote object:nil queue:nil usingBlock:^(NSNotification *note)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             // Verify this cell still represents the same row
             NSString *notificationID = note.userInfo[@"id"] ?: self->_rowData[@"id"];
             if ([self->_rowData[@"id"] isEqualToString:notificationID]) {
                 qlinfo(@"[setupUninstallNotification] Start notification received");
                 [self->_actionButton setTitle:@"Uninstalling..."];
             }
         });
     }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:cellProgressNote object:nil queue:nil usingBlock:^(NSNotification *note)
     {
         NSDictionary *userInfo = note.userInfo;
         dispatch_async(dispatch_get_main_queue(), ^{
             // Verify this cell still represents the same row
             NSString *notificationID = userInfo[@"id"] ?: self->_rowData[@"id"];
             if ([self->_rowData[@"id"] isEqualToString:notificationID]) {
                 // Update status text
                 if (userInfo[@"status"]) {
                     self->_swActionStatusText.stringValue = userInfo[@"status"];
                 }
                 
                 // FIX: Update the progress bar directly with CATransaction
                 NSNumber *prog = userInfo[@"progress"] ?: @0;
                 qldebug(@"[setupUninstallNotification] Progress update: %f%% (progressBarNew: %p, hidden: %d, opacity: %f)",
                        prog.doubleValue, self.progressBarNew, self.progressBarNew.hidden, self.progressBarNew.opacity);
                 
                 if (prog.doubleValue > 0) {
                     // Switch to determinate mode and show progress
                     if (self.progressBarNew.progressMode != MPOProgressBarModeDeterminate) {
                         qldebug(@"[setupUninstallNotification] Switching to determinate mode");
                         [self.progressBarNew stopAnimation];
                         self.progressBarNew.progressMode = MPOProgressBarModeDeterminate;
                     }
                     
                     // Use CATransaction to ensure the layer updates
                     [CATransaction begin];
                     [CATransaction setDisableActions:NO];
                     [CATransaction setAnimationDuration:0.3];
                     self.progressBarNew.progress = prog.doubleValue / 100.0;
                     [CATransaction commit];
                     
                     // CRITICAL: Ensure visibility
                     self.progressBarNew.opacity = 1.0;
                     [self.progressBarNew setHidden:NO];
                     [self.progressBarNew setNeedsDisplay];
                     
                     qldebug(@"[setupUninstallNotification] Progress bar updated to: %f (%.1f%%), opacity: %f, hidden: %d",
                            self.progressBarNew.progress, prog.doubleValue, self.progressBarNew.opacity, self.progressBarNew.hidden);
                 }
             }
         });
     }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:cellStopNote object:nil queue:nil usingBlock:^(NSNotification *note)
     {
         NSDictionary *userInfo = note.userInfo;
         dispatch_async(dispatch_get_main_queue(), ^{
             // Verify this cell still represents the same row
             NSString *notificationID = userInfo[@"id"] ?: self->_rowData[@"id"];
             if ([self->_rowData[@"id"] isEqualToString:notificationID]) {
                 qlinfo(@"[setupUninstallNotification] Stop notification received");
                 if (userInfo[@"error"]) {
                     self->_swActionStatusText.stringValue = userInfo[@"status"] ?: @"Error";
                     [self stopUninstallWithError:YES];
                 } else {
                     [self stopUninstallWithError:NO];
                 }
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
        if ([self.delegate respondsToSelector:@selector(softwareCellViewDidStartInstall:rowData:)]) {
            [self.delegate softwareCellViewDidStartInstall:self rowData:self.rowData];
        }
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
        self->_swActionStatusText.stringValue = aStatus ?: @"";
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
        [self.actionButton setEnabled:YES];
        [self->_swDescription setFrameSize:NSMakeSize(500.0, 86.0)];
    });
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // CRITICAL: Remove notification observers to prevent cross-cell updates
    [self removeNotificationObserver];
    [self removeUninstallNotificationObserver];
    
    // Reset NSProgressIndicator
    [_progressBar stopAnimation:nil];
    [_progressBar setIndeterminate:YES];
    [_progressBar setHidden:YES];

    // Reset MPOProgressBar (custom progress bar)
    if (self.progressBarNew) {
        [self.progressBarNew stopAnimation];
        [self.progressBarNew setHidden:YES];
    }

    // Reset status text and images
    _swActionStatusText.hidden = YES;
    _swActionStatusText.stringValue = @"";
    [self.errorImage setHidden:YES];
    [self.actionButton setEnabled:YES];
    
    // Reset action button state
    [self.actionButton setTitle:@"Install"];
    [self.actionButton setState:0];
    
    // Reset installed state image
    [self.installedStateImage setImage:[NSImage imageNamed:@"EmptyImage"]];
}

- (void)prepareForReuseLikeReset
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Reset NSProgressIndicator
        [self->_progressBar stopAnimation:nil];
        [self->_progressBar setIndeterminate:YES];
        [self->_progressBar setHidden:YES];
        [self->_progressBar display];

        // Reset MPOProgressBar (custom progress bar)
        if (self.progressBarNew) {
            [self.progressBarNew stopAnimation];
            [self.progressBarNew setHidden:YES];
        }

        // Reset status text and images
        self->_swActionStatusText.hidden = YES;
        self->_swActionStatusText.stringValue = @"";
        [self.errorImage setHidden:YES];
        [self.actionButton setEnabled:YES];
    });
}

- (void)setupCellUIForInstall
{
    dispatch_async(dispatch_get_main_queue(), ^{
        qldebug(@"[setupCellUIForInstall] Starting setup");
        [self->_errorImage setHidden:YES];
        [self->_swDescription setFrameSize:NSMakeSize(350.0, 86.0)]; // Resize the Description Field
        
        // Explicitly hide old progress bar
        [self->_progressBar setHidden:YES];
        [self->_progressBar stopAnimation:nil];
        
        // Ensure progress bar is set up
        [self setupProgressBar];
        
        // Set up new progress bar
        qldebug(@"[setupCellUIForInstall] Setting up progressBarNew (pointer: %p)", self.progressBarNew);
        self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
        self.progressBarNew.progress = 0.0; // Explicitly set to 0
        
        // CRITICAL: Ensure visibility
        self.progressBarNew.opacity = 1.0;
        [self.progressBarNew setHidden:NO];
        [self.progressBarNew startAnimation];
        [self.progressBarNew setNeedsDisplay];
        
        qldebug(@"[setupCellUIForInstall] progressBarNew configured - hidden: %d, progress: %f, opacity: %f",
               self.progressBarNew.hidden, self.progressBarNew.progress, self.progressBarNew.opacity);
        
        [self->_swActionStatusText setHidden:NO];
        self->_swActionStatusText.stringValue = @"Starting install...";
        [self->_swActionStatusText display];
        
        [self.actionButton setTitle:@"Installing"];
        [self.actionButton setEnabled:NO];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"disableSWCatalogMenu" object:nil userInfo:@{}];
    });
}

- (void)setupCellUIForUninstall
{
    dispatch_async(dispatch_get_main_queue(), ^{
        qldebug(@"[setupCellUIForUninstall] Starting setup");
        [self->_errorImage setHidden:YES];
        [self->_swDescription setFrameSize:NSMakeSize(350.0, 86.0)]; // Resize the Description Field
        
        // Explicitly hide old progress bar
        [self->_progressBar setHidden:YES];
        [self->_progressBar stopAnimation:nil];
        
        // Ensure progress bar is set up
        [self setupProgressBar];
        
        // Set up new progress bar
        qldebug(@"[setupCellUIForUninstall] Setting up progressBarNew (pointer: %p)", self.progressBarNew);
        self.progressBarNew.progressMode = MPOProgressBarModeIndeterminate;
        self.progressBarNew.progress = 0.0; // Explicitly set to 0
        
        // CRITICAL: Ensure visibility
        self.progressBarNew.opacity = 1.0;
        [self.progressBarNew setHidden:NO];
        [self.progressBarNew startAnimation];
        [self.progressBarNew setNeedsDisplay];
        
        qldebug(@"[setupCellUIForUninstall] progressBarNew configured - hidden: %d, progress: %f, opacity: %f",
               self.progressBarNew.hidden, self.progressBarNew.progress, self.progressBarNew.opacity);
        
        [self->_swActionStatusText setHidden:NO];
        self->_swActionStatusText.stringValue = @"Starting uninstall...";
        [self->_swActionStatusText display];
        
        [self.actionButton setTitle:@"Uninstalling"];
        [self.actionButton setEnabled:NO];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"disableSWCatalogMenu" object:nil userInfo:@{}];
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
        [self->_progressBar setIndeterminate:YES];
        [self->_progressBar setHidden:YES];
        [self->_progressBar display];
        
        [self.progressBarNew stopAnimation];
        [self.progressBarNew setHidden:YES];
        
        if (hadError)
        {
            [self.errorImage setHidden:NO];
            if (isUninstall) {
                [self.actionButton setTitle:@"Uninstall"];
            } else {
                [self.actionButton setTitle:@"Install"];
                self->_installedStateImage.image = [NSImage imageNamed:@"ErrorImage"];
            }
            if (errStr) self->_swActionStatusText.stringValue = errStr;
        }
        else
        {
            self->_swActionStatusText.stringValue = @" ";
            if (isUninstall) {
                [self.actionButton setTitle:@"Install"];
            } else {
                [self.actionButton setTitle:@"Uninstall"];
                self->_installedStateImage.image = [NSImage imageNamed:@"GoodImage"];
                
                if ([self->_rowData[@"Software"][@"reboot"] isEqualToString:@"1"])
                {
                    AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
                    [appDelegate showSWRebootWindow];
                }
            }
        }
        
        [self->_progressBarNew stopAnimation];
        [self->_progressBarNew setHidden:YES];
        
        [self.actionButton setEnabled:YES];
        [self->_swDescription setFrameSize:NSMakeSize(500.0, 86.0)];
        
        if ([self.delegate respondsToSelector:@selector(softwareCellViewDidFinish:success:errorMessage:rowData:)]) {
            BOOL success = !hadError;
            [self.delegate softwareCellViewDidFinish:self success:success errorMessage:errStr rowData:self.rowData];
        }
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
                if (hadError)
                {
                    [[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                        qlerror(@"proxyError: %@",proxyError.localizedDescription);
                    }] recordHistoryWithType:kMPSoftwareType name:self->_rowData[@"name"] uuid:self->_rowData[@"id"] action:kMPInstallAction result:1 errorMsg:@"" withReply:^(BOOL result) {
                        //[[NSNotificationCenter defaultCenter] postNotificationName:kRefreshSoftwareTable object:nil userInfo:@{}];
                    }];
                }
                else
                {
                    [[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                        qlerror(@"proxyError: %@",proxyError.localizedDescription);
                    }] recordSoftwareInstallAdd:self->_rowData withReply:^(NSInteger result) {
                        //[[NSNotificationCenter defaultCenter] postNotificationName:kRefreshSoftwareTable object:nil userInfo:@{}];
                    }];
                }
            }
            
        }
    }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"enableSWCatalogMenu" object:nil userInfo:@{}];
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
        
        [self.progressBarNew stopAnimation];
        [self.progressBarNew setHidden:YES];
        
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
                //qlinfo(@"Code %ld",(long)result);
                //[[NSNotificationCenter defaultCenter] postNotificationName:kRefreshSoftwareTable object:nil userInfo:@{}];
            }];
        }
    }];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"enableSWCatalogMenu" object:nil userInfo:@{}];
    [self removeUninstallNotificationObserver];
}
@end
