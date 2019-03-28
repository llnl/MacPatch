//
//  ExecFoo.m
//  MPAgentExec
//
//  Created by Charles Heizer on 3/5/19.
//  Copyright © 2019 LLNL. All rights reserved.
//

#import "ExecFoo.h"

@implementation ExecFoo

- (void)scanForatches
{
	MPPatching *patching = [MPPatching new];
	NSArray *patches = [patching scanForPatchesUsingTypeFilter:kAllPatches forceRun:NO];
	qlinfo(@"Patches Required:");
	qlinfo(@"%@",patches);
}

@end
