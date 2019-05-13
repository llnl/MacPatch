//
//  MPOperation.h
//  MPAgent
//
//  Created by Charles Heizer on 5/9/19.
//  Copyright © 2019 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MPOperation : NSOperation

@property (nonatomic, strong)	NSString 	*taskName;
@property (nonatomic)			BOOL 		isExecuting;
@property (nonatomic)			BOOL 		isFinished;

@end
