//
//  MacPatchTile.m
/*
Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "MacPatchTile.h"

@interface MacPatchTile ()

@property (retain) id macPatchObserver;

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
