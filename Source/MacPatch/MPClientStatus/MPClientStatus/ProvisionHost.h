//
//  ProvisionHost.h
//  MPClientStatus
//
//  Created by Charles Heizer on 2/10/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ProvisionHostDelegate;

@interface ProvisionHost : NSObject

@property (nonatomic, weak) id<ProvisionHostDelegate> delegate;

- (int)provisionHost;

@end

@protocol ProvisionHostDelegate <NSObject>
@optional

- (void)provisionProgress:(NSString *)progressStr;

@end

NS_ASSUME_NONNULL_END
