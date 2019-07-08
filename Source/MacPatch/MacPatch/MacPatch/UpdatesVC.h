//
//  UpdatesVC.h
//  MacPatch
//
//  Created by Charles Heizer on 11/15/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UpdatesVC : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (weak) IBOutlet NSTableView *tableView;

@end

NS_ASSUME_NONNULL_END
