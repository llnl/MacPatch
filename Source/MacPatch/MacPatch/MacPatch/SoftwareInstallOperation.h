//
//  SoftwareInstallOperation.h
//  MacPatch
//
//  Created by Charles Heizer on 11/5/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SoftwareInstallOperation : NSOperation
{
	
@private
	NSFileManager 	*fm;
	NSXPCConnection *workerConnection;
}

@property (nonatomic, readonly) BOOL isExecuting;
@property (nonatomic, readonly) BOOL isFinished;
@property (nonatomic, strong, setter = setSWTask:) NSDictionary *swTask;
@property (nonatomic, strong, readonly) NSDictionary *userInfo;

@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;
@end

NS_ASSUME_NONNULL_END
