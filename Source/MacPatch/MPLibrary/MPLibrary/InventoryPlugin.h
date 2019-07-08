//
//  InventoryPlugin.h
//  MPAgent
//
//  Created by Heizer, Charles on 9/1/15.
//  Copyright (c) 2017 LLNL. All rights reserved.
//

// InventoryPlugin.h -- protocol for MacPatch Inventory plugins to use

@protocol InventoryPluginProtocol

@property (nonatomic, copy) NSString *pluginName;
@property (nonatomic, copy) NSString *pluginVersion;

@property (nonatomic, weak) NSString *type;
@property (nonatomic, weak) NSString *wstype;
@property (nonatomic, weak) NSArray *data;

- (NSString *)pluginKey;
- (NSDictionary *)runInventoryCollection;

@end
