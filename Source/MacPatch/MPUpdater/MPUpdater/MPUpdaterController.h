//
//  MPUpdaterController.h
//  MPUpdater
//
//  Created by Charles Heizer on 3/21/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MPServerConnection;
@class MPAsus;
@class MPDataMgr;

NS_ASSUME_NONNULL_BEGIN

@interface MPUpdaterController : NSObject
{
	MPServerConnection *mpServerConnection;
	
	MPAsus          *mpAsus;
	MPDataMgr       *mpDataMgr;
}

@property (nonatomic, strong)   NSString        *_cuuid;
@property (nonatomic, strong)   NSString        *_appPid;
@property (nonatomic, strong)   NSDictionary    *_updateData;
@property (nonatomic, strong)   NSDictionary    *_osVerDictionary;
@property (nonatomic, strong)   NSString        *_migrationPlist;

@property (strong)              NSTimer         *taskTimeoutTimer;
@property (nonatomic, assign)   NSTimeInterval  taskTimeoutValue;
@property (nonatomic, assign)   BOOL            taskTimedOut;

- (int)scanForUpdate;
- (void)scanAndUpdate;

@end

NS_ASSUME_NONNULL_END
