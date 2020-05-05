//
//  UpdateInstallOperation.h
//  MacPatch
//
//  Created by Charles Heizer on 11/21/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UpdateInstallOperation : NSOperation
{
	
@private
	NSFileManager 	*fm;
}

@property (nonatomic, readonly) 				BOOL isExecuting;
@property (nonatomic, readonly) 				BOOL isFinished;
@property (nonatomic, strong, readonly) 		NSDictionary *userInfo;
@property (nonatomic, strong, setter=setPatch:)	NSDictionary *patch;
@property (atomic, strong, readwrite) 			NSXPCConnection *workerConnection;
//@property (nonatomic, assign, readonly) int showRebootWindow;

@end
