//
//  SoftwareController.h
//  MPAgent
//
//  Created by Charles Heizer on 5/9/19.
//  Copyright © 2019 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SoftwareController : NSObject

@property (nonatomic, assign)           BOOL        iLoadMode;
@property (nonatomic, assign, readonly) int         needsReboot;

@property (nonatomic, assign, readonly) int         errorCode;
@property (nonatomic, strong, readonly) NSString    *errorMsg;

-(BOOL)installSoftwareTask:(NSString *)aTask;
-(int)installSoftwareTasksForGroup:(NSString *)aGroupName;
-(int)installSoftwareTasksUsingPLIST:(NSString *)aPlist;

@end

