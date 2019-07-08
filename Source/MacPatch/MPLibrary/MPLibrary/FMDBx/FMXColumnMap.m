//
//  FMXColumnMap.m
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import "FMXColumnMap.h"
#import "FMXHelpers.h"

@implementation FMXColumnMap

- (id)initWithName:(NSString *)name type:(FMXColumnMapType)type
{
    self = [super init];
    if (self) {
        self.name = name;
        self.type = type;
        self.increments = NO;
    }
    return self;
}

-(NSString *)propertyName
{
    //return FMXLowerCamelCaseFromSnakeCase(self.name);
	return self.name;
}

@end
