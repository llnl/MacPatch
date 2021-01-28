//
//  Software.h
//  MPAgent
//
//  Created by Charles Heizer on 7/26/18.
//  Copyright © 2018 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Software : NSObject
{
	
}

- (int)installSoftwareTask:(NSDictionary *)swTaskDict;

- (BOOL)isSoftwareTaskInstalled:(NSString *)tuuid;
- (BOOL)recordRequiredSoftware:(NSArray *)ids;
- (BOOL)recordInstalledRequiredSoftware:(NSDictionary *)swTask;

@end

