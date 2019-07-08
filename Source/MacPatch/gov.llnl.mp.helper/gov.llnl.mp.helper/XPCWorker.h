//
//  XPCWorker.h
//  gov.llnl.mp.worker
//
//  Created by Charles Heizer on 2/8/17.
//  Copyright © 2017 Lawrence Livermore Nat'l Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MPHelperProtocol.h"

@class MPAsus;
@class MPPatching;

@interface XPCWorker : NSObject <MPAsusDelegate, MPPatchingDelegate>
{
    NSTask              *swTask;
    NSPipe              *pipe_task;
    NSFileHandle        *fh_task;
    NSTimer             *swTaskTimer;
    BOOL                swTaskTimedOut;
    BOOL                swTaskIsRunning;
    int                 swTaskTimeoutValue;
}

- (id)init;
- (void)run;

@end
