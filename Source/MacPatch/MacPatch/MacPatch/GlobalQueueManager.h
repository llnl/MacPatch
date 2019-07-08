//
//  GlobalQueueManager.h
//  TestTable
//
//  Created by Heizer, Charles on 12/18/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GlobalQueueManager : NSObject

@property (nonatomic) NSOperationQueue *globalQueue;
+ (instancetype)sharedInstance;

@end
