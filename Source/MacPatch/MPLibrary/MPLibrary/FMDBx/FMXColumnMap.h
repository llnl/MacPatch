//
//  FMXColumnMap.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FMXColumnMapType) {
    FMXColumnMapTypeInt = 0,
    FMXColumnMapTypeLong,
    FMXColumnMapTypeLongLongInt,
    FMXColumnMapTypeUnsignedLongLongInt,
    FMXColumnMapTypeBool,
    FMXColumnMapTypeDouble,
    FMXColumnMapTypeString,
    FMXColumnMapTypeDate,
    FMXColumnMapTypeData
};

@interface FMXColumnMap : NSObject

@property (strong, nonatomic) NSString *name;
@property (assign, nonatomic) FMXColumnMapType type;
@property (assign, nonatomic) BOOL increments;

- (id)initWithName:(NSString *)name type:(FMXColumnMapType)type;
- (NSString *)propertyName;

@end
