//
//  NSTask+KillBy.h
//  MPLibrary
//
//  Created by Charles Heizer on 3/26/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTask (KillBy)

- (void)endTaskOnTimeoutInterval:(NSTimeInterval)timeOut;

@end

NS_ASSUME_NONNULL_END
