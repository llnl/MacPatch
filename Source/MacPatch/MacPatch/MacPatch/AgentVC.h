//
//  TestVC.h
//  MacPatch
//
//  Created by Charles Heizer on 7/14/17.
//  Copyright © 2017 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface AgentVC : NSViewController <WKUIDelegate, WKNavigationDelegate,MPHelperProtocol>
{
    
}

@property (strong,nonatomic) IBOutlet WKWebView *wkWebView;

@end
