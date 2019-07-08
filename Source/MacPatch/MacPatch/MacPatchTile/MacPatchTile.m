//
//  MacPatchTile.m
//  MacPatchTile
//
//  Created by Charles Heizer on 2/6/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import "MacPatchTile.h"

@interface MacPatchTile ()

@property (retain) id macPatchObserver;
/*
@property (retain) id privilegesObserver;
@property (retain) id timeoutObserver;
@property (atomic, copy, readwrite) NSMenu *theDockMenu;
@property (atomic, copy, readwrite) NSString *cliPath;
@property (atomic, copy, readwrite) NSBundle *mainBundle;
@property (atomic, strong, readwrite) NSTimer *toggleTimer;
@property (atomic, strong, readwrite) NSDate *timerExpires;
 */
@end

@implementation MacPatchTile

static void updatePatchCount(NSDockTile *tile)
{
	CFPreferencesAppSynchronize(CFSTR("gov.llnl.mp.MacPatch.MacPatchTile"));
	NSInteger patchCount = CFPreferencesGetAppIntegerValue(CFSTR("PatchCount"), CFSTR("gov.llnl.mp.MacPatch.MacPatchTile"), NULL);
	if (patchCount >= 1) {
		[tile setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)patchCount]];
	} else {
		[tile setBadgeLabel:@""];
	}
}

- (void)setDockTile:(NSDockTile *)dockTile
{
	if (dockTile)
	{
		// Attach an observer that will update the high score in the dock tile whenever it changes
		self.macPatchObserver = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"gov.llnl.mp.MacPatch.PatchCount" object:nil queue:nil usingBlock:^(NSNotification *notification) {
			updatePatchCount(dockTile);	// Note that this block captures (and retains) dockTile for use later. Also note that it does not capture self, which means -dealloc may be called even while the notification is active. Although it's not clear this needs to be supported, this does eliminate a potential source of leaks.
		}];
		updatePatchCount(dockTile);	// Make sure score is updated from the get-go as well
	} else {
		// Strictly speaking this may not be necessary (since the plug-in may be terminated when it's removed from the dock), but it's good practice
		[[NSDistributedNotificationCenter defaultCenter] removeObserver:self.macPatchObserver];
		self.macPatchObserver = nil;
	}
}

@end
