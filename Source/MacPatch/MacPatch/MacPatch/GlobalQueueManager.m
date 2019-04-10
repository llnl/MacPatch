//
//  GlobalQueueManager.m
//  TestTable
//
//  Created by Heizer, Charles on 12/18/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

#import "GlobalQueueManager.h"

@implementation GlobalQueueManager

+ (instancetype)sharedInstance
{
    static id mySharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mySharedInstance = [[self alloc] init];
    });
    return mySharedInstance;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        _globalQueue = [[NSOperationQueue alloc] init];
        [_globalQueue setMaxConcurrentOperationCount:1];
    }
    return self;
}

@end
