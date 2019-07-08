//
//  DBRequiredPatches.h
//  MPLibrary
//
//  Created by Charles Heizer on 2/12/19.
//

#import "FMXModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DBRequiredPatches : FMXModel

@property (strong, nonatomic) NSNumber *id;
@property (strong, nonatomic) NSString *type;
@property (strong, nonatomic) NSString *patch_id;
@property (strong, nonatomic) NSString *patch;
@property (strong, nonatomic) NSString *patch_version;
@property (strong, nonatomic) NSNumber *patch_reboot;
@property (strong, nonatomic) NSData   *patch_data;
@property (strong, nonatomic) NSDate   *patch_scandate;

@end

NS_ASSUME_NONNULL_END
