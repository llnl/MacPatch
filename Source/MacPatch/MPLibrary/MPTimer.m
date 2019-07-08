//
//  MPTimer.m
//  MPLibrary
//
//  Created by Charles Heizer on 3/7/19.
//

#import "MPTimer.h"

@interface MPTimer ()

@property (nonatomic, readwrite, copy) dispatch_block_t block;
@property (nonatomic, readwrite, assign) dispatch_source_t source;

@end

@implementation MPTimer
@synthesize block = _block;
@synthesize source = _source;

+ (MPTimer *)repeatingTimerWithTimeInterval:(NSTimeInterval)seconds block:(void (^)(void))block
{
	NSParameterAssert(seconds);
	NSParameterAssert(block);
	
	MPTimer *timer = [[self alloc] init];
	timer.block = block;
	timer.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	uint64_t nsec = (uint64_t)(seconds * NSEC_PER_SEC);
	dispatch_source_set_timer(timer.source, dispatch_time(DISPATCH_TIME_NOW, nsec), nsec, 0);
	dispatch_source_set_event_handler(timer.source, block);
	dispatch_resume(timer.source);
	return timer;
}

- (void)invalidate
{
	if (self.source)
	{
		dispatch_source_cancel(self.source);
		self.source = nil;
	}
	self.block = nil;
}

- (void)dealloc
{
	[self invalidate];
}

- (void)fire {
	self.block();
}

@end
