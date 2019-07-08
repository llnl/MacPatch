//
//  HistoryViewController.h
//  MacPatch
//
//  Created by Heizer, Charles on 12/16/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface HistoryViewController : NSViewController
{
    IBOutlet NSArrayController  *arrayController;
}

@property (nonatomic, retain) IBOutlet NSImageView *statusImage;
@property (nonatomic, retain) IBOutlet NSTextField *statusText;

@end
