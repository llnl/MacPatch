//
//  FMXTableMap.m
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import "FMXTableMap.h"
#import "FMXColumnMap.h"

@implementation FMXTableMap

- (id)init {
    self = [super init];
    if (self) {
        self.columns = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)hasIntColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeInt] forKey:name];
}

- (void)hasIntColumn:(NSString *)name withPrimaryKey:(BOOL)key {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeInt] forKey:name];
    if (key) {
        self.primaryKeyName = name;
    }
}

-(void)hasIntIncrementsColumn:(NSString *)name {
    FMXColumnMap *column = [[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeInt];
    column.increments = YES;
    [self.columns setObject:column forKey:name];
    self.primaryKeyName = name;
}

- (void)hasLongColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeLong] forKey:name];
}

-(void)hasLongColumn:(NSString *)name withPrimaryKey:(BOOL)key {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeLong] forKey:name];
    if (key) {
        self.primaryKeyName = name;
    }    
}

-(void)hasLongIncrementsColumn:(NSString *)name {
    FMXColumnMap *column = [[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeLong];
    column.increments = YES;
    [self.columns setObject:column forKey:name];
    self.primaryKeyName = name;
}

- (void)hasLongLongIntColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeLongLongInt] forKey:name];
}

- (void)hasLongLongIntColumn:(NSString *)name withPrimaryKey:(BOOL)key {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeLongLongInt] forKey:name];
    if (key) {
        self.primaryKeyName = name;
    }
}

- (void)hasLongLongIntIncrementsColumn:(NSString *)name {
    FMXColumnMap *column = [[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeLongLongInt];
    column.increments = YES;
    [self.columns setObject:column forKey:name];
    self.primaryKeyName = name;
}

- (void)hasUnsignedLongLongIntColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeUnsignedLongLongInt] forKey:name];
}

- (void)hasUnsignedLongLongIntColumn:(NSString *)name withPrimaryKey:(BOOL)key {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeUnsignedLongLongInt] forKey:name];
    if (key) {
        self.primaryKeyName = name;
    }
}

- (void)hasUnsignedLongLongIntIncrementsColumn:(NSString *)name {
    FMXColumnMap *column = [[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeUnsignedLongLongInt];
    column.increments = YES;
    [self.columns setObject:column forKey:name];
    self.primaryKeyName = name;
}

- (void)hasBoolColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeBool] forKey:name];
}

- (void)hasDoubleColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeDouble] forKey:name];
}

- (void)hasStringColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeString] forKey:name];
}

- (void)hasDateColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeDate] forKey:name];
}

- (void)hasDataColumn:(NSString *)name {
    [self.columns setObject:[[FMXColumnMap alloc] initWithName:name type:FMXColumnMapTypeData] forKey:name];
}

- (FMXColumnMap *)columnForPrimaryKey {
    return [self.columns objectForKey:self.primaryKeyName];
}

@end
