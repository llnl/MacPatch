//
//  MPFileMonitor.m
//  MacPatch

#import "MPFileMonitor.h"


@interface MPFileMonitor ()
{
    NSString            *fileToMonitorPath;
    dispatch_source_t   source;
    int                 fileDescriptor;
    BOOL                keepMonitoringFile;
}

@end

@implementation MPFileMonitor

- (id)initWithFilePath:(NSString *)filePath
{
    self = [self init];
    if (self)
    {
        fileToMonitorPath = filePath;
        keepMonitoringFile = NO;
        [self startMonitoringFile];
    }
    return self;
}

- (void)dealloc
{
    dispatch_source_cancel(source);
}

- (void)startMonitoringFile
{
    // Add a file descriptor for our test file
    fileDescriptor = open([fileToMonitorPath fileSystemRepresentation], O_EVTONLY);
    
    // Get a reference to the default queue so our file notifications can go out on it
    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    // Create a dispatch source
    source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fileDescriptor,
                                     DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE | DISPATCH_VNODE_WRITE,
                                     defaultQueue);
    
    // Log one or more messages to the screen when there's a file change event
    dispatch_source_set_event_handler(source, ^
    {
        unsigned long eventTypes = dispatch_source_get_data(self->source);
        [self notifyDelegateOfEvents:eventTypes];
    });
    
    dispatch_source_set_cancel_handler(source, ^{
        close(self->fileDescriptor);
        
        self->fileDescriptor = 0;
        self->source = nil;
        
        // If this dispatch source was canceled because of a rename or delete notification, recreate it
        if (self->keepMonitoringFile)
        {
            self->keepMonitoringFile = NO;
            [self startMonitoringFile];
        }
    });
    
    // Start monitoring the test file
    dispatch_resume(self->source);
}

- (void)recreateDispatchSource
{
    keepMonitoringFile = YES;
    dispatch_source_cancel(source);
}

- (void)notifyDelegateOfEvents:(unsigned long)eventTypes
{
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL recreateDispatchSource = NO;
        NSMutableSet *eventSet = [[NSMutableSet alloc] init];
        
        if (eventTypes & DISPATCH_VNODE_ATTRIB)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeMetadata)];
        }
        if (eventTypes & DISPATCH_VNODE_DELETE)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeDeleted)];
            recreateDispatchSource = YES;
        }
        if (eventTypes & DISPATCH_VNODE_EXTEND)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeSize)];
        }
        if (eventTypes & DISPATCH_VNODE_LINK)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeObjectLink)];
        }
        if (eventTypes & DISPATCH_VNODE_RENAME)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeRenamed)];
            recreateDispatchSource = YES;
        }
        if (eventTypes & DISPATCH_VNODE_REVOKE)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeRevoked)];
        }
        if (eventTypes & DISPATCH_VNODE_WRITE)
        {
            [eventSet addObject:@(MPFileMonitorChangeTypeModified)];
        }
        
        for (NSNumber *eventType in eventSet)
        {
            MPFileMonitorChangeType changeType = (MPFileMonitorChangeType)[eventType unsignedIntegerValue];
            [self.delegate fileMonitor:self didChange:changeType];
        }
        
        if (recreateDispatchSource)
        {
            [self recreateDispatchSource];
        }
    });
}

@end
