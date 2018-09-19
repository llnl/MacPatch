//
//  MPCatalogAppDelegate.m
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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

#import "MPCatalogAppDelegate.h"
#import "PreferenceController.h"
#import "MacPatch.h"
#import "MPWorkerProtocol.h"
#import "EventToSend.h" 
#import "SWDistInfoController.h"
#import "RebootWindow.h"

#define MP_INSTALLED_DATA       @".installed.plist"

@interface MPInstallIconValueTransformer: NSValueTransformer
{
    NSImage *installedImage;
    NSImage *insallingImage;
    NSImage *errorImage;
    NSImage *emptyImage;
    NSImage *downloadImage;
}
@end

@implementation MPInstallIconValueTransformer

- (id)init
{
    if (self = [super init]) 
    {
        installedImage = [NSImage imageNamed:@"Installcomplete"];
        insallingImage = [NSImage imageNamed:@"running"];
        errorImage = [NSImage imageNamed:@"exclamation"];
        emptyImage = [NSImage imageNamed:@"empty"];
        downloadImage = [NSImage imageNamed:@"blue_down_16"];
        
    }
    return self;
}

- (void)dealloc 
{
    installedImage = nil;
    insallingImage = nil;
    errorImage = nil;
    emptyImage = nil;
    downloadImage = nil;
}

+ (Class)transformedValueClass { return [NSImage class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value 
{
    if ([value intValue] == 0) {
        return emptyImage;
    } else if ([value intValue] == 1) {
        return installedImage;
    } else if ([value intValue] == 2) {
        return insallingImage;
    } else if ([value intValue] == 3) {
        return errorImage;
    } else if ([value intValue] == 4) {
        return downloadImage;    
    } else {
        return emptyImage;
    }
    //return ([value boolValue] ? installedImage : emptyImage);
}
@end

@interface MPBOOLIconValueTransformer: NSValueTransformer
{
    NSImage *installedImage;
    NSImage *emptyImage;
}
@end

@implementation MPBOOLIconValueTransformer

- (id)init
{
    if (self = [super init]) 
    {
        installedImage = [NSImage imageNamed:@"Installcomplete"];
        emptyImage = [NSImage imageNamed:@"empty"];
    }
    return self;
}

- (void)dealloc 
{
    installedImage = nil;
    emptyImage = nil;
}

+ (Class)transformedValueClass { return [NSImage class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value 
{
    return ([value boolValue] ? installedImage : emptyImage);
}
@end

#pragma mark -

@interface MPBOOLRebootIconValueTransformer: NSValueTransformer
{
    NSImage *rebootImage;
    NSImage *emptyImage;
}
@end

@implementation MPBOOLRebootIconValueTransformer

- (id)init 
{
    if (self = [super init]) 
    {
        rebootImage = [NSImage imageNamed:@"RestartReq"];
        emptyImage = [NSImage imageNamed:@"empty"];
    }
    return self;
}

- (void)dealloc 
{
    rebootImage = nil;
    emptyImage = nil;
}

+ (Class)transformedValueClass { return [NSImage class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value 
{
    return ([value boolValue] ? rebootImage : emptyImage);
}
@end

@interface FileSizeTransformer : NSValueTransformer

+ (Class)transformedValueClass;
+ (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)value;

@end

@implementation FileSizeTransformer
+ (Class)transformedValueClass;
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;
}
- (id)transformedValue:(id)value;
{
    // Data contains "K" remove it to turn it in to a number value
    double convertedValue = [[value stringByReplacingOccurrencesOfString:@"K" withString:@""] doubleValue];
    // Data is already at k, other wise set bytes to 0
    int multiplyFactor = 1;

    NSArray *tokens = [NSArray arrayWithObjects:@"B",@"KB",@"MB",@"GB",@"TB",nil];

    while (convertedValue > 1024) {
        convertedValue /= 1024;
        multiplyFactor++;
    }

    return [NSString stringWithFormat:@"%4.2f %@",convertedValue, [tokens objectAtIndex:multiplyFactor]];
}
@end

#pragma mark -

// Private Methods
@interface MPCatalogAppDelegate ()
{
    MPSettings *settings;
}

// Reboot
- (IBAction)showRebootPanel:(id)sender;
- (IBAction)closeRebootPanel:(id)sender;
- (IBAction)closeRebootPanelAndReboot:(id)sender;
- (void)rebootPanelDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo;

@property (strong) RebootWindow *rebootWindowWindowController;

// SW Dist Info
- (IBAction)showSWDistInfo:(id)sender;
- (void)populateSoftwareGroupsPopupButton;

// Install Mandatory Software
- (void)checkAndInstallMandatoryApplications;
- (void)checkAndInstallMandatoryApplicationsThread;
// Helpers
- (NSArray *)filterMandatorySoftwareContent;
- (BOOL)softwareItemInstalled:(NSDictionary *)dict;
- (BOOL)softwareTaskInstalled:(NSString *)aTaskID;

// Install
- (IBAction)installSoftware:(id)sender;
- (void)installSoftwareThread;
- (BOOL)installSoftwareItem:(NSDictionary *)dict;

// Remove
- (IBAction)removeSoftware:(id)sender;
- (void)removeSoftwareThread;

// Actions
- (IBAction)showMainLog:(id)sender;
- (IBAction)showHelperLog:(id)sender;

// Class Methods
- (void)updateArrayControllerWithDictionary:(NSDictionary *)dict;
- (void)updateArrayControllerWithDictionary:(NSDictionary *)dict forActionType:(NSString *)type;
- (void)removeSoftwareInstallStatus:(NSString *)swID;
- (void)downloadSoftwareContent;
- (void)filterSoftwareContent:(NSArray *)content;

- (void)setLoggingState:(BOOL)aState;

// Web Services
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict;
- (void)postUnInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict;

// Helper
- (void)connect;
- (void)cleanup;
- (void)connectionDown:(NSNotification *)notification;

- (int)installSoftwareViaProxy:(NSDictionary *)aInstallDict;
- (int)patchSoftwareViaProxy:(NSDictionary *)aInstallDict;
- (int)removeSoftwareViaProxy:(NSString *)removeScript;
- (int)writeToFileViaProxy:(NSString *)aFile data:(id)data;
- (int)writeArrayFileViaProxy:(NSString *)aFile data:(NSArray *)data;

- (BOOL)hasCanceledInstall:(NSDictionary *)task;

@end

#pragma mark -

// Public

@implementation MPCatalogAppDelegate

@synthesize defaults = _defaults;

@synthesize window;
@synthesize tableView;
@synthesize arrayController;
@synthesize statusTextTitle;
@synthesize statusTextStatus;
@synthesize progressBar;
@synthesize installButton;
@synthesize removeButton;
@synthesize cancelButton;
@synthesize refreshButton;
@synthesize infoButton;
@synthesize swDistGroupsButton;
@synthesize swGroupsPopupButton;
@synthesize selectedItems;
@synthesize swDistGroupsArray;

@synthesize rebootPanel;

@synthesize queue;
@synthesize cancelInstalls;
@synthesize _selectionColumn;
@synthesize tableColEdit;
@synthesize mp_SOFTWARE_DATA_DIR;
@synthesize swDistInfoPanelDict;
@synthesize swDistInfoPanel;
@synthesize swDistCurrentTitle;

#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{
	// Center the Window
	[window center];
	[self loadInitialContent];
	[swDistGroupsButton addItemWithTitle:@"Bob"];
	[swDistGroupsButton display];
	[swDistGroupsButton setEnabled:YES];
}

- (void)awakeFromNib
{
    fm = [NSFileManager defaultManager];
    queue = [[NSOperationQueue alloc] init];
    selectedItems = [[NSMutableArray alloc] init];
    settings = [MPSettings sharedInstance];
    
    // User Defaults 
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if (![d objectForKey:@"colBaselineOnLaunch"]) {
		[d setBool:NO forKey:@"colBaselineOnLaunch"];
	}
	if (![d objectForKey:@"colSizeOnLaunch"]) {
		[d setBool:YES forKey:@"colSizeOnLaunch"];
	}
	if (![d objectForKey:@"colStateOnLaunch"]) {
		[d setBool:NO forKey:@"colStateOnLaunch"];
	}
    if (![d objectForKey:@"enableRemoveSoftware"]) {
        [d setBool:YES forKey:@"enableRemoveSoftware"];
    }
    [d synchronize];
    
    // Setup logging
	NSString *_logFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MPCatalog.log"];
	[MPLog setupLogging:_logFile level:lcl_vInfo];
    
	if ([d boolForKey:@"enableDebugLogging"]) {
		// enable logging for all components up to level Debug
		lcl_configure_by_name("*", lcl_vDebug);
		logit(lcl_vInfo,@"***** MP SW Catalog started -- Debug Enabled *****");
	} else {
		// enable logging for all components up to level Info
		lcl_configure_by_name("*", lcl_vInfo);
		logit(lcl_vInfo,@"***** MP SW Catalog started *****");
	}
    
    // Set Data Directory
    NSURL *appSupportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
    NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch"];
    [self setMp_SOFTWARE_DATA_DIR:[appSupportMPDir URLByAppendingPathComponent:@"SW_Data"]];
    if ([fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]] == NO) {
        NSError *err = nil;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
    }
    if ([fm fileExistsAtPath:[[mp_SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] path]] == NO) {
        NSError *err = nil;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        [fm createDirectoryAtPath:[[mp_SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] path] withIntermediateDirectories:YES attributes:attributes error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
        [[mp_SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsHiddenKey error:NULL];
    }
    
    [progressBar setUsesThreadedAnimation:YES];
    [installButton setEnabled:NO];
    [removeButton  setEnabled:NO];
    [cancelButton  setEnabled:NO];
    [infoButton    setEnabled:NO];

    [self setTableColEdit:YES];
    
    // Connect to Helper
    logit(lcl_vInfo,@"Start");
    if ([d boolForKey:@"enableDebugLogging"])
        [self setLoggingState:[d boolForKey:@"enableDebugLogging"]];
	
    [self.window display];
}

- (void)loadInitialContent
{
	[swDistGroupsButton removeAllItems];
	
	NSError *error = nil;
	NSArray *catalogs = [NSArray array];
	MPRESTfull *rest = [[MPRESTfull alloc] init];
	catalogs = [rest getSoftwareCatalogs:&error];
	
	if (error) {
		logit(lcl_vError,@"%@",error.localizedDescription);
		[swDistGroupsButton addItemWithTitle:settings.agent.swDistGroup];
		return;
	}
	
	if ([catalogs count] > 0)
	{
		[self setSwDistGroupsArray:catalogs];
		
		NSMutableSet *titles = [NSMutableSet new];
		[self setSwDistGroupsArray:catalogs];
		for (NSDictionary *n in catalogs) {
			[titles addObject:n[@"Name"]];
		}
		
		NSArray *sorted = [[titles allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
		[swDistGroupsButton addItemsWithTitles:sorted];
		
		if (settings.agent.swDistGroup != nil) {
			[swDistGroupsButton selectItemAtIndex:[[swDistGroupsButton itemTitles] indexOfObject:settings.agent.swDistGroup]];
		} else {
			[swDistGroupsButton selectItemAtIndex:0];
		}
		
	} else {
		[swDistGroupsButton addItemWithTitle:settings.agent.swDistGroup];
	}
	
	[swDistGroupsButton display];
	// Set title
	window.title = [NSString stringWithFormat:@"MP - Software Catalog (%@)",[[swDistGroupsButton selectedItem] title]];
	
	[self performSelectorInBackground:@selector(downloadSoftwareContent) withObject:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

-(IBAction)windowCloseWillExit:(id)sender
{
	[NSApp terminate:nil];
}

- (void)dealloc
{
    [self cleanup];
}

- (IBAction)showRebootPanel:(id)sender
{
    if (NSAppKitVersionNumber < NSAppKitVersionNumber10_9) {
        
        [NSApp beginSheet: rebootPanel
           modalForWindow: window
            modalDelegate: self
           didEndSelector: @selector(rebootPanelDidEnd:returnCode:contextInfo:)
              contextInfo: nil];
        
    } else {
        // Mac OS X 10.9 and higher
        dispatch_async(dispatch_get_main_queue(), ^{
            
            self.rebootWindowWindowController = [[RebootWindow alloc] initWithWindowNibName:@"RebootWindow"];
            [self.window beginSheet:self.rebootWindowWindowController.window  completionHandler:^(NSModalResponse returnCode) {
                
                switch (returnCode) {
                    case NSModalResponseOK:
                        [self rebootPanelDidEnd:nil returnCode:1 contextInfo:nil];
                        break;
                    case NSModalResponseCancel:
                        // Close the window
                        break;
                    default:
                        // Close the window
                        break;
                }
                
                self.rebootWindowWindowController = nil;
            }];
        
        });
    }
}

- (IBAction)closeRebootPanel:(id)sender
{
    [NSApp endSheet:rebootPanel returnCode:0];
} 

- (IBAction)closeRebootPanelAndReboot:(id)sender
{
    [NSApp endSheet:rebootPanel returnCode:1];
} 

- (void)rebootPanelDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [sheet orderOut:self];
    // Reboot
    if (returnCode == 1) {
        OSStatus error = noErr;
        error = SendAppleEventToSystemProcess(kAEShowRestartDialog);
        if (error == noErr) {
            [NSApp terminate:self];
        }
    }
}

- (IBAction)showPreferencePanel:(id)sender
{
    // Is preferenceController nil?
    if (!preferenceController) {
		preferenceController = [[PreferenceController alloc] init];
    }
    [preferenceController showWindow:self];
}

- (IBAction)showSWDistInfo:(id)sender
{
    if (!swDistInfoController) {
        swDistInfoController = [[SWDistInfoController alloc] init];
    }
    
    [swDistInfoController setSwDistInfoPanelDict:[selectedItems objectAtIndex:0]];
    [swDistInfoController showWindow:self];
}

- (void)populateSoftwareGroupsPopupButton
{
    @autoreleasepool
    {
		[swDistGroupsButton removeAllItems];
        
        NSError *error = nil;
        NSArray *catalogs = [NSArray array];
        MPRESTfull *rest = [[MPRESTfull alloc] init];
        
        catalogs = [rest getSoftwareCatalogs:&error];
        
        if (error) {
            logit(lcl_vError,@"%@",error.localizedDescription);
            [swDistGroupsButton addItemWithTitle:settings.agent.swDistGroup];
            return;
        }
        
        if ([catalogs count] > 0)
        {
			NSMutableSet *titles = [NSMutableSet new];
            [self setSwDistGroupsArray:catalogs];
            for (NSDictionary *n in catalogs) {
				[titles addObject:n[@"Name"]];
				//[swDistGroupsButton addItemWithTitle:n[@"Name"]];
            }
			
			NSArray *sorted = [[titles allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
			[swDistGroupsButton addItemsWithTitles:sorted];
        } else {
            [swDistGroupsButton addItemWithTitle:settings.agent.swDistGroup];
        }
		
		[swDistGroupsButton display];
    }
}

- (IBAction)popUpChanged:(id)sender
{
    if ([[sender title] isEqualToString:swDistCurrentTitle] == NO) {
        [self refreshSoftware:nil];
    }
}

#pragma mark - Install Mandatory Software

- (void)checkAndInstallMandatoryApplications
{
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"enableInstallOnLaunch"] == nil) 
    {
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"enableInstallOnLaunch"];
    }
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"enableInstallOnLaunch"] == 1) {
        logit(lcl_vInfo,@"Check and install any mandatory applications.");
        [self checkAndInstallMandatoryApplicationsThread];
    }
}

- (void)checkAndInstallMandatoryApplicationsThread
{
    NSArray *mandatoryInstllTasks;
    mandatoryInstllTasks = [self filterMandatorySoftwareContent];
    
    // Check to see if there is anything to install
    if (mandatoryInstllTasks == nil || [mandatoryInstllTasks count] <= 0) {
        return;
    }
    
    MPDiskUtil *mpd = [[MPDiskUtil alloc] init];
    
    // *****************************************
    // Install the mandatory software
    // *****************************************
    int _needsReboot = 0;
    for (NSDictionary *d in mandatoryInstllTasks) 
    {
        [statusTextStatus setStringValue:[NSString stringWithFormat:@"Installing %@ ...",[d objectForKey:@"name"]]];
        logit(lcl_vInfo,@"Installing %@ (%@).",[d objectForKey:@"name"],[d objectForKey:@"id"]);
        logit(lcl_vInfo,@"INFO: %@",[d valueForKeyPath:@"Software.sw_type"]);
        
        // *****************************************
        // Create Path to download software to
        // *****************************************
        NSString *swLoc = NULL;
        NSString *swLocBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
        swLoc = [NSString pathWithComponents:[NSArray arrayWithObjects:swLocBase, [d objectForKey:@"id"], nil]];
        
        // *****************************************
        // Verify Disk space requirements before downloading and installing
        // *****************************************
        NSScanner* scanner = [NSScanner scannerWithString:[d valueForKeyPath:@"Software.sw_size"]];
        long long stringToLong;
        if(![scanner scanLongLong:&stringToLong])
        {
            logit(lcl_vError,@"Unable to convert size %@",[d valueForKeyPath:@"Software.sw_size"]);
            [self postInstallResults:99 resultText:@"Unable to calculate size." task:d];
            [self updateArrayControllerWithDictionary:d forActionType:@"error"];
            continue;
        }
        
        if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO) 
        {
            logit(lcl_vError,@"This system does not have enough free disk space to install the following software %@",[d objectForKey:@"name"]);
            [self postInstallResults:99 resultText:@"Not enough free disk space." task:d];
            [self updateArrayControllerWithDictionary:d forActionType:@"error"];
            continue;
        }
        
        // *****************************************
        // Create Download URL PATH
        // *****************************************
        NSString *urlPath = [NSString stringWithFormat:@"/mp-content%@",[d valueForKeyPath:@"Software.sw_url"]];
        logit(lcl_vInfo,@"Download software from: %@",urlPath);
        
        // *****************************************
        // Create the final llcation for the downloaded file
        // *****************************************
        BOOL isDir;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        if ([fm fileExistsAtPath:swLoc isDirectory:&isDir] == NO) {
            [fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:attributes error:NULL];
        } else {
            if (isDir == NO) {
                // Item is not a directory so we need to remove it and create our dir structure
                [fm removeItemAtPath:swLoc error:NULL];
                [fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:attributes error:NULL];
            }
        }
        
        // *****************************************
        // Download Software
        // *****************************************
        dispatch_async(dispatch_get_main_queue(), ^(void){[progressBar setDoubleValue:0.0];});
        dispatch_async(dispatch_get_main_queue(), ^(void){[progressBar setIndeterminate:NO];});
        
        __block NSError *dlErr = nil;
        MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
        NSString *dlPath = [req createTempDownloadDir:urlPath]; // Create temp download dir
        
        // Start download
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [statusTextStatus setStringValue:[NSString stringWithFormat:@"Downloading %@",[d objectForKey:@"name"]]];
        });
        [req runDownloadRequest:urlPath downloadDirectory:dlPath progress:progressBar progressPercent:nil completion:^(NSString *fileName, NSString *filePath, NSError *error)
        {
            if (error) {
                logit(lcl_vError,@"%@", error.localizedDescription);
                dlErr = error;
            }
            else
            {
                logit(lcl_vInfo,@"Successfully downloaded file to %@", fileName);
                dispatch_async(dispatch_get_main_queue(), ^(void){
                    [statusTextStatus setStringValue:[NSString stringWithFormat:@"Successfully downloaded %@",fileName]];
                });
            }
        }];

        [self updateArrayControllerWithDictionary:d forActionType:@"download"];

        // *****************************************
        // Create Destination Dir
        // *****************************************
        dlErr = nil;
        if ([fm fileExistsAtPath:swLoc] == NO) {
            [fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:nil error:&dlErr];
            if (dlErr) {
                logit(lcl_vError,@"Error[%d], trying to create destination directory. %@.",(int)[dlErr code],swLoc);
            }
        }
        
        // *****************************************
        // Move Downloaded File to Destination
        // *****************************************
        dlErr = nil;
        [fm moveItemAtPath:dlPath toPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]] error:&dlErr];
        if (dlErr) {
            logit(lcl_vError,@"Error[%d], trying to move downloaded file to %@.",(int)[dlErr code],swLoc);
        }

        // *****************************************
        // Software was downloaded, start install
        // *****************************************
        if (!dlErr)
        {
            logit(lcl_vDebug,@"Begin install for (%@).",[d objectForKey:@"name"]);
            int result = -1;
            int pResult = -1;
            [progressBar setIndeterminate:YES];
            [progressBar startAnimation:nil];
            [progressBar display];
            
            if ([self hasCanceledInstall:d]) break;
            
            [self updateArrayControllerWithDictionary:d forActionType:@"install"];
            result = [self installSoftwareViaProxy:d];
            
            if (result == 0) 
            {
                // Software has been installed, now flag for reboot
                if ([[d valueForKeyPath:@"Software.reboot"] isEqualTo:@"1"]) {
                    _needsReboot++;
                }
                if ([[d valueForKeyPath:@"Software.auto_patch"] isEqualTo:@"1"])
                {
                    dispatch_async(dispatch_get_main_queue(), ^(void){
                        [statusTextStatus setStringValue:@"Auto Patching is enabled, begin patching..."];
                    });
                    
                    pResult = [self patchSoftwareViaProxy:d];
                    [NSThread sleepForTimeInterval:5];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^(void){
                    [statusTextStatus setStringValue:[NSString stringWithFormat:@"Installing %@ completed.",[d objectForKey:@"name"]]];
                });

                [self installSoftwareItem:d];
                [self updateArrayControllerWithDictionary:d];
            } else {
                [self updateArrayControllerWithDictionary:d forActionType:@"error"];
            }
            
            [self postInstallResults:result resultText:@"" task:d];
            [progressBar stopAnimation:nil];
            [progressBar display];
        }
        
    }
    
    [refreshButton setEnabled:YES];
    [cancelButton setEnabled:NO];
    [self setTableColEdit:YES];
    
    // Apps were installed that require a reboot
    if (_needsReboot >= 1) {
        [self showRebootPanel:nil];
    }

    [self.window display];
}

#pragma mark Helpers Methods

- (NSArray *)filterMandatorySoftwareContent
{
    NSArray *_a = nil;
    int c = 0;
    NSMutableDictionary *d;
    NSDictionary *_SoftwareCriteria;
    NSMutableArray *_MandatorySoftware = [[NSMutableArray alloc] init];
    
    /* If there is content */
    if ([fm fileExistsAtPath:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]] == NO) {
        return nil;
    }

    @try {
        _a = [NSKeyedUnarchiver unarchiveObjectWithFile:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]];
    }
    @catch ( NSException *ex ) {
        //do whatever you need to in case of a crash
        qlwarning(@"%@ is not a NSKeyedArchiver file. Open as a dictionary.\n%@",[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"],ex);
        _a = [NSArray arrayWithContentsOfFile:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]];
    }

    for (id item in _a) 
    {
        d = [[NSMutableDictionary alloc] initWithDictionary:item];
        logit(lcl_vInfo,@"Checking %@",[d objectForKey:@"name"]);
        
        // Check for Mandatory apps
        if ([[d objectForKey:@"sw_task_type"] containsString:@"m" ignoringCase:YES] == NO) {
            logit(lcl_vInfo,@"%@ is not a mandatory application.",[d objectForKey:@"name"]);
            continue;
        }
        
        // Check Install Date Info
        NSDate *now = [NSDate date];
        NSDate *startDate = [NSDate dateFromString:[d objectForKey:@"sw_start_datetime"]];
        NSDate *endDate = [NSDate dateFromString:[d objectForKey:@"sw_end_datetime"]];
        
        if ([now timeIntervalSince1970] < [startDate timeIntervalSince1970]) {
            // Software is not ready for deployment
            continue;
        }
        
        // If it's a Optional / Mandatory App then we wait for the end date
        if ([[d objectForKey:@"sw_task_type"] containsString:@"o" ignoringCase:YES]) 
        {
            if ([now timeIntervalSince1970] >= [endDate timeIntervalSince1970]) 
            {
                logit(lcl_vInfo,@"Optional/Mandatory date has been reached for install.");
            } else {
                continue;
            }
        }
        
        // Check Simple Requirements
        c = 0;
        MPOSCheck *mpos = [[MPOSCheck alloc] init];
        _SoftwareCriteria = [item objectForKey:@"SoftwareCriteria"];
        // OSArch
        if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
            logit(lcl_vInfo,@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
        } else {
            logit(lcl_vInfo,@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
            c++;
        }
        // OSType
        if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
            logit(lcl_vInfo,@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
        } else {
            logit(lcl_vInfo,@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
            c++;
        }
        // OSVersion
        if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
            logit(lcl_vInfo,@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
        } else {
            logit(lcl_vInfo,@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
            c++;
        }
        mpos = nil;
        // Did not pass the criteria check
        if (c >= 1) {
            continue;
        }
        
        // Check to see if it's installed
        if ([self softwareTaskInstalled:[d objectForKey:@"id"]] == NO) {
            // Has not been installed, and is mandatory
            logit(lcl_vInfo,@"Adding %@ to mandatory installs.",[d objectForKey:@"name"]);
            [_MandatorySoftware addObject:d];
        } else {
            logit(lcl_vInfo,@"%@ is already installed.",[d objectForKey:@"name"]);
        }
        
        d = nil;
    }
    
    // Echo which apps are going to be installed.
    for (id x in _MandatorySoftware) {
        logit(lcl_vInfo,@"Approved Mandatory Software task: %@",[x objectForKey:@"name"]);
    }
    NSArray *results = [NSArray arrayWithArray:_MandatorySoftware];
    return results;
}

- (BOOL)softwareItemInstalled:(NSDictionary *)dict
{
    NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
    NSMutableDictionary *installData = [[NSMutableDictionary alloc] init];
    [installData setObject:[NSDate date] forKey:@"installDate"];
    [installData setObject:[dict objectForKey:@"id"] forKey:@"id"];
    [installData setObject:[dict objectForKey:@"name"] forKey:@"name"];
    if ([dict objectForKey:@"sw_uninstall"]) {
        [installData setObject:[dict objectForKey:@"sw_uninstall"] forKey:@"sw_uninstall"];    
    } else {
        [installData setObject:@"" forKey:@"sw_uninstall"];
    }
    NSMutableArray *_data;
    if ([fm fileExistsAtPath:installFile]) {
        _data = [NSMutableArray arrayWithContentsOfFile:installFile];
    } else {
        if (![fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]]) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:NULL];
        }
        _data = [NSMutableArray array];
    }
    [_data addObject:installData];
    [_data writeToFile:installFile atomically:YES];
    return YES;
}

- (BOOL)softwareTaskInstalled:(NSString *)aTaskID
{
    NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
    if ([fm fileExistsAtPath:installFile]) {
        NSArray *a = [NSArray arrayWithContentsOfFile:installFile];
        for (int i = 0; i < [a count];i++) {
            if ([[[a objectAtIndex:i] objectForKey:@"id"] isEqualTo:aTaskID]) {
                return YES; // It's installed ... no need to install
            }
        }
    }
    
    return NO;
}

#pragma mark - Install Software

- (IBAction)installSoftware:(id)sender
{
    [cancelButton setEnabled:YES];
    [NSThread detachNewThreadSelector:@selector(installSoftwareThread) toTarget:self withObject:nil];
}

- (void)installSoftwareThread
{
    @autoreleasepool
    {
        [self setTableColEdit:NO];
        [installButton setEnabled:NO];
        [cancelButton setEnabled:YES];
        [refreshButton setEnabled:NO];
        [swDistGroupsButton setEnabled:NO];
        [self setCancelInstalls:NO];
        
        MPDiskUtil      *mpd                = [[MPDiskUtil alloc] init];
        NSMutableArray  *swToInstallArray   = [NSMutableArray arrayWithArray:[arrayController arrangedObjects]];
        
        int _needsReboot = 0;
        for (NSDictionary *d in swToInstallArray)
        {
            if (cancelInstalls == YES)
            {
                [self setCancelInstalls:NO];
                break;
            }
            
            if ([d objectForKey:@"selected"]) {
                if ([[d objectForKey:@"selected"] intValue] == 1)
                {
                    [statusTextStatus setStringValue:[NSString stringWithFormat:@"Installing %@ ...",[d objectForKey:@"name"]]];
                    logit(lcl_vInfo,@"Installing %@ (%@).",[d objectForKey:@"name"],[d objectForKey:@"id"]);
                    logit(lcl_vInfo,@"INFO: %@",[d valueForKeyPath:@"Software.sw_type"]);
                    
                    if ([self hasCanceledInstall:d]) break;
                    
                    // Create Path to download software to
                    NSString *swLoc = NULL;
                    NSString *swLocBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
                    swLoc = [NSString pathWithComponents:[NSArray arrayWithObjects:swLocBase, [d objectForKey:@"id"], nil]];
                    
                    // Verify Disk space requirements before downloading and installing
                    NSScanner* scanner = [NSScanner scannerWithString:[d valueForKeyPath:@"Software.sw_size"]];
                    long long stringToLong;
                    if(![scanner scanLongLong:&stringToLong]) {
                        logit(lcl_vError,@"Unable to convert size %@",[d valueForKeyPath:@"Software.sw_size"]);
                        [self postInstallResults:99 resultText:@"Unable to calculate size." task:d];
                        [self updateArrayControllerWithDictionary:d forActionType:@"error"];
                        continue;
                    }
                    
                    if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO)
                    {
                        logit(lcl_vError,@"This system does not have enough free disk space to install the following software %@",[d objectForKey:@"name"]);
                        [self postInstallResults:99 resultText:@"Not enough free disk space." task:d];
                        [self updateArrayControllerWithDictionary:d forActionType:@"error"];
                        continue;
                    }
                    
                    // *****************************************
                    // Create Download URL
                    // *****************************************
                    NSString *urlPath = [NSString stringWithFormat:@"/mp-content%@",[d valueForKeyPath:@"Software.sw_url"]];
                    logit(lcl_vDebug,@"Download software from: %@",[d valueForKeyPath:@"Software.sw_type"]);
                    
                    dispatch_async(dispatch_get_main_queue(), ^(void){[progressBar setDoubleValue:0.0];});
                    dispatch_async(dispatch_get_main_queue(), ^(void){[progressBar setIndeterminate:NO];});
                    
                    __block NSError *dlErr = nil;
                    MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
                    NSString *dlPath = [req createTempDownloadDir:d[@"id"]]; // Create temp download dir
                    
                    // *****************************************
                    // Start download
                    // *****************************************
                    dispatch_async(dispatch_get_main_queue(), ^(void){
                        [statusTextStatus setStringValue:[NSString stringWithFormat:@"Downloading %@",[d objectForKey:@"name"]]];
                    });
					
                    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                    [req runDownloadRequest:urlPath downloadDirectory:dlPath progress:progressBar progressPercent:nil completion:^(NSString *fileName, NSString *filePath, NSError *error)
                     {
                         if (error) {
                             logit(lcl_vError,@"%@", error.localizedDescription);
                             dlErr = error;
                         }
                         else
                         {
                             logit(lcl_vInfo,@"Successfully downloaded file to %@", fileName);
                             dispatch_async(dispatch_get_main_queue(), ^(void){
                                 [statusTextStatus setStringValue:[NSString stringWithFormat:@"Successfully downloaded %@",fileName]];
                             });
                         }
						 dispatch_semaphore_signal(sem);
                     }];
					
                    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                    // *****************************************
                    // There was an error downloding the file, no install can ocure
                    // *****************************************
                    if (dlErr) {
                        [self postInstallResults:99 resultText:@"Unable to download software." task:d];
                        [self updateArrayControllerWithDictionary:d forActionType:@"error"];
                        continue;
                    }

                    [self updateArrayControllerWithDictionary:d forActionType:@"download"];
                    
                    // *****************************************
                    // Create Destination Dir
                    // *****************************************
                    NSString *decodedName = [[urlPath lastPathComponent] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
					// Remove the install sw location if exists
					if ([fm fileExistsAtPath:swLoc]) {
						[self removeDirectoryViaProxy:swLoc];
					}
					
					// Create the directory where we will put the installer
					dlErr = nil;
					[fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:nil error:&dlErr];
					if (dlErr) {
						logit(lcl_vError,@"Error[%d], trying to create destination directory. %@.",(int)[dlErr code],swLoc);
					}
                    
                    // *****************************************
                    // Move Downloaded File to Destination
                    // *****************************************
					logit(lcl_vDebug,@"Moving downloaded file %@ to destination %@.",dlPath, [swLoc stringByAppendingPathComponent:decodedName]);
                    dlErr = nil;
                    [fm moveItemAtPath:[dlPath stringByAppendingPathComponent:decodedName] toPath:[swLoc stringByAppendingPathComponent:decodedName] error:&dlErr];
                    if (dlErr) {
                        logit(lcl_vError,@"Error[%d], trying to move downloaded file to %@.",(int)[dlErr code],swLoc);
                    }
                    
                    if ([self hasCanceledInstall:d]) break;
                    
                    // *****************************************
                    // Software was downloaded, now install software
                    // *****************************************
                    if (!dlErr)
                    {
                        logit(lcl_vDebug,@"Begin install for (%@).",[d objectForKey:@"name"]);
                        int result = -1;
                        int pResult = -1;
                        
                        [progressBar setDoubleValue:0.0];
                        [progressBar setIndeterminate:NO];
                        [progressBar display];
                        
                        if ([self hasCanceledInstall:d]) break;
                        
                        [self updateArrayControllerWithDictionary:d forActionType:@"install"];
                        result = [self installSoftwareViaProxy:d];
                        
                        if (result == 0)
                        {
                            // Software has been installed, now flag for reboot
                            if ([[d valueForKeyPath:@"Software.reboot"] isEqualTo:@"1"]) {
                                _needsReboot++;
                            }
                            if ([[d valueForKeyPath:@"Software.auto_patch"] isEqualTo:@"1"]) {
                                
                                [progressBar setIndeterminate:YES];
                                [progressBar startAnimation:nil];
                                [progressBar display];
                                
                                [statusTextStatus setStringValue:@"Auto Patching is enabled, begin patching..."];
                                [statusTextStatus display];
                                
                                pResult = [self patchSoftwareViaProxy:d];
                                [NSThread sleepForTimeInterval:5];
                            }
                            
                            [statusTextStatus setStringValue:[NSString stringWithFormat:@"Installing %@ completed.",[d objectForKey:@"name"]]];
                            [statusTextStatus display];
                            
                            [self installSoftwareItem:d];
                            [self updateArrayControllerWithDictionary:d];
                        } else {
                            [self updateArrayControllerWithDictionary:d forActionType:@"error"];
                            [progressBar setDoubleValue:0.0]; // Clears the progress bar, timing issue does not clear it otherwise.
                        }
                        
                        [self postInstallResults:result resultText:@"" task:d];
                        [progressBar stopAnimation:nil];
                        dispatch_async(dispatch_get_main_queue(), ^(void){[progressBar display];});
                    }
                    
                    // Clean up downloaded software
                    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"enableRemoveSoftware"] == YES)
                    {
                        if ([fm fileExistsAtPath:swLoc] == YES)
                        {
                            NSError *rmErr = nil;
                            [fm removeItemAtPath:swLoc error:&rmErr];
                            if (rmErr) {
                                logit(lcl_vError,@"Error[%d], trying to remove downloaded software directory. %@.",(int)[dlErr code],swLoc);
                            }
                        }
                    }
                }
            }
        }
        [installButton setEnabled:YES];
        [refreshButton setEnabled:YES];
        [cancelButton setEnabled:NO];
        [swDistGroupsButton setEnabled:YES];
        [self setTableColEdit:YES];
        
        // Apps were installed that require a reboot
        if (_needsReboot >= 1) {
            [self showRebootPanel:nil];
        }
        
        [self.window setFrame:self.window.frame display:YES animate:YES];
    }
}

- (BOOL)installSoftwareItem:(NSDictionary *)dict
{
    NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
    NSMutableDictionary *installData = [[NSMutableDictionary alloc] init];
    [installData setObject:[NSDate date] forKey:@"installDate"];
    [installData setObject:[dict objectForKey:@"id"] forKey:@"id"];
    [installData setObject:[dict objectForKey:@"name"] forKey:@"name"];
    if ([dict objectForKey:@"sw_uninstall"]) {
        [installData setObject:[dict objectForKey:@"sw_uninstall"] forKey:@"sw_uninstall"];    
    } else {
        [installData setObject:@"" forKey:@"sw_uninstall"];
    }
    NSMutableArray *_data;
    if ([fm fileExistsAtPath:installFile]) {
        _data = [NSMutableArray arrayWithContentsOfFile:installFile];
    } else {
        if (![fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]]) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:NULL];
        }
        _data = [NSMutableArray array];
    }
    [_data addObject:installData];
    [_data writeToFile:installFile atomically:YES];

    return YES;
}

#pragma mark - Remove Software
- (IBAction)removeSoftware:(id)sender
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *d in [arrayController arrangedObjects]) {
        if ([d objectForKey:@"selected"] && [d objectForKey:@"installed"]) {
            if (([[d objectForKey:@"selected"] intValue] == 1) && ([[d objectForKey:@"installed"] intValue] == 1)) {
                [items addObject:[d objectForKey:@"name"]];
            }
        }
    }
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setMessageText:@"Remove Software?"];
    [alert setInformativeText:[NSString stringWithFormat:@"Are you sure you want to uninstall/remove the following item(s). \n %@",[items componentsJoinedByString:@","]]];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        // OK clicked, delete the record
        [self performSelectorInBackground:@selector(removeSoftwareThread) withObject:nil];
    }
    
    
}

- (void)removeSoftwareThread
{
    @autoreleasepool {
        [refreshButton setEnabled:NO];
        [swDistGroupsButton setEnabled:NO];
        [self setTableColEdit:NO];
        
        [progressBar setIndeterminate:YES];
        [progressBar startAnimation:nil];
        [progressBar display];
        
        int _result = 0;
        
        NSString *uninstallScriptEnc, *uninstallScript;
        NSDictionary *curTaskDict;
        for (NSDictionary *d in [arrayController arrangedObjects])
        {
            if ([d objectForKey:@"selected"] && [d objectForKey:@"installed"])
            {
                // This seams like a duplication of work, but updateArrayControllerWithDictionary
                // is clearing the pointer for d, and since I can not reatin it ...
                curTaskDict = [NSDictionary dictionaryWithDictionary:d];

                if (([[d objectForKey:@"selected"] intValue] == 1) && ([[d objectForKey:@"installed"] intValue] == 1))
                {
                    [statusTextStatus setStringValue:[NSString stringWithFormat:@"Uninstalling %@ ...",[d objectForKey:@"name"]]];
                    uninstallScriptEnc = [d valueForKeyPath:@"Software.sw_uninstall"];
                    if ([uninstallScriptEnc length] > 0) {
                        uninstallScript = [uninstallScriptEnc decodeBase64AsString];
                        logit(lcl_vDebug,@"Remove Script:\n%@",uninstallScript);
                        _result = [self removeSoftwareViaProxy:uninstallScript];   
                    }
                    
                    if (_result == 0) {
                        [self removeSoftwareInstallStatus:[d objectForKey:@"id"]];
                        [self updateArrayControllerWithDictionary:d forActionType:@"remove"];
                        [statusTextStatus setStringValue:[NSString stringWithFormat:@"Uninstall completed."]];
                    } else {
                        [self updateArrayControllerWithDictionary:d forActionType:@"error"];
                        [statusTextStatus setStringValue:[NSString stringWithFormat:@"Error uninstalling."]];
                    }
                    [self postUnInstallResults:_result resultText:@"" task:curTaskDict];
                }
            }
        }
        
        [progressBar stopAnimation:nil];
        [progressBar display];
        [refreshButton setEnabled:YES];
        [swDistGroupsButton setEnabled:YES];
        [self setTableColEdit:YES];
    }
}

#pragma mark MPDLWrapper Callbacks
- (void)appendDownloadProgress:(double)aNumber
{
	[progressBar setDoubleValue:aNumber];
    dispatch_async(dispatch_get_main_queue(), ^(void){[progressBar display];});
}

- (void)appendDownloadProgressPercent:(NSString *)aPercent
{
    logit(lcl_vDebug,@"%@",[NSString stringWithFormat:@"%@%@",aPercent,@"%"]);
}

- (void)downloadStarted
{
	[statusTextStatus setStringValue:@"Downloading..."];
}

- (void)downloadFinished
{
    [statusTextStatus setStringValue:@"Download Complete"];
	isDownloading = NO;
}

- (void)downloadError
{
	//[cancelButton setEnabled:YES];
    [statusTextStatus setStringValue:@"Download Error"];
	[progressBar setDoubleValue:0.0];
}

#pragma mark IBActions

- (IBAction)checkboxChanged:(id)sender
{
    [selectedItems removeAllObjects];
    
    int _selected = 0;
    int _installed = 0;
    int _emptyUninstall = 0;
    for (NSDictionary *d in [arrayController arrangedObjects]) {
        if ([d objectForKey:@"selected"]) {
            if ([[d objectForKey:@"selected"] intValue] == 1) {
                [selectedItems addObject:d];
                _selected++;
                
                if ([d objectForKey:@"installed"]) {
                    if ([[d objectForKey:@"installed"] intValue] == 1) {
                        _installed++;
                        _selected--;
                    }
                }
                
                if ([d valueForKeyPath:@"Software.sw_uninstall"]) {
                    if ([[d valueForKeyPath:@"Software.sw_uninstall"] length] <= 0) {
                        _emptyUninstall++;
                    }
                }
            }
        }
    }
    if ((_selected == 1 || _installed == 1) && (_selected + _installed) == 1 ) {
        [infoButton setEnabled:YES];
    } else {
        [infoButton setEnabled:NO];
    }
    
    if (_selected >= 1) {
        [installButton setEnabled:YES];
    } else {
        [installButton setEnabled:NO];
    }
    
    if (_installed >= 1) {
        [removeButton setEnabled:YES];
    } else {
        [removeButton setEnabled:NO];
    }
    
    if (_emptyUninstall >= 1) {
        [installButton setEnabled:YES];
        [removeButton setEnabled:NO];
    }
}

- (IBAction)refreshSoftware:(id)sender
{
    [NSThread detachNewThreadSelector:@selector(downloadSoftwareContent) toTarget:self withObject:nil];
}

- (IBAction)cancelSoftware:(id)sender
{
    [statusTextStatus setStringValue:@"Canceling software install task..."];
	[self setCancelInstalls:YES];
}

- (IBAction)getSoftwareDataFromFile:(id)sender
{
    NSArray *a = [NSKeyedUnarchiver unarchiveObjectWithFile:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]];
    
    if (a && [a count] > 0) {
		[arrayController removeObjects:[arrayController arrangedObjects]];
		[arrayController addObjects:a];	
        [tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
        [tableView performSelectorOnMainThread:@selector(display) withObject:nil waitUntilDone:YES];
	}
}

- (IBAction)refreshSoftwareDistGroups:(id)sender
{
    [self performSelectorInBackground:@selector(populateSoftwareGroupsPopupButton) withObject:nil];
}

#pragma mark Class Methods

- (IBAction)showMainLog:(id)sender
{
    [[NSWorkspace sharedWorkspace] openFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MPCatalog.log"] withApplication:@"Console"]; 
}

- (IBAction)showHelperLog:(id)sender
{
    [[NSWorkspace sharedWorkspace] openFile:@"/Library/MacPatch/Client/Logs/MPWorker.log" withApplication:@"Console"]; 
}

- (void)updateArrayControllerWithDictionary:(NSDictionary *)dict
{
    [self updateArrayControllerWithDictionary:dict forActionType:@"installed"];
}

- (void)updateArrayControllerWithDictionary:(NSDictionary *)dict forActionType:(NSString *)type
{
    NSString *curID = [dict objectForKey:@"id"];
    [arrayController.arrangedObjects enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
     {
         NSMutableDictionary *d = object;
         
         if ([[d objectForKey:@"id"] isEqualTo:curID])
         {
             if ([type isEqualToString:@"installed"] == YES) {
                 [d setObject:[NSNumber numberWithInt:1] forKey:@"installed"];
                 [d setObject:[NSNumber numberWithBool:NO] forKey:@"selected"];
             } else if ([type isEqualToString:@"remove"] == YES) {
                 [d setObject:[NSNumber numberWithInt:0] forKey:@"installed"];
                 [d setObject:[NSNumber numberWithBool:NO] forKey:@"selected"];
                 if ([dict hasKey:@"isReceipt"]) {
                     if ([[dict objectForKey:@"isReceipt"] isEqualToNumber:[NSNumber numberWithInt:1]]) {
                         [arrayController removeObjects:[NSArray arrayWithObject:d]];
                         *stop = YES;    // Stop enumerating
                         return;
                     }
                 }
             } else if ([type isEqualToString:@"install"] == YES) {
                 [d setObject:[NSNumber numberWithInt:2] forKey:@"installed"];
             } else if ([type isEqualToString:@"error"] == YES) {
                 [d setObject:[NSNumber numberWithInt:3] forKey:@"installed"];
             } else if ([type isEqualToString:@"download"] == YES) {
                 [d setObject:[NSNumber numberWithInt:4] forKey:@"installed"];
             } else {
                 [d setObject:[NSNumber numberWithInt:0] forKey:@"installed"];
             }

             dispatch_async(dispatch_get_main_queue(), ^(void){[tableView display];});
         }
     }];
}

- (void)removeSoftwareInstallStatus:(NSString *)swID
{
    NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
    
    NSMutableArray *_data = nil;
    if ([fm fileExistsAtPath:installFile]) {
        _data = [NSMutableArray arrayWithContentsOfFile:installFile];
    }
    
    if (!_data) {
        return;
    }
    
    for (int i = 0; [_data count]; i++) {
        if ([[[_data objectAtIndex:i] objectForKey:@"id"] isEqualToString:swID]) {
            [_data removeObjectAtIndex:i];
            break;
        }
    }
    
    [_data writeToFile:installFile atomically:YES];
}

- (void)downloadSoftwareContent
{
    @autoreleasepool
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressBar setHidden:NO];
            [progressBar setIndeterminate:YES];
            [progressBar startAnimation:self];
            [progressBar display];
        });
        
        [statusTextStatus setStringValue:@"Downloading Software Distribution Content..."];
        [NSThread sleepForTimeInterval:2];
        
        MPSWTasks *sw = [[MPSWTasks alloc] init];
        if ([swDistGroupsButton selectedItem])
        {
            [sw setGroupName:[[swDistGroupsButton selectedItem] title]];
            [self setSwDistCurrentTitle:[[swDistGroupsButton selectedItem] title]];
        }
        NSError *err = nil;
        NSArray *tasks = [sw getSoftwareTasksForGroup:&err];
        if (err) {
            [statusTextStatus setStringValue:err.localizedDescription];
            return;
        }

        window.title = [NSString stringWithFormat:@"MP - Software Catalog (%@)",[sw groupName]];
        
        if (err) {
            [statusTextStatus setStringValue:err.localizedDescription];
        } else {
            [self filterSoftwareContent:tasks];
            [statusTextStatus setStringValue:@"Done"];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressBar stopAnimation:nil];
        });
        [self checkAndInstallMandatoryApplications];
    }
}

- (void)filterSoftwareContent:(NSArray *)content
{
    NSArray *_a;
    int c = 0;
    NSMutableDictionary *d;
    NSDictionary *_SoftwareCriteria;
    NSMutableArray *_SoftwareArray = [[NSMutableArray alloc] init];
    NSMutableArray *_MandatorySoftware = [[NSMutableArray alloc] init];
    NSError *err = nil;
    if (content) {
        /* If there is content */
        BOOL isDir;
        BOOL dirExists = [fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path] isDirectory:&isDir];
        if (!dirExists) {
            [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:nil error:&err];
            if (err) {
               logit(lcl_vError,@"%@",[err localizedDescription]);
                return;
            }
        }
        
        [self writeArrayFileViaProxy:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"] data:content];
        _a = [NSKeyedUnarchiver unarchiveObjectWithFile:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]];
        for (id item in _a) 
        {
            d = [[NSMutableDictionary alloc] initWithDictionary:item];
            logit(lcl_vDebug,@"Checking %@",[d objectForKey:@"name"]);
            c = 0;
            MPOSCheck *mpos = [[MPOSCheck alloc] init];
            _SoftwareCriteria = [item objectForKey:@"SoftwareCriteria"];
            // OSArch
            if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
                logit(lcl_vDebug,@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
            } else {
                logit(lcl_vDebug,@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
                c++;
            }
            // OSType
            if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
                logit(lcl_vDebug,@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
            } else {
                logit(lcl_vDebug,@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
                c++;
            }
            // OSVersion
            if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
                logit(lcl_vDebug,@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
            } else {
                logit(lcl_vDebug,@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
                c++;
            }
            mpos = nil;
            // Did not pass the criteria check
            if (c >= 1) {
                continue;
            }
            // Check Start Date
            NSDate *now = [NSDate date];
            NSDate *startDate = [NSDate dateFromString:[d objectForKey:@"sw_start_datetime"]];
            NSDate *endDate = [NSDate dateFromString:[d objectForKey:@"sw_end_datetime"]];
            
            if ([now timeIntervalSince1970] < [startDate timeIntervalSince1970]) {
                // Software is not ready for deployment
                continue;
            }
            // Check for Mandatory apps
            BOOL isMandatory = NO;
            if ([now timeIntervalSince1970] >= [endDate timeIntervalSince1970]) {
                if ([[d objectForKey:@"sw_task_type"] containsString:@"m" ignoringCase:YES]) {
                    isMandatory = YES;
                }
            }
            
            // Check to see if it's installed
            NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
            if ([fm fileExistsAtPath:installFile]) {
                NSArray *a = [NSArray arrayWithContentsOfFile:installFile];
                for (int i = 0; i < [a count];i++) {
                    if ([[[a objectAtIndex:i] objectForKey:@"id"] isEqualTo:[item objectForKey:@"id"]]) {
                        [d setObject:[NSNumber numberWithInt:1] forKey:@"installed"];
                        isMandatory = NO; // It's installed ... no need to install
                    }
                }
            }
            
            // Has not been installed, and is mandatory
            if (isMandatory == YES) {
                logit(lcl_vInfo,@"Adding %@ to mandatory installs.",[d objectForKey:@"name"]);
                [_MandatorySoftware addObject:d];
            }
            
            // Populate install by date
            if ([[[d objectForKey:@"sw_task_type"] uppercaseString] containsString:@"m"]) {
                [d setObject:[d objectForKey:@"sw_end_datetime"] forKey:@"installBy"];
            }
            
            [_SoftwareArray addObject:d];
            d = nil;
        }
        
    } else {
        /* If there is no content, dosp[lay only installed items */
        _a = [NSKeyedUnarchiver unarchiveObjectWithFile:[[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]];
        if (_a) {
            
            for (id item in _a) 
            {
                d = [[NSMutableDictionary alloc] initWithDictionary:item];
                
                // Check to see if it's installed
                NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
                if ([fm fileExistsAtPath:installFile]) {
                    NSArray *a = [NSArray arrayWithContentsOfFile:installFile];
                    for (int i = 0; i < [a count];i++) {
                        if ([[[a objectAtIndex:i] objectForKey:@"id"] isEqualTo:[item objectForKey:@"id"]]) {
                            [d setObject:[NSNumber numberWithInt:1] forKey:@"installed"];
                            [d setObject:[NSNumber numberWithInt:1] forKey:@"isReceipt"];
                            // Populate install by date
                            if ([[[d objectForKey:@"sw_task_type"] uppercaseString] containsString:@"m"]) {
                                [d setObject:[d objectForKey:@"sw_end_datetime"] forKey:@"installBy"];
                            }
                            
                            [_SoftwareArray addObject:d];
                        }
                    }
                }
                
                d = nil;
            }
            
        }
    }
    
    logit(lcl_vInfo,@"Approved/Installed Software tasks: %@",_SoftwareArray);
    NSLog(@"%@",_SoftwareArray);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [arrayController removeObjects:[arrayController arrangedObjects]];
        if (_SoftwareArray && [_SoftwareArray count] > 0)
        {
			NSSortDescriptor *sortBy;
			sortBy = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
			NSArray *sortDescriptors = [NSArray arrayWithObject:sortBy];
			NSArray *sortedArray = [_SoftwareArray sortedArrayUsingDescriptors:sortDescriptors];
            [arrayController addObjects:sortedArray];
        }
    });
    
    [tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
    [tableView performSelectorOnMainThread:@selector(display) withObject:nil waitUntilDone:YES];
    
    if ([_MandatorySoftware count] >= 1) {
        logit(lcl_vDebug,@"Need to install mandatory apps");
    }
    
}

#pragma mark WebService methods
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
    @autoreleasepool {
        MPSWTasks *swt = [[MPSWTasks alloc] init];
        int result = -1;
        result = [swt postInstallResults:resultNo resultText:resultString task:taskDict];
    }
}

- (void)postUnInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
    @autoreleasepool {
        MPSWTasks *swt = [[MPSWTasks alloc] init];
        int result = -1;
        result = [swt postUnInstallResults:resultNo resultText:resultString task:taskDict];
    }
}

#pragma mark Misc
- (BOOL)hasCanceledInstall:(NSDictionary *)task
{
    if (cancelInstalls == YES) 
    {
        [cancelButton setEnabled:NO];
        [statusTextStatus setStringValue:@"Cancel Install Tasks"];
        logit(lcl_vInfo,@"Install task has been canceled");
        [self setCancelInstalls:NO];
        [self updateArrayControllerWithDictionary:task forActionType:@"cancel"];
        [progressBar setHidden:YES];
        [statusTextStatus setStringValue:@" "];
        return YES;
    }
    
    return NO;
}

#pragma mark - Proxy Methods
-(int)installSoftwareViaProxy:(NSDictionary *)aInstallDict
{
	int results = -1;
	
	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		} 
    }
	
	@try {
		results = [proxy installSoftwareViaHelper:aInstallDict];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [Custom Scan] error: %@", e);
    }
	
done:
	[self cleanup];
	return results;
}

- (int)patchSoftwareViaProxy:(NSDictionary *)aInstallDict
{
    int results = -1;
	
	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		} 
    }
	
	@try {
		results = [proxy patchSoftwareViaHelper:aInstallDict];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [Custom Scan] error: %@", e);
    }
	
done:
	[self cleanup];
	return results;
}

- (int)removeSoftwareViaProxy:(NSString *)removeScript
{
    int results = -1;
	
	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		} 
    }
	
	@try {
		results = [proxy removeSoftwareViaHelper:removeScript];
        // Quick fix, script result is a bool
        if (results == 1) {
            results = 0;
        } else {
            results = 1;
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [Remove Software] error: %@", e);
    }
	
done:
	[self cleanup];
	return results;
}

- (void)setLoggingState:(BOOL)aState
{
	if (!proxy) 
    {
        [self connect];
    }
    
	if (proxy) 
    {
        @try 
        {
            [proxy setLoggingLevel:aState];
        }
        @catch (NSException *e) {
            logit(lcl_vError,@"Trying to set the logging level, %@", e);
        }
    }
    
    [self cleanup];
	return;
}

- (int)writeToFileViaProxy:(NSString *)aFile data:(id)data
{
    int results = -1;
	
	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		}
    }
	
	@try {
		results = [proxy writeDataToFileViaHelper:data toFile:aFile];
        // Quick fix, script result is a bool
        if (results == 1) {
            results = 0;
        } else {
            results = 1;
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [writeDataToFileViaHelper] error: %@", e);
    }
	
done:
	[self cleanup];
	return results;
}

- (int)writeArrayFileViaProxy:(NSString *)aFile data:(NSArray *)data
{
    int results = -1;
	
	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		}
    }
	
	@try {
		results = [proxy writeArrayToFileViaHelper:data toFile:aFile];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"writeArrayToFileViaHelper error: %@", e);
    }
	
done:
	[self cleanup];
	return results;
}

- (BOOL)removeDirectoryViaProxy:(NSString *)aDirectory
{
	BOOL result = NO;
	
	if (!proxy) {
		[self connect];
		if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		}
	}
	
	@try {
		result = [proxy removeStagedDirectory:aDirectory];
	}
	@catch (NSException *e) {
		logit(lcl_vError,@"removeDirectory error: %@", e);
	}
	
done:
	[self cleanup];
	return result;
}

#pragma mark -
#pragma mark MPWorker

- (void)connect 
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
	
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
	
    @try {
        proxy = [connection rootProxy];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(connectionDown:)
													 name:NSConnectionDidDieNotification
												   object:connection];
		
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful = [proxy registerClient:self];
        if (!successful) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                             defaultButton:@"OK" alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
            
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [alert runModal];
            [self cleanup];
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
}

- (void)cleanup
{
    if (proxy) 
    {
        NSConnection *connection = [proxy connectionForProxy];
        [connection invalidate];
        proxy = nil;
    }
	
}

- (void)connectionDown:(NSNotification *)notification 
{
    logit(lcl_vInfo,@"helperd connection down");
    [self cleanup];
} 

#pragma mark Client Callbacks
- (void)statusData:(in bycopy NSString *)aData
{
    [statusTextStatus setStringValue:aData];
}

- (void)installData:(in bycopy NSString *)aData
{
    NSString *strTxt;
    strTxt = [aData replaceAll:@"installer:STATUS:" replaceString:@""];
    strTxt = [strTxt replaceAll:@"installer:PHASE:" replaceString:@""];
    if ([aData containsString:@"installer:"]) {
        if ([strTxt containsString:@"installer:%"]) {
            [progressBar setDoubleValue:[[[[strTxt replaceAll:@"installer:%" replaceString:@""] componentsSeparatedByString:@"."] objectAtIndex:0] floatValue]];
        } else {
            [statusTextStatus setStringValue:strTxt];
        }
    }
}

@end
