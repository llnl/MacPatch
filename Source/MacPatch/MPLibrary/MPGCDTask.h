//
//  MPGCDTask.h
//  MPLibrary
//
//  Created by Charles Heizer on 5/9/19.
//

#import <Foundation/Foundation.h>

@interface MPGCDTask : NSObject

@property (nonatomic, assign, readonly) BOOL    taskTimedOut;
@property (nonatomic, assign, readonly) int     installtaskResult;

- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs error:(NSError **)err;
- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs environment:(NSDictionary *)aEnv error:(NSError **)err;

@end
