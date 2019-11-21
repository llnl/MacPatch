//
//  LongPatch.m
//  TestAlert
//
//  Created by Charles Heizer on 11/20/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import "LongPatchWindow.h"

@interface LongPatchWindow ()

@end

@implementation LongPatchWindow

@synthesize title;
@synthesize message;
@synthesize patch;

- (id)initWithWindowNibName:(NSString *)windowNibName patch:(NSDictionary *)aPatch
{
    self = [super initWithWindowNibName:windowNibName];
    // custom stuff
	[self setPatch:aPatch];
    return self;
}

- (id)initWithWindowNibName:(NSString *)windowNibName
{
	self = [super initWithWindowNibName:windowNibName];
	if (self)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSMutableString *str = [NSMutableString new];
			[str appendString:@"This patch can take a long while to install.\n"];
			[str appendString:@"Please do not interupt the patching process. Some times the patch can sit at a \"black\" screen with no progress.\n"];
			self->message.stringValue = str;
		});
	}
	return self;
}

- (id)initWithPatch:(NSDictionary *)aPatch
{
	self = [super initWithWindowNibName:@"LongPatchWindow"];
	if (self)
	{
		[self setPatch:aPatch];
	}
	return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (void)show
{
	[self.window makeKeyAndOrderFront:self];
	[self.window makeMainWindow];
}

- (void)setPatch:(NSDictionary *)arg1
{
	patch = arg1;
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableString *str = [NSMutableString new];
		[str appendFormat:@"%@ can take a long while to install.\n",arg1[@"patch"]];
		[str appendString:@"Please do not interupt the patching process. Some times the patch can sit at a \"black\" screen with no progress.\n"];
		self.message.stringValue = str;
	});
}

@end
