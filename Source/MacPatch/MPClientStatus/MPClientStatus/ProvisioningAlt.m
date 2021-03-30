//
//  ProvisioningAlt.m
//  MPClientStatus
//
//  Created by Charles Heizer on 3/18/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import "ProvisioningAlt.h"
#import "MPGradientView.h"

@interface ProvisioningAlt ()

@property (strong) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTabView *tabBar;
@property (weak) IBOutlet NSButton *nextButton;
@property (weak) IBOutlet NSTextField *nextButtonLabel;

@end

@implementation ProvisioningAlt

@dynamic window;

- (void)windowDidLoad {
    [super windowDidLoad];
    [(MPGradientView *)self.window.contentView setYPoint:60];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (IBAction)nextTab:(id)sender
{
    [self.tabBar selectNextTabViewItem:nil];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    
}

@end
