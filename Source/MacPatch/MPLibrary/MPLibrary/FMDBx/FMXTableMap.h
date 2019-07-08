//
//  FMXTableMap.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMXColumnMap.h"

@interface FMXTableMap : NSObject

@property (strong, nonatomic) NSString *database;
@property (strong, nonatomic) NSString *tableName;
@property (strong, nonatomic) NSMutableDictionary *columns;
@property (strong, nonatomic) NSString *primaryKeyName;

- (void)hasIntColumn:(NSString *)name;

- (void)hasIntColumn:(NSString *)name withPrimaryKey:(BOOL)key;

- (void)hasIntIncrementsColumn:(NSString *)name;

- (void)hasLongColumn:(NSString *)name;

- (void)hasLongColumn:(NSString *)name withPrimaryKey:(BOOL)key;

- (void)hasLongIncrementsColumn:(NSString *)name;

- (void)hasLongLongIntColumn:(NSString *)name;

- (void)hasLongLongIntColumn:(NSString *)name withPrimaryKey:(BOOL)key;

- (void)hasLongLongIntIncrementsColumn:(NSString *)name;


- (void)hasUnsignedLongLongIntColumn:(NSString *)name;

- (void)hasUnsignedLongLongIntColumn:(NSString *)name withPrimaryKey:(BOOL)key;

- (void)hasUnsignedLongLongIntIncrementsColumn:(NSString *)name;



- (void)hasBoolColumn:(NSString *)name;

- (void)hasDoubleColumn:(NSString *)name;

- (void)hasStringColumn:(NSString *)name;

- (void)hasDateColumn:(NSString *)name;

- (void)hasDataColumn:(NSString *)name;

- (FMXColumnMap *)columnForPrimaryKey;

@end
