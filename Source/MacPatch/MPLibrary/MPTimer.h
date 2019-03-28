//
//  MPTimer.h
//  MPLibrary
//
//  Created by Charles Heizer on 3/7/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPTimer : NSObject

/**---------------------------------------------------------------------------------------
 @name Creating a Timer
 -----------------------------------------------------------------------------------------
 */

/** Creates and returns a new repeating RNTimer object and starts running it
 After `seconds` seconds have elapsed, the timer fires, executing the block.
 You will generally need to use a weakSelf pointer to avoid a retain loop.
 The timer is attached to the main GCD queue.
 @param seconds The number of seconds between firings of the timer. Must be greater than 0.
 @param block Block to execute. Must be non-nil
 @return A new RNTimer object, configured according to the specified parameters.
 */
+ (MPTimer *)repeatingTimerWithTimeInterval:(NSTimeInterval)seconds block:(dispatch_block_t)block;


/**---------------------------------------------------------------------------------------
 @name Firing a Timer
 -----------------------------------------------------------------------------------------
 */

/** Causes the block to be executed.
 This does not modify the timer. It will still fire on schedule.
 */
- (void)fire;


/**---------------------------------------------------------------------------------------
 @name Stopping a Timer
 -----------------------------------------------------------------------------------------
 */

/** Stops the receiver from ever firing again
 Once invalidated, a timer cannot be reused.
 */
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
