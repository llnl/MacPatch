//
//  RequiredPatch.h
//  FMDBme
//
//  Created by Charles Heizer on 10/25/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RequiredPatch : NSObject <NSCoding, NSCopying>

@property (strong, nonatomic) NSString *id;
@property (strong, nonatomic) NSString *type;
@property (strong, nonatomic) NSString *patch_id;
@property (strong, nonatomic) NSString *patch;
@property (strong, nonatomic) NSString *patch_version;
@property (assign, nonatomic) NSInteger patch_reboot;
@property (strong, nonatomic) NSData   *patch_data;
@property (strong, nonatomic) NSDate   *patch_scandate;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end
