//
//  Survey.m
//  MPClientStatus
//
//  Created by Charles Heizer on 12/1/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import "Survey.h"
#import <WebKit/WebKit.h>

@interface WKWebView(SynchronousEvaluateJavaScript)
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;
@end

@implementation WKWebView(SynchronousEvaluateJavaScript)

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script
{
    __block NSString *resultString = nil;
    __block BOOL finished = NO;

    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error == nil) {
            if (result != nil) {
                resultString = [NSString stringWithFormat:@"%@", result];
            }
        } else {
            qlerror(@"evaluateJavaScript error : %@", error.localizedDescription);
        }
        finished = YES;
    }];

    while (!finished)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    return resultString;
}
@end

@interface Survey ()
{
    NSFileManager *fm;
    NSTextField *textFieldStatus;
    NSTextField *textFieldStatusBanner;
    NSProgressIndicator *progressWheelMain;
}

@property (strong) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTabView *tabBar;
@property (weak) IBOutlet NSButton *stepperButton;
@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSTextView *softwareTextView;
@property (weak) IBOutlet NSProgressIndicator *progressBar;
@property (weak) IBOutlet NSProgressIndicator *progressWheel;
@property (weak) IBOutlet NSTextField *progressStatus;
@property (weak) NSString *selectedTabViewItem;
@property (weak) NSString *swGroup;
@property (strong) NSArray *swForGroup;
@property (strong) NSDictionary *provisionData;
@property (strong) NSDictionary *provisionFileData;

@property (strong, nonatomic) NSWindow *backwindow;
@property (weak) IBOutlet NSButton *closeWindowButton;

// Helper
// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation Survey

@dynamic window;

- (void)windowDidLoad
{
    [super windowDidLoad];
    fm = [NSFileManager defaultManager];
    BOOL backgroundOn = YES;
    
    if (backgroundOn)
    {
        NSRect screenFrame = [[NSScreen mainScreen] frame]; // Get Full Screen
        self.backwindow  = [[NSWindow alloc] initWithContentRect:screenFrame styleMask:NSBorderlessWindowMask
                                                         backing:NSBackingStoreBuffered defer:NO];
        //[self.backwindow setOpaque:NO];
        [self.backwindow setBackgroundColor:[[NSColor darkGrayColor] colorWithAlphaComponent:0.5]];
        [self.backwindow setLevel:NSStatusWindowLevel];
        [self.backwindow makeKeyAndOrderFront:NSApp];
    }
    
    /* All Provisioning
    //_provisionFileData = [self readProvisioningFile];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    
    [_stepperButton setTitle:@"Begin"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_stepperButton setEnabled:NO]; // Diable Begin button ... initial required sw should be small
    });
    
    NSError *err = nil;
    NSData *data = [NSData dataWithContentsOfFile:MP_PROVISION_UI_FILE];
    NSDictionary *jdata = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&err];
    if (err) {
        qlerror(@"MP_PROVISION_UI_FILE contents are null. Unable to provision this system.");
        qlerror(@"%@",err.localizedDescription);
        _provisionData = nil;
        [self.window close];
    } else {
        _provisionData = [jdata copy];
    }
    
    _tabBar.delegate = self;
    [_tabBar selectLastTabViewItem:NULL];
    [_tabBar selectTabViewItemAtIndex:0];
    
    _swGroup = @"Default";
    if (_provisionData[@"softwareGroup"]) {
        _swGroup = _provisionData[@"softwareGroup"];
        qlinfo(@"Setting optional install group to %@",_swGroup);
    }
    
    [self performSelectorInBackground:@selector(getSoftwareForGroup:) withObject:_swGroup];
    [self performSelectorInBackground:@selector(runProvisionHostThread) withObject:nil];
    */
}

// Close the Grey (Transparent) Full Screen Bacround Window
- (IBAction)closeBackground:(NSButton *)sender
{
    [self.backwindow orderOut:self];
}

// Close the provisioning window, will only work on first tab.
- (IBAction)closeWindow:(NSButton *)sender
{
    [self.backwindow orderOut:self];
    [self.window orderOut:self];
}

#pragma mark - Tab Delegates

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    self.selectedTabViewItem = tabViewItem.identifier;
    
    NSString *htmlString;
    if (_provisionData) {
        htmlString = [self htmlForTab:[tabViewItem.identifier intValue] data:_provisionData[@"tabs"]];
    } else {
        htmlString = [self htmlForFile:@"blank"];
    }
    
    if ([tabViewItem.identifier isEqualToString:@"0"])
    {
        [_welcomeWebView setValue:@(YES) forKey:@"drawsTransparentBackground"];
    }
    else if ([tabViewItem.identifier isEqualToString:@"1"])
    {
        [_collectionWebView setValue:@(YES) forKey:@"drawsTransparentBackground"];
        [_collectionWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
        
    }
    else if ([tabViewItem.identifier isEqualToString:@"2"])
    {
        [_installWebView setValue:@(YES) forKey:@"drawsTransparentBackground"];
        [_installWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
        
    }
    else if ([tabViewItem.identifier isEqualToString:@"3"])
    {
        [_finishWebView setValue:@(YES) forKey:@"drawsTransparentBackground"];
        [_finishWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
        
    }
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSString *htmlString;
    
    if (_provisionData) {
        htmlString = [self htmlForTab:[tabViewItem.identifier intValue] data:_provisionData[@"tabs"]];
    } else {
        htmlString = [self htmlForFile:@"blank"];
    }
    
    if ([tabViewItem.identifier isEqualToString:@"0"])
    {
        _welcomeWebView.allowsBackForwardNavigationGestures = NO;
        [_welcomeWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
        [_stepperButton setTitle:@"Begin"];
    }
    else if ([tabViewItem.identifier isEqualToString:@"1"])
    {
        _collectionWebView.allowsBackForwardNavigationGestures = NO;
        [_stepperButton setTitle:@"Continue"];
        [_closeWindowButton setEnabled:NO];
    }
    else if ([tabViewItem.identifier isEqualToString:@"2"])
    {
        NSString *text = [self textForTab:[tabViewItem.identifier intValue] data:_provisionData[@"tabs"]];
        
        // Calc size and count
        /*
        NSInteger swCount = 0;
        NSInteger swSize = 0;
        for (NSDictionary *s in _swForGroup) {
            swCount++;
            swSize = swSize + [[s valueForKeyPath:@"Software.sw_size"] integerValue];
        }
        long lSize = (swSize * 1000);
        NSString *swSizeTXT = [NSByteCountFormatter stringFromByteCount:lSize countStyle:NSByteCountFormatterCountStyleFile];
        
        text = [text replace:@"[SIZE]" replaceString:swSizeTXT];
        text = [text replace:@"[COUNT]" replaceString:[@(swCount) stringValue]];
        [self writeSoftwareView:text];
        
        for (NSDictionary *s in _swForGroup) {
            [self writeSoftwareView:[NSString stringWithFormat:@"- %@",s[@"name"]]];
        }
        */
        [_skipButton setHidden:NO];
        [_stepperButton setTitle:@"Install"];
    }
    else if ([tabViewItem.identifier isEqualToString:@"3"])
    {
        /*
        // Check to see if the process needs to run any final scripts.
        if (!_provisionFileData) _provisionFileData = [self readProvisioningFile];
        NSData *archiveData = _provisionFileData[@"data"];
        NSDictionary *pData = [NSKeyedUnarchiver unarchiveObjectWithData:archiveData];
        // Unarchive the data object and locate the scriptsFinish key, then see if the array
        // has anything in it.
        if (pData[@"scriptsFinish"]) {
            if([pData[@"scriptsFinish"] count] >= 1) {
                NSArray *scripts = pData[@"scriptsFinish"];
                // Sort Array by order ascending
                NSSortDescriptor *orderDescriptor = [[NSSortDescriptor alloc] initWithKey:@"order" ascending:YES];
                scripts = [scripts sortedArrayUsingDescriptors:[NSArray arrayWithObject:orderDescriptor]];
                for (NSDictionary *script in scripts)
                {
                    if ([script[@"active"] intValue] == 1) {
                        if ([self runScript:script[@"script"]] != 0) {
                            qlerror(@"Error running script, sid is %@", script[@"sid"]);
                        }
                    }
                }
            }
        }
        */
        _finishWebView.allowsBackForwardNavigationGestures = NO;
        [_stepperButton setEnabled:YES];
        [_stepperButton setTitle:@"Finished"];
        if (_provisionData[@"mandatoryReboot"]) {
            if ([_provisionData[@"mandatoryReboot"] intValue] == 1) {
                [_stepperButton setTitle:@"Reboot"];
            }
        }
        [_skipButton setHidden:YES];
    }
}

- (int)runScript:(NSString *)script
{
    qlinfo(@"Begin running script");
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSInteger res = 99;
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
            dispatch_semaphore_signal(sem);
        } else {
            [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
                dispatch_semaphore_signal(sem);
            }] runScriptFromString:script withReply:^(NSError *error, NSInteger result) {
                res = result;
                if (error) {
                    qlerror(@"Error running script.");
                    qlerror(@"%@",error.localizedDescription);
                }
                qlinfo(@"End running script");
                dispatch_semaphore_signal(sem);
            }];
        }
    }];
    
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    qlinfo(@"Script result: %d",(int)res);
    return (int)res;
}

#pragma mark - HTML

- (NSString *)htmlForFile:(NSString *)file
{
    NSString *filePath = [[NSBundle mainBundle] pathForResource:file ofType:@"html" inDirectory:@"provision"];
    NSString *htmlString = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
    return htmlString;
}

- (NSString *)htmlForTab:(NSInteger)tabID data:(NSArray *)data
{
    NSDictionary *tabData = nil;
    for (NSDictionary *d in data)
    {
        if ([[d objectForKey:@"id"] integerValue] == tabID)
        {
            tabData = [d copy];
            break;
        }
    }
    
    if (!tabData) {
        qlwarning(@"No Data for tab");
        return @"";
    }

    NSString *filePath;
    NSString *htmlStringBase;
    NSString *htmlString;
    if ([tabData[@"type"] isEqualToString:@"html"]) {
        
        filePath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"html" inDirectory:@"provision"];
        htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
        htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[HDATA]" withString:[self htmlFromArray:tabData[@"html"]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[HTITLE]" withString:[self htmlTitleForTab:tabData]];
        
    } else if ([tabData[@"type"] isEqualToString:@"fields"]) {
        
        filePath = [[NSBundle mainBundle] pathForResource:@"fields" ofType:@"html" inDirectory:@"provision"];
        htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
        htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[HDATA]" withString:[self fieldsFromArray:tabData[@"fields"]]];
        htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[HTITLE]" withString:[self htmlTitleForTab:tabData]];
        
    }
    
    return htmlString;
}

- (NSString *)textForTab:(NSInteger)tabID data:(NSArray *)data
{
    NSDictionary *tabData = nil;
    for (NSDictionary *d in data)
    {
        if ([[d objectForKey:@"id"] integerValue] == tabID)
        {
            tabData = [d copy];
            break;
        }
    }
    
    if (!tabData) {
        qlwarning(@"No Data for tab");
        return @"";
    }

    NSString *result = @"";
    if (tabData[@"text"]) {
        result = tabData[@"text"];
    }
    
    return result;
}

- (NSString *)htmlTitleForTab:(NSDictionary *)data
{
    NSMutableString *s = [NSMutableString new];
    [s appendString:@"<div class=\"text-center\">"];
    [s appendFormat:@"<img src=\"%@\" class=\"rounded mx-auto d-block\">",data[@"titleImage"]];
    [s appendFormat:@"%@",data[@"titleHtml"]];
    [s appendString:@"</div>"];
    return [s copy];
}

- (NSString *)htmlFromArray:(NSArray *)data
{
    return [data componentsJoinedByString:@" "];
}

- (NSString *)fieldsFromArray:(NSArray *)data
{
    NSMutableString *s = [NSMutableString new];
    [s appendString:@"<form>"];
    for (NSDictionary *d in data)
    {
        [s appendString:@"<div class=\"form-group\">"];
        [s appendFormat:@"<label for=\"%@\">%@</label>",d[@"field"],d[@"label"]];
        if ([d[@"type"] isEqualToString:@"textField"]) {
        [s appendFormat:@"<input type=\"text\" class=\"form-control\" id=\"%@\" placeholder=\"%@\" data-toggle=\"tooltip\" alt=\"tooltip\" onfocus=\"%@\">",d[@"field"],d[@"placeholder"],d[@"help"]];
        } else if ([d[@"type"] isEqualToString:@"selectField"]) {
            [s appendFormat:@"<select class=\"form-control\" id=\"%@\">",d[@"field"]];
            NSArray *opts = d[@"selectValues"];
            if (opts.count >= 1)
            {
                for (NSString *o in opts)
                {
                    [s appendFormat:@"<option>%@</option>",o];
                }
            }
            [s appendString:@"</select>"];
            
        }
        [s appendString:@"</div>"];
    }
    [s appendString:@"</form>"];
    return [s copy];
    /*
    <div class="form-group">
        <label for="oun">Primary User - OUN</label>
        <input type="text" class="form-control" id="oun" placeholder="OUN">
    </div>
     */
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
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
    // Ensure that there's a helper tool connection in place.
    self.workerConnection = nil;
    [self connectToHelperTool];
    
    commandBlock(nil);
}


@end
