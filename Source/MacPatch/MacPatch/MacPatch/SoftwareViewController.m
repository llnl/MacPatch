//
//  SoftwareViewController.m
//  MPPortal
//
//  Created by Heizer, Charles on 12/13/12.
//  Copyright (c) 2012 LLNL. All rights reserved.
//

#import "SoftwareViewController.h"
#import "SWInstallItem.h"
#import "SoftwareCellView.h"
#import "MacPatch.h"

#import <WebKit/WebKit.h>

#define MP_INSTALLED_DATA       @".installed.plist"

@interface SoftwareViewController ()
{
    NSUserDefaults  	*defaults;
	MPSettings 			*settings;
	NSFileManager		*fm;
	NSOperationQueue 	*aQueue;
}

- (void)refreshInstalledItems;
- (BOOL)parseSoftwareItems:(id)jsonData;

// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@property (nonatomic, weak) NSString *ignoreRow;

// Private
@property (nonatomic, strong) NSURL *SOFTWARE_DATA_DIR;

// WebView
@property (strong, nonatomic) IBOutlet NSProgressIndicator *webSpinner;
@property (strong, nonatomic) IBOutlet NSWindow *webWindow;
@property (strong, nonatomic) IBOutlet WKWebView *webView;
@property (strong, nonatomic) NSString *productURL;

@end

@implementation SoftwareViewController

@synthesize tableView = _tableView;
@synthesize swTasks;
@synthesize filteredSwTasks;
@synthesize installedItems;
@synthesize SOFTWARE_DATA_DIR;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:@"SoftwareViewController" bundle:nil];
    if (self)
	{
        // Initialization code here.
		settings		= [MPSettings sharedInstance];
        swTasks 		= [[NSMutableArray alloc] init];
        filteredSwTasks = [[NSMutableArray alloc] init];
        defaults 		= [NSUserDefaults standardUserDefaults];
		fm 				= [NSFileManager defaultManager];
		
		if (![defaults objectForKey:@"SWGroupSelected"])
		{
			[defaults setObject:@"Default" forKey:@"SWGroupSelected"];
			[defaults synchronize];
		}
		
		[self setupSWDataDir];		
    }
	
    [self setTitle:@"Software"];
    return self;
}

- (void)viewDidLoad
{
	[self.view setWantsLayer:YES];
	[self loadBannerView:nil];
	
	[settings refresh];
	[self setupNotification];

	[self populateSoftwareGroupsPopupButton:nil];
	[self getInstalledSoftwareTasks];
}

- (IBAction)loadBannerView:(id)sender
{
	qlinfo(@"loadBannerView");
	[_wkWebView.enclosingScrollView setHasVerticalScroller:NO];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"banner" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	[_wkWebView loadHTMLString:htmlStringBase baseURL:[[NSBundle mainBundle] resourceURL]];
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
    //assert([NSThread isMainThread]);
    if (self.workerConnection == nil)
	{
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
    //assert([NSThread isMainThread]);
    
    // Ensure that there's a helper tool connection in place.
    self.workerConnection = nil;
    [self connectToHelperTool];

	if (![self verifyServiceVersion]) {
		NSError *workerErr = [NSError errorWithDomain:@"WorkerConnectionError"
												 code:-9999
											 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"MP Helper Connection Failed.", nil),
														NSLocalizedFailureReasonErrorKey: @"Could not reach the MacPatch helper application.",
														NSLocalizedRecoverySuggestionErrorKey: @"Verify if gov.llnl.mp.helper is running."}];
		commandBlock(workerErr);
	}
    commandBlock(nil);
}

- (BOOL)verifyServiceVersion
{
	__block BOOL hasConnection = NO;

	[[self.workerConnection synchronousRemoteObjectProxyWithErrorHandler:^(NSError * proxyError)
	  {
		  //err msg
		  qlerror(@"Failed to execute XPC service verification (error: %@)",  proxyError);
		  
	  }] getVersionWithReply:^(NSString *verData) {
		 //dbg msg
		 qldebug(@"Got Version: %@",verData);

		 if ([verData isEqualToString:@"1"]) {
			 hasConnection = YES;
		 }
	 }];
	
	
	if (!hasConnection)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"MacPatch Helper Verification"];
		[alert setInformativeText:@"This application requires a helper application to perform certain actions. The helper applciation can not be verified. MacPatch may not work as expected."];
		[alert addButtonWithTitle:@"OK"];
		[alert setAlertStyle:NSAlertStyleCritical];
		[alert runModal];
	}
	
	return hasConnection;
}

#pragma mark - Main

// GOOD
/**
 Refresh Will re-load all of the catalog items via API call to Web service to
 get all software tasks for the selected catalog.
 */
- (IBAction)refresh:(id)sender
{
	[self loadCatalogItems];
}

// GOOD
/**
 populateSoftwareGroupsPopupButton will query Webservice API to get all of the
 software catalogs and will load the catalog items for the selected catalog.
 */
- (IBAction)populateSoftwareGroupsPopupButton:(id)sender
{
	MBProgressHUD *hud = [[MBProgressHUD alloc] initWithView:self.view];
	[self.view addSubview:hud];

	[hud showAnimated:YES whileExecutingBlock:^{
		hud.labelText = @"Loading Catalogs...";
		
		NSError *error = nil;
		NSArray *catalogs = [NSArray array];
		MPRESTfull *rest = [[MPRESTfull alloc] init];
		catalogs = [rest getSoftwareCatalogs:&error];
		
		if (error) {
			qlerror(@"%@",error.localizedDescription);
			[self->_swDistGroupsButton addItemWithTitle:self->settings.agent.swDistGroup];
			return;
		}
		
		if ([catalogs count] > 0)
		{
			NSMutableSet *titles = [NSMutableSet new];
			for (NSDictionary *n in catalogs) {
				[titles addObject:n[@"Name"]];
			}
			
			NSArray *sorted = [[titles allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self->_swDistGroupsButton addItemsWithTitles:sorted];
			});
			
			if (self->settings.agent.swDistGroup != nil) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[self->_swDistGroupsButton selectItemAtIndex:[[self->_swDistGroupsButton itemTitles] indexOfObject:self->settings.agent.swDistGroup]];
				});
			} else {
				dispatch_async(dispatch_get_main_queue(), ^{
					[self->_swDistGroupsButton selectItemAtIndex:0];
				});
			}
			
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self->_swDistGroupsButton addItemWithTitle:self->settings.agent.swDistGroup];
			});
		}
		
	} completionBlock:^{
		[hud removeFromSuperview];
		// Set the catalog popup button and load content for the catalog selected
		if ([self->defaults objectForKey:@"SWGroupSelected"])
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self->_swDistGroupsButton selectItemWithTitle:[self->defaults objectForKey:@"SWGroupSelected"]];
			});
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self->_swDistGroupsButton selectItemWithTitle:@"Default"];
			});
		}
		[self loadCatalogItems];
	}];
}

// GOOD
/**
 changeSoftwareGroup will change the catalog group and load all catalog items
 by calling self.loadCatalogItems
 */
- (IBAction)changeSoftwareGroup:(id)sender
{
	[defaults setValue:[sender title] forKey:@"SWGroupSelected"];
	[defaults synchronize];
	[self getInstalledSoftwareTasks];
	[self loadCatalogItems];
}

// GOOD
/**
 Loads catalog items from web service API
 
 - Will send a notification to install mandatory software tasks
 */
- (void)loadCatalogItems
{
	MBProgressHUD *hud = [[MBProgressHUD alloc] initWithView:self.view];
	[self.view addSubview:hud];
	
	[hud showAnimated:YES whileExecutingBlock:^{
		hud.labelText = @"Loading Catalog Items...";
		
		MPSWTasks *sw = [[MPSWTasks alloc] init];
		[sw setGroupName:[self->defaults objectForKey:@"SWGroupSelected"]];
		NSError *err = nil;
		NSArray *tasks = [sw getSoftwareTasksForGroup:&err];
		if (err) {
			dispatch_async(dispatch_get_main_queue(), ^{
				qlerror(@"%@",err.localizedDescription);
				self->_swNetworkStatusImage.hidden = NO;
				[self->_swNetworkStatusText setStringValue:err.localizedDescription];
			});
			return;
		} else {
			[self->swTasks removeAllObjects];
			[self->swTasks addObjectsFromArray:[self filterSoftwareTasks:tasks]];
			//[self filterSoftwareTasks:tasks];
		}
		
		// Send Notification for Mandatory Installs
		//[self checkAndInstallMandatoryApplications];
		
	} completionBlock:^{
		[hud removeFromSuperview];
	}];
}

- (void)refreshInstalledItems
{
    //[self setInstalledItems:[db getAllSoftwareRecords]];
}

- (void)getInstalledSoftwareTasks
{
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"%@",connectError.localizedDescription);
			dispatch_semaphore_signal(sem);
		} else {
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"%@",proxyError.localizedDescription);
				dispatch_semaphore_signal(sem);
			}] retrieveInstalledSoftwareTasksWithReply:^(NSData *result) {
				NSArray *tasks = [NSKeyedUnarchiver unarchiveObjectWithData:result];
				[self setInstalledItems:tasks];
				dispatch_semaphore_signal(sem);
			}];
		}
	}];
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

// GOOD
- (NSArray *)filterSoftwareTasks:(NSArray *)swTasks
{
	NSArray *_a;
	int c = 0;
	NSMutableDictionary *d;
	NSDictionary *_SoftwareCriteria;
	NSMutableArray *_SoftwareArray = [[NSMutableArray alloc] init];
	NSMutableArray *_MandatorySoftware = [[NSMutableArray alloc] init];
	NSError *err = nil;
	if (swTasks)
	{
		/* If there is content */
		BOOL isDir;
		BOOL dirExists = [fm fileExistsAtPath:[SOFTWARE_DATA_DIR path] isDirectory:&isDir];
		if (!dirExists) {
			[fm createDirectoryAtPath:[SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:nil error:&err];
			if (err) {
				qlerror(@"%@",[err localizedDescription]);
				return [NSArray array];
			}
		}
		
		for (id item in swTasks)
		{
			d = [[NSMutableDictionary alloc] initWithDictionary:item];
			qldebug(@"------------------------------------------------");
			qldebug(@"Checking %@",[d objectForKey:@"name"]);
			c = 0;
			MPOSCheck *mpos = [[MPOSCheck alloc] init];
			_SoftwareCriteria = [item objectForKey:@"SoftwareCriteria"];
			// OSArch
			if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
				qldebug(@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
			} else {
				qldebug(@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
				c++;
			}
			// OSType
			if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
				qldebug(@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
			} else {
				qldebug(@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
				c++;
			}
			// OSVersion
			if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
				qldebug(@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
			} else {
				qldebug(@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
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
				qlerror(@"Failed start date. Needs to be greater than %@",startDate);
				continue;
			}
			// Check for Mandatory apps
			BOOL isMandatory = NO;
			if ([now timeIntervalSince1970] >= [endDate timeIntervalSince1970])
			{
				if ([d[@"sw_task_type"] containsString:@"m" ignoringCase:YES]) {
					isMandatory = YES;
				}
			}
			
			// Check to see if it's installed
			NSString *installFile = [[SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
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
				qlinfo(@"Adding %@ to mandatory installs.",[d objectForKey:@"name"]);
				[_MandatorySoftware addObject:d];
			}
			
			// Populate install by date
			if ([[[d objectForKey:@"sw_task_type"] uppercaseString] containsString:@"m"]) {
				[d setObject:[d objectForKey:@"sw_end_datetime"] forKey:@"installBy"];
			}
			
			[_SoftwareArray addObject:d];
			d = nil;
		}
		
	}
	else
	{
		/* If there is no content, display only installed items */
		qlinfo(@"no content");
		if ([fm fileExistsAtPath:[[SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]])
		{
			_a = [NSKeyedUnarchiver unarchiveObjectWithFile:[[SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"content.plist"]];
			if (_a)
			{
				for (id item in _a)
				{
					d = [[NSMutableDictionary alloc] initWithDictionary:item];
					
					// Check to see if it's installed
					NSString *installFile = [[SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:MP_INSTALLED_DATA];
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
	}

	qlinfo(@"Approved Software tasks:");
	for (NSDictionary *s in _SoftwareArray)
	{
		qlinfo(@"- %@",s[@"name"]);
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		[self->filteredSwTasks removeAllObjects];
		if (_SoftwareArray && [_SoftwareArray count] > 0)
		{
			NSSortDescriptor *sortBy;
			sortBy = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
			NSArray *sortDescriptors = [NSArray arrayWithObject:sortBy];
			NSArray *sortedArray = [_SoftwareArray sortedArrayUsingDescriptors:sortDescriptors];
			[self->filteredSwTasks addObjectsFromArray:[sortedArray mutableCopy]];
		}
		[self->_tableView reloadData];
		[self->_tableView display];
	});
	
	if ([_MandatorySoftware count] >= 1) {
		qlinfo(@"Need to install mandatory apps");
	}
	
	return [_SoftwareArray copy];
}

- (BOOL)parseSoftwareItems:(NSDictionary *)swItems
{
    NSArray *jsonResult = nil;

    @try {
        jsonResult = [swItems objectForKey:@"Tasks"];
        
        // For Testing
        [jsonResult writeToFile:@"/tmp/software.plist" atomically:NO];
        
        [swTasks removeAllObjects];
        [filteredSwTasks removeAllObjects];
        
        for (NSDictionary *d in jsonResult)
        {
            NSMutableDictionary *s = [[NSMutableDictionary alloc] init];
            [s addEntriesFromDictionary:d];
            [s setObject:[NSNumber numberWithInt:0] forKey:@"installed"];
            for (SWInstallItem *si in installedItems)
            {
                if ([si.swuuid isEqualTo:[d objectForKey:@"id"]])
                {
                    [s setObject:[NSNumber numberWithInt:1] forKey:@"installed"];
                    break;
                }
            }
            [swTasks addObject:s];
        }
        
        [filteredSwTasks addObjectsFromArray:swTasks];
        dispatch_async(dispatch_get_main_queue(), ^{
			[self->_tableView reloadData];
        });
    }
    @catch (NSException *exception)
    {
        qlerror(@"%@",exception);
        return NO;
    }
    return YES;
}

- (IBAction)testButton:(id)sender
{
	MBProgressHUD *hud = [[MBProgressHUD alloc] initWithView:self.view];
	[self.view addSubview:hud];
	hud.labelText = @"Test Helper...";
	[hud show:YES];
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"%@",connectError);
			[NSThread sleepForTimeInterval:3.0];
			dispatch_async(dispatch_get_main_queue(), ^{
				[hud removeFromSuperview];
			});
		} else {
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				[NSThread sleepForTimeInterval:3.0];
				dispatch_async(dispatch_get_main_queue(), ^{
					[hud removeFromSuperview];
				});
			}] getTestWithReply:^(NSString *aString) {
				[NSThread sleepForTimeInterval:3.0];
				dispatch_async(dispatch_get_main_queue(), ^{
					[hud removeFromSuperview];
				});
			}];
		}
	}];
}

#pragma mark - Notifications
// Setup User Notification for Software Install Operation
- (void)setupNotification
{
	[[NSNotificationCenter defaultCenter] addObserverForName:kRefreshSoftwareTable object:nil queue:nil usingBlock:^(NSNotification *note)
	 {
		 [self getInstalledSoftwareTasks];
		 //NSDictionary *userInfo = note.userInfo;
		 dispatch_async(dispatch_get_main_queue(), ^{
			 [self->_tableView reloadData];
			 [self->_tableView display];
		 });
	 }];
}

#pragma mark - XPC Methods

- (void)workerStatusText:(NSString *)aStatus
{
    _swNetworkStatusText.stringValue = aStatus;
}

#pragma mark - TableView
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [filteredSwTasks count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary *sw = filteredSwTasks[row];
    
    NSString *identifier = [tableColumn identifier];
    if ([identifier isEqualToString:@"MainCell"])
    {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *appSupportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
        NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch/SW_Data"];
        
		NSString *appImage = sw[@"image"]?:@"AppStore";

        SoftwareCellView *cellView = [tableView makeViewWithIdentifier:@"MainCell" owner:self];
        cellView.mp_SOFTWARE_DATA_DIR = appSupportMPDir;
        cellView.rowData = [sw copy];
		cellView.actionButton.title = @"Install";
		[cellView.actionButton setState:0];
		[cellView.errorImage setImage:[NSImage imageNamed:@"EmptyImage"]];
		
		if (![sw[@"Software"][@"sw_img_path"] isEqualToString:@"None"]) {
			MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
			NSString *imgURL = sw[@"Software"][@"sw_img_path"];
			if (imgURL.length > 2)
			{
				NSData *imgData = [req dataForURLPath:[NSString stringWithFormat:@"/mp-content%@",imgURL.urlEncode]];
				if (imgData) {
					NSImage *image = [[NSImage alloc] initWithData:imgData];
					[cellView.swIcon setImage:image];
				} else {
					[cellView.swIcon setImage:[NSImage imageNamed:appImage]];
				}
			}
		} else {
			[cellView.swIcon setImage:[NSImage imageNamed:appImage]];
		}
		
        
        [cellView.swTitle setStringValue:sw[@"name"]];
		[cellView.swCompany setStringValue:@""];
		[cellView.swCompany setStringValue:[NSString stringWithFormat:@"%@",sw[@"Software"][@"vendor"]]];
        [cellView.swVersion setStringValue:[NSString stringWithFormat:@"Version %@",sw[@"Software"][@"version"]]];
		
		long lSize = ([sw[@"Software"][@"sw_size"] longLongValue] * 1000);
		NSString *xSize = [NSByteCountFormatter stringFromByteCount:lSize countStyle:NSByteCountFormatterCountStyleFile];
		[cellView.swSize setStringValue:[NSString stringWithFormat:@"Size: %@",xSize]];
		[cellView.swDescription setStringValue:@""];
        [cellView.swDescription setStringValue:sw[@"Software"][@"description"]];
        
        if ([sw[@"sw_task_type"] isEqualToString:@"om"]) {
            NSString *istBy = [NSString stringWithFormat:@"Install by: %@",sw[@"sw_end_datetime"]];
            [cellView.swInstallBy setStringValue:istBy];
        } else {
            [cellView.swInstallBy setStringValue:@""];
        }
        if (sw[@"reboot"] == 0) {
            [cellView.swRebootTextFlag setStringValue:@""];
            [cellView.installedStateImage setImage:[NSImage imageNamed:@"EmptyImage"]];
        } else {
            [cellView.swRebootTextFlag setStringValue:@"Reboot Required"];
            [cellView.installedStateImage setImage:[NSImage imageNamed:@"RebootImage"]];
        }
		
		cellView.isAppInstalled = NO;
		
		for (NSString *_tid in installedItems) {
			if ([_tid isEqualToString:sw[@"id"]])
			{
				cellView.isAppInstalled = YES;
				break;
			}
		}
		
        return cellView;
    }
    return nil;
}

#pragma mark - Search
- (IBAction)searchString:(id)sender
{
    //NSLog(@"%@",[_searchField stringValue]);
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    if ([[_searchField stringValue] length] <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->filteredSwTasks removeAllObjects];
            [self->filteredSwTasks addObjectsFromArray:self->swTasks];
            [self->_tableView reloadData];
        });
        return;
    }
    
    NSMutableArray *preds = [NSMutableArray array];
    [preds addObject:[NSPredicate predicateWithFormat:@"%K CONTAINS[c] %@",@"name",[_searchField stringValue]]];
    [preds addObject:[NSPredicate predicateWithFormat:@"%K CONTAINS[c] %@",@"Software.vendor",[_searchField stringValue]]];
    [preds addObject:[NSPredicate predicateWithFormat:@"%K CONTAINS[c] %@",@"Software.description",[_searchField stringValue]]];
    
    NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:preds];
    NSArray *aNames = [swTasks filteredArrayUsingPredicate:predicate];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->filteredSwTasks removeAllObjects];
        [self->filteredSwTasks addObjectsFromArray:aNames];
        [self->_tableView reloadData];
    });
}

#pragma mark - Progress Methods
- (void)startWheel
{
    _swNetworkStatusText.stringValue = @"";
    [_swNetworkStatusImage setHidden:YES];
    [_swProgressWheel setHidden:NO];
    [_swProgressWheel startAnimation:nil];
}

- (void)stopWheel
{
    [_swProgressWheel stopAnimation:nil];
    [_swProgressWheel setHidden:YES];
    [_swNetworkStatusImage setHidden:YES];
}

#pragma mark - Private

- (void)setupSWDataDir
{
	// Set Data Directory
	NSURL *appSupportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
	NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch"];
	[self setSOFTWARE_DATA_DIR:[appSupportMPDir URLByAppendingPathComponent:@"SW_Data"]];
	if ([fm fileExistsAtPath:[SOFTWARE_DATA_DIR path]] == NO) {
		NSError *err = nil;
		NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
		[fm createDirectoryAtPath:[SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:&err];
		if (err) {
			qlerror(@"%@",[err description]);
		}
	}
	if ([fm fileExistsAtPath:[[SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] path]] == NO) {
		NSError *err = nil;
		NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
		[fm createDirectoryAtPath:[[SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] path] withIntermediateDirectories:YES attributes:attributes error:&err];
		if (err) {
			qlerror(@"%@",[err description]);
		}
		[[SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsHiddenKey error:NULL];
	}
}

#pragma mark - HUD Views

#pragma mark MBProgressHUDDelegate methods

- (void)hudWasHidden:(MBProgressHUD *)hud
{
	// Remove HUD from screen when the HUD was hidded
	[HUD removeFromSuperview];
	HUD = nil;
}

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
	
}

#pragma mark - Web URL Info

- (void)showSoftwareInfoURLWithTitle:(NSString *)windowTitle url:(NSString *)url;
{
	[_webSpinner startAnimation:nil];
	[_webView.window setTitle:windowTitle];
	[_webWindow makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
	NSURL *nsurl=[NSURL URLWithString:url];
	NSURLRequest *nsrequest=[NSURLRequest requestWithURL:nsurl];
	[self.webView setHidden:YES];
	[self.webView loadRequest:nsrequest];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
	//NSLog(@"didCommitNavigation");
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	if (navigationAction.navigationType == WKNavigationTypeLinkActivated)
	{
		[[NSWorkspace sharedWorkspace] openURL:[navigationAction.request URL]];
		decisionHandler(WKNavigationActionPolicyCancel);
	}
	
	decisionHandler(WKNavigationActionPolicyAllow);
}

@end
