//
//  Provisioning.h
//  MPClientStatus
//
//  Created by Charles Heizer on 1/15/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface Provisioning : NSWindowController <NSTabViewDelegate, WKUIDelegate, WKNavigationDelegate>
{
    
}

@property (strong,nonatomic) IBOutlet WKWebView *welcomeWebView;
@property (strong,nonatomic) IBOutlet WKWebView *collectionWebView;
@property (strong,nonatomic) IBOutlet WKWebView *installWebView;
@property (strong,nonatomic) IBOutlet WKWebView *finishWebView;

@end

NS_ASSUME_NONNULL_END
