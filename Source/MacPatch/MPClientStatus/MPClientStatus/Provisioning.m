//
//  Provisioning.m
//  MPClientStatus
//
//  Created by Charles Heizer on 1/15/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import "Provisioning.h"
#import <WebKit/WebKit.h>
#import "ProvisionHost.h"
#import <dispatch/dispatch.h>
#import "EventToSend.h"

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


@interface Provisioning ()
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

@property (strong, nonatomic) NSWindow *backwindow;
@property (weak) IBOutlet NSButton *closeWindowButton;

// Helper
// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation Provisioning

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
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    
    [_stepperButton setTitle:@"Begin"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_stepperButton setEnabled:NO]; // Diable Begin button ... initial required sw should be small
    });
    
    NSError *err = nil;
    NSData *data = [NSData dataWithContentsOfFile:MP_PROVISION_DATA_FILE];
    NSDictionary *jdata = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&err];
    if (err) {
        qlerror(@"MP_PROVISION_DATA_FILE contents are null. Unable to provision this system.");
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
}

- (void)runProvisionHostThread
{
    @autoreleasepool
    {
        BOOL beginProvision = NO;
        NSDictionary *provisionFileData = [self readProvisioningFile];
        qldebug(@"provisionFileData: %@", provisionFileData);
        if (provisionFileData[@"stage"])
        {
            if ([[provisionFileData[@"stage"] lowercaseString] isEqualToString:@"begin"] || [[provisionFileData[@"stage"] lowercaseString] isEqualToString:@"getData"])
            {
                beginProvision = YES;
                qldebug(@"beginProvision = YES");
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    //[self writeStatusToHTML:@""];
                    [self->_stepperButton setEnabled:YES];
                    [self->_closeWindowButton setEnabled:YES];
                });
            }
        } else {
            // File is empty 
            beginProvision = YES;
            qldebug(@"beginProvision = YES, File is empty");
        }
        
        // Host need initial required provisioning software installed.
        if (beginProvision)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_closeWindowButton setEnabled:NO]; // Diable Begin button ... initial required sw should be small
            });
            [NSThread sleepForTimeInterval:1.5];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self->textFieldStatusBanner = [[NSTextField alloc] initWithFrame:NSMakeRect(self.window.contentView.frame.size.width/2 - 300, 158, 600, 18)];
                [self->textFieldStatusBanner setStringValue:@"Required software needs to be installed. Once completed, you may begin."];
                [self->textFieldStatusBanner setAlignment:NSTextAlignmentCenter];
                [self->textFieldStatusBanner setFont:[NSFont systemFontOfSize:14]];
                [self->textFieldStatusBanner setBezeled:NO];
                [self->textFieldStatusBanner setDrawsBackground:NO];
                [self->textFieldStatusBanner setEditable:NO];
                [self->textFieldStatusBanner setSelectable:NO];
                [self.window.contentView addSubview:self->textFieldStatusBanner];
                
                self->progressWheelMain = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(self.window.contentView.frame.size.width/2 - 8, 128, 16, 16)];
                [self->progressWheelMain setStyle:NSProgressIndicatorStyleSpinning];
                [self->progressWheelMain startAnimation:nil];
                [self.window.contentView addSubview:self->progressWheelMain];
                
                self->textFieldStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(self.window.contentView.frame.size.width/2 - 300, 98, 600, 18)];
                [self->textFieldStatus setStringValue:@""];
                [self->textFieldStatus setAlignment:NSTextAlignmentCenter];
                [self->textFieldStatus setFont:[NSFont systemFontOfSize:12]];
                [self->textFieldStatus setBezeled:NO];
                [self->textFieldStatus setDrawsBackground:NO];
                [self->textFieldStatus setEditable:NO];
                [self->textFieldStatus setSelectable:NO];
                [self.window.contentView addSubview:self->textFieldStatus];
            });
            
            //NSString *jsTxt = @"<p>Required software needs to be installed. Once completed, you may begin.</p>";
            //[self writeStatusToHTML:jsTxt];
            
            ProvisionHost *ph = [ProvisionHost new];
            ph.delegate = self;
            int result = 99;
            result = [ph provisionHost];
            
            qlinfo(@"provisionHost result = %d",(int)result);
            
            if (result == 0 ) {
                qlinfo(@"Result was good, enable stepper button.");
                qlinfo(@"Result was good, enable close window function.");
                dispatch_async(dispatch_get_main_queue(), ^{
                    //[self writeStatusToHTML:@""];
                    [self->textFieldStatus removeFromSuperview];
                    [self->textFieldStatusBanner removeFromSuperview];
                    [self->progressWheelMain removeFromSuperview];
                    
                    [self->_stepperButton setEnabled:YES]; // Diable Begin button ... initial required sw should be small
                    [self->_closeWindowButton setEnabled:YES];
                });
            } else {
                qlerror(@"result != 0");
                NSAlert *alert = [NSAlert alertWithMessageText:@"Error running initial provisioning."
                    defaultButton:@"Exit"
                    alternateButton:@"Continue"
                    otherButton:nil
                    informativeTextWithFormat:@"There was an error running the initial provisioning installs. Click Exit to exit the app, or click Contimnue and proceed."];
                [alert setAlertStyle:NSCriticalAlertStyle];
                [alert beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
                    if (result == 0) {
                        [self closeWindow:nil];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            //[self writeStatusToHTML:@""];
                            [self->textFieldStatus removeFromSuperview];
                            [self->textFieldStatusBanner removeFromSuperview];
                            [self->progressWheelMain removeFromSuperview];
                            
                            [self->_stepperButton setEnabled:YES]; // Diable Begin button ... initial required sw should be small
                            [self->_closeWindowButton setEnabled:YES];
                        });
                    }
                }];
            }
        }
        else {
            qlinfo(@"beginProvision == false");
            dispatch_async(dispatch_get_main_queue(), ^{
                //[self writeStatusToHTML:@""];
                [self->textFieldStatus removeFromSuperview];
                [self->textFieldStatusBanner removeFromSuperview];
                [self->progressWheelMain removeFromSuperview];
                
                [self->_stepperButton setEnabled:YES]; // Diable Begin button ... initial required sw should be small
                [self->_closeWindowButton setEnabled:YES];
            });
        }
    }
}

- (NSDictionary *)readProvisioningFile
{
    NSMutableDictionary *_pFile;
    if ( [fm fileExistsAtPath:MP_PROVISION_FILE] ) {
        _pFile = [NSMutableDictionary dictionaryWithContentsOfFile:MP_PROVISION_FILE];
    } else {
        _pFile = [NSMutableDictionary new];
    }
    return [_pFile copy];
}

// Test Method, button is hidden
- (IBAction)writeJS:(NSButton *)sender
{
    [self connectAndExecuteCommandBlock:^(NSError * connectError)
     {
         if (connectError != nil)
         {
             qlerror(@"connectError: %@",connectError.localizedDescription);
         }
         else
         {
             NSData *myData = [NSKeyedArchiver archivedDataWithRootObject:@{@"testKey":@"testVal",@"testKey2":@"testVal2"}];
             [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                 qlerror(@"proxyError: %@",proxyError.localizedDescription);
             }] postProvisioningData:@"userInfoData" dataForKey:myData dataType:@"dict" withReply:^(NSError *err) {
                dispatch_sync(dispatch_get_main_queue(), ^()
                   {
                       NSAlert *alert = [[NSAlert alloc] init];
                       [alert addButtonWithTitle:@"OK"];
                       if (err) {
                           [alert setMessageText:@"Error with check-in"];
                           [alert setInformativeText:@"There was a problem checking in with the server. Please review the client status logs for cause."];
                           [alert setAlertStyle:NSCriticalAlertStyle];
                       } else {
                           [alert setMessageText:@"Client check-in"];
                           [alert setInformativeText:@"Client check-in was successful."];
                           [alert setAlertStyle:NSInformationalAlertStyle];
                           
                       }
                       
                       [alert runModal];
                   });
             }];
         }
     }];
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

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector { return NO; }

- (NSURL *)urlForFile:(NSString *)name
{
    NSString *path = [NSString stringWithFormat:@"provision/%@",[name stringByDeletingPathExtension]];
    return [[NSBundle mainBundle] URLForResource:path withExtension:@"html"];
}

- (IBAction)changeTab:(NSButton *)sender
{
    __block NSInteger _selectedIndex = [self.selectedTabViewItem integerValue];
    
    if ([sender.title isEqualToString:@"Install"]) {
        [_stepperButton setEnabled:NO];
        [_stepperButton setTitle:@"Continue"];
        [self performSelectorInBackground:@selector(installSoftwareThread) withObject:nil];
        // Start installs
        
    } else if ([sender.title isEqualToString:@"Reboot"] || [sender.title isEqualToString:@"Finished"]) {
        // Write Done file and Code to reboot host
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.backwindow orderOut:self];
        });
        
        
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [self connectAndExecuteCommandBlock:^(NSError * connectError) {
             if (connectError != nil) {
                 qlerror(@"connectError: %@",connectError.localizedDescription);
                 dispatch_semaphore_signal(sem);
             } else {
                 [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                     qlerror(@"proxyError: %@",proxyError.localizedDescription);
                     dispatch_semaphore_signal(sem);
                 }] touchFile:MP_PROVISION_DONE withReply:^(NSError *error) {
                     if (error) {
                       qlerror(@"Error writing provisioning done file.");
                     }
                     dispatch_semaphore_signal(sem);
                 }];
             }
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        //[self closeWindow:nil];
        [self closeOrRebootHost];
    
    } else {
        if ([self.selectedTabViewItem isEqualToString:@"1"])
        {
            // Get All Values
            NSError *err = nil;
            NSDictionary *vals = [self getHTMLValues:&err];
            __block NSData *myData = [NSKeyedArchiver archivedDataWithRootObject:vals];
            
            if (err) {
                qlerror(@"%@",err.localizedDescription);
                NSAlert *alert = [NSAlert alertWithMessageText:@"Input Required"
                                                 defaultButton:@"OK" alternateButton:nil otherButton:nil
                                     informativeTextWithFormat:@"All fields must be answered to continue. Please verify your answers."];
                [alert setAlertStyle:NSCriticalAlertStyle];
                [alert beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) { }];
            } else {
                [self connectAndExecuteCommandBlock:^(NSError * connectError)
                 {
                     if (connectError != nil)
                     {
                         qlerror(@"connectError: %@",connectError.localizedDescription);
                     }
                     else
                     {
                         [self->_tabBar selectNextTabViewItem:NULL];
                         
                         [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                             qlerror(@"proxyError: %@",proxyError.localizedDescription);
                         }] postProvisioningData:@"userInfoData" dataForKey:myData dataType:@"dict" withReply:^(NSError *error) {
                            dispatch_sync(dispatch_get_main_queue(), ^()
                               {
                                   
                                   if (error) {
                                       NSAlert *alert = [[NSAlert alloc] init];
                                       [alert addButtonWithTitle:@"OK"];
                                       [alert setMessageText:@"Error with check-in"];
                                       [alert setInformativeText:@"There was a problem checking in with the server. Please review the client status logs for cause."];
                                       [alert setAlertStyle:NSCriticalAlertStyle];
                                       [alert runModal];
                                   } else {
                                       [self->_tabBar selectTabViewItemAtIndex:(_selectedIndex + 1)];
                                   }
                               });
                         }];
                     }
                 }];
            }
        }
        else
        {
            [self->_tabBar selectTabViewItemAtIndex:(_selectedIndex + 1)];
        }
    }
    
}

- (IBAction)skipTab:(NSButton *)sender
{
    NSAlert *alert = [NSAlert alertWithMessageText:@"Skip Software Installs?"
        defaultButton:@"OK"
        alternateButton:@"Cancel"
        otherButton:nil
        informativeTextWithFormat:@"Are you sure you want to skip the software installs? If you do, you can always launch the MacPatch application and install them at a later time."];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result) {
        if (result == 1) {
            [self->_tabBar selectNextTabViewItem:NULL];
        }
    }];
}

// Get HTML Form Values from Tab
- (NSDictionary *)getHTMLValues:(NSError **)err
{
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSDictionary *tabData = [self getDataForTab:self.selectedTabViewItem];
    
    if (![tabData[@"type"] isEqualTo:@"fields"]) {
        return nil;
    };
    
    int i = 0;
    for (NSDictionary *f in tabData[@"fields"])
    {
        __block NSString *field = f[@"field"];
        NSString *fieldJS = [NSString stringWithFormat:@"document.getElementById('%@').value;",f[@"field"]];
        NSString *res = [self.collectionWebView stringByEvaluatingJavaScriptFromString:fieldJS];
        if ([res length] >= [f[@"fieldLen"] intValue]) {
            [result setObject:res forKey:field];
        } else {
            if ([f[@"required"] boolValue]) {
                i++;
            }
        }
    }
    
    if (i != 0) {
        // We did not get values
        NSError *error = [NSError errorWithDomain:@"gov.llnl.mp.provision" code:1001 userInfo:@{@"Error reason": @"Invalid Input"}];
        *err = error;
    }
    return [result copy];
}

- (void)writeStatusToHTML:(NSString *)status
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([status isEqual:@""]) {
            [self->_welcomeWebView evaluateJavaScript:@"clearStatus();" completionHandler:^(id Result, NSError * error) {
                qlerror(@"Error[clearStatus()]: %@",error);
            }];
        } else {
            [self->_welcomeWebView evaluateJavaScript:[NSString stringWithFormat:@"addStatus(\"%@\");",status] completionHandler:^(id Result, NSError * error) {
                qlerror(@"Error[addStatus()]: %@",error);
            }];
        }
    });
}

// Convience method to get the data for a given tab
- (NSDictionary *)getDataForTab:(NSString *)tabIndex
{
    NSDictionary *result = nil;
    NSArray *a = _provisionData[@"tabs"];
    for (NSDictionary *d in a)
    {
        if ([[d objectForKey:@"id"] integerValue] == [tabIndex integerValue]) {
            result = [d copy];
            break;
        }
    }
    
    return result;
}

- (void)closeOrRebootHost
{
    if (_provisionData[@"mandatoryReboot"]) {
        if ([_provisionData[@"mandatoryReboot"] intValue] == 1) {
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
                     }] rebootHost:^(NSError *error) {
                         if (error) {
                             qlerror(@"%@",error.localizedDescription);
                         };
                     }];
                 }
             }];
        }
    } else {
        [self closeWindow:nil];
    }
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
        //[_collectionWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
        [_stepperButton setTitle:@"Continue"];
        [_closeWindowButton setEnabled:NO];
    }
    else if ([tabViewItem.identifier isEqualToString:@"2"])
    {
        //[_installWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
        /*[self writeSoftwareView:@"The following software be will installed once you click the \"Install\" button. This can not be canceled once started. Please note, this may take some time depending on your network connection.\n"];
         */
        NSString *text = [self textForTab:[tabViewItem.identifier intValue] data:_provisionData[@"tabs"]];
        
        // Calc size and count
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
        
        [_skipButton setHidden:NO];
        [_stepperButton setTitle:@"Install"];
    }
    else if ([tabViewItem.identifier isEqualToString:@"3"])
    {
        _finishWebView.allowsBackForwardNavigationGestures = NO;
        //[_finishWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
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

#pragma mark - Required Software Install

#pragma mark - Software

- (void)getSoftwareForGroup:(NSString *)groupName
{
    @autoreleasepool
    {
        MPRESTfull *rest = [MPRESTfull new];
        NSError *err = nil;
        NSArray *swArr = [rest getSoftwareTasksForGroup:groupName error:&err];
        if (err) {
            qlerror(@"%@",err.localizedDescription);
        }
        _swForGroup = [swArr copy];
    }
}

- (void)installSoftwareThread
{
    @autoreleasepool
    {
        int i = 1;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_skipButton setHidden:YES];
            [self->_progressBar setHidden:NO];
            [self->_progressStatus setHidden:NO];
            [self->_progressWheel setHidden:NO];
            [self->_progressWheel startAnimation:nil];
            self->_progressBar.doubleValue = 0.0;
            self->_progressBar.maxValue = self->_swForGroup.count;
        });
        for (NSDictionary *s in _swForGroup)
        {
            [self appendToSoftwareView:[NSString stringWithFormat:@"Installing (%d/%lu) %@",i, (unsigned long)self->_swForGroup.count,s[@"name"]]];
            [self runInstallForTask:s];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_progressBar.doubleValue = i;
                self->_progressStatus.stringValue = [NSString stringWithFormat:@"Installing %@",s[@"name"]];
            });
            i++;
            [NSThread sleepForTimeInterval:1.0];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_progressWheel stopAnimation:nil];
            [self->_progressWheel setHidden:YES];
            self->_progressStatus.stringValue = @"Install(s) complete.";
            [self->_stepperButton setEnabled:YES];
            [self->_stepperButton setTitle:@"Continue"];
        });
    }
}

- (void)runInstallForTask:(NSDictionary *)swTask
{
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    qlinfo(@"Install Software Task: %@",swTask[@"name"]);
    qldebug(@"Task Data: %@",swTask);
    
    [self appendToSoftwareView:@"Starting Install operation"];
    NSDictionary *softwareObj = swTask[@"Software"];
    
    // -----------------------------------------
    // Verify Disk space requirements before
    // downloading and installing
    // -----------------------------------------
    NSScanner *scanner = [NSScanner scannerWithString:softwareObj[@"sw_size"]];
    long long stringToLong;
    if(![scanner scanLongLong:&stringToLong]) {
        qlerror(@"Unable to convert size %@",softwareObj[@"sw_size"]);
        [self appendToSoftwareView:@"Unable to check disk size requirements"];
        [self postStopHasError:YES errorString:@"Unable to check disk size requirements"];
        return;
    }
    
    MPDiskUtil *mpd = [[MPDiskUtil alloc] init];
    if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO)
    {
        qlerror(@"This system does not have enough free disk space to install the following software %@",softwareObj[@"name"]);
        [self appendToSoftwareView:@"System does not have enough free disk space"];
        [self postStopHasError:YES errorString:@"System does not have enough free disk space"];
        return;
    }
    
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
            [self appendToSoftwareView:[NSString stringWithFormat:@"ERROR: %@",connectError.localizedDescription]];
            dispatch_semaphore_signal(sem);
        } else {
            [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
                [self appendToSoftwareView:[NSString stringWithFormat:@"ERROR: %@",proxyError.localizedDescription]];
                dispatch_semaphore_signal(sem);
                
            }] installSoftware:swTask withReply:^(NSError *error, NSInteger resultCode, NSData *installData) {

                if (resultCode == 0) {
                    [self appendToSoftwareView:[NSString stringWithFormat:@"%@ was installed.",swTask[@"Software"][@"name"]]];
                } else {
                    [self appendToSoftwareView:[NSString stringWithFormat:@"ERROR: %@ was not installed.",swTask[@"Software"][@"name"]]];
                    qlerror(@"Error installing software task %@",swTask[@"Software"][@"name"]);
                    if (error) {
                        qlerror(@"Error: %@",error.localizedDescription);
                    }
                    /*
                    else {
                        error = [NSError errorWithDomain:@"InstallError"
                                                                 code:1
                                                             userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to install software task.", nil)}];
                    }
                    */
                }
                
                dispatch_semaphore_signal(sem);
            }];
        }
    }];
        
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

- (void)writeSoftwareView:(NSString*)text
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString* attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n",text]];
        [[self->_softwareTextView textStorage] appendAttributedString:attr];
    });
}

- (void)appendToSoftwareView:(NSString*)text
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString* attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n",text]];
        [[self->_softwareTextView textStorage] appendAttributedString:attr];
        [self->_softwareTextView scrollRangeToVisible:NSMakeRange([[self->_softwareTextView string] length], 0)];
    });
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

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
    if (type == kMPProcessStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_progressStatus.stringValue = status;
        });
    }
}

#pragma mark - ProvisionHost protocol

- (void)provisionProgress:(NSString *)progressStr;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->textFieldStatus) {
            self->textFieldStatus.stringValue = progressStr;
        }
    });
}


#pragma mark - Notifications

- (void)postStopHasError:(BOOL)arg1 errorString:(NSString *)arg2
{
    qlinfo(@"postStopHasError called %@",arg2);
    //NSError *err = nil;
    if (arg1) {
        //err = [NSError errorWithDomain:@"gov.llnl.sw.oper" code:1001 userInfo:@{NSLocalizedDescriptionKey:arg2}];
        //[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{@"error":err}];
    } else {
        //[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{}];
    }
}
@end
