//
//  MPFileMonitor.h
//  MacPatch
//
//  Created by Charles Heizer on 10/28/20.
//  Copyright © 2020 Heizer, Charles. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, MPFileMonitorChangeType)
{
    MPFileMonitorChangeTypeModified,
    MPFileMonitorChangeTypeMetadata,
    MPFileMonitorChangeTypeSize,
    MPFileMonitorChangeTypeRenamed,
    MPFileMonitorChangeTypeDeleted,
    MPFileMonitorChangeTypeObjectLink,
    MPFileMonitorChangeTypeRevoked
};

@protocol MPFileMonitorDelegate;

@interface MPFileMonitor : NSObject

@property (nonatomic, weak) id<MPFileMonitorDelegate> delegate;

- (id)initWithFilePath:(NSString *)filePath;

@end

@protocol MPFileMonitorDelegate <NSObject>
@optional

- (void)fileMonitor:(MPFileMonitor *)fileMonitor didChange:(MPFileMonitorChangeType)changeType;

@end



