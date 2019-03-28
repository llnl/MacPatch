//
//  SysInfoNetworkPlugin.h
//  SysInfoNetwork
//
//  Created by Heizer, Charles on 8/31/15.
//  Copyright (c) 2015 Charles Heizer. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "InventoryPlugin.h"

@interface SysInfoNetworkPlugin : NSObject <InventoryPluginProtocol>

- (NSDictionary *)runInventoryCollection;

@end
