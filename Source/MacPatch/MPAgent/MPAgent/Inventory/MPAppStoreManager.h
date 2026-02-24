//
//  MPAppStoreManager.h
//  MPAgent
//
//  Created by Heizer, Charles on 1/9/26.
//  Copyright © 2026 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPAppStoreManager : NSObject

- (void)getInstalledAppStoreApps;
- (NSArray *)getAllInstalledApps;

- (NSDictionary *)getAppInfo:(NSString *)appPath;
- (BOOL)isAppStoreApp:(NSString *)appPath;
- (void)verifyAppReceipt:(NSString *)appPath;

- (void)fetchAppStoreMetadata;
- (void)fetchMetadataFromiTunesAPI;
- (void)parseAppStoreMetadata:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
