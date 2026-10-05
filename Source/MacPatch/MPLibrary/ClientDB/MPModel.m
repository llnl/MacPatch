//
//  MPModel.m
//  MPLibrary
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.

 This file is part of MacPatch, a program for installing and patching
 software.

 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.

 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.

 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#import "MPModel.h"
#import "Logger.h"
#import <objc/runtime.h>

@implementation MPModel

#pragma mark - Configuration

+ (NSString *)databasePath
{
	// Default to MacPatch agent database
	// Subclasses can override
	return @"/private/var/db/.MacPatch.db";
}

+ (NSString *)tableName
{
	// Default to lowercase class name
	return [NSStringFromClass(self) lowercaseString];
}

+ (NSString *)primaryKey
{
	return @"id";
}

+ (NSArray<NSString *> *)ignoredProperties
{
	// Base class properties that shouldn't be persisted
	return @[@"hash", @"superclass", @"description", @"debugDescription"];
}

#pragma mark - Database Access

+ (FMDatabase *)database
{
	static NSMutableDictionary *databases = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		databases = [NSMutableDictionary dictionary];
	});

	NSString *path = [self databasePath];
	FMDatabase *db = databases[path];

	if (!db) {
		db = [FMDatabase databaseWithPath:path];
		databases[path] = db;
	}

	if (![db open]) {
		LogError(@"Failed to open database at %@: %@", path, [db lastErrorMessage]);
		return nil;
	}

	return db;
}

+ (nullable id)executeQuery:(void(^)(FMDatabase *db))block
{
	FMDatabase *db = [self database];
	if (!db) return nil;

	@try {
		block(db);
	}
	@catch (NSException *exception) {
		LogError(@"Database query exception: %@", exception);
		return nil;
	}

	return @(YES);
}

#pragma mark - Property Introspection

+ (NSArray<NSString *> *)propertyNames
{
	static NSMutableDictionary *propertyCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		propertyCache = [NSMutableDictionary dictionary];
	});

	NSString *className = NSStringFromClass(self);
	NSArray *cached = propertyCache[className];
	if (cached) {
		return cached;
	}

	NSMutableArray *properties = [NSMutableArray array];
	NSArray *ignored = [self ignoredProperties];

	unsigned int count;
	objc_property_t *propList = class_copyPropertyList(self, &count);

	for (unsigned int i = 0; i < count; i++) {
		objc_property_t property = propList[i];
		NSString *propName = [NSString stringWithUTF8String:property_getName(property)];

		if (![ignored containsObject:propName]) {
			[properties addObject:propName];
		}
	}

	free(propList);

	propertyCache[className] = properties;
	return properties;
}

+ (NSString *)propertyType:(NSString *)propertyName
{
	objc_property_t property = class_getProperty(self, [propertyName UTF8String]);
	if (!property) return nil;

	const char *attrs = property_getAttributes(property);
	NSString *attrString = [NSString stringWithUTF8String:attrs];

	// Format: T@"NSString",&,N,V_name or Tq,N,V_age (for NSInteger)
	// Extract type encoding
	if ([attrString hasPrefix:@"T@\""] && [attrString length] > 3) {
		NSRange range = NSMakeRange(3, [attrString rangeOfString:@"\"" options:0 range:NSMakeRange(3, [attrString length] - 3)].location - 3);
		return [attrString substringWithRange:range];
	}

	// Primitive types
	if ([attrString hasPrefix:@"Tq"] || [attrString hasPrefix:@"Ti"] || [attrString hasPrefix:@"Ts"]) {
		return @"NSInteger";
	}
	if ([attrString hasPrefix:@"Tf"] || [attrString hasPrefix:@"Td"]) {
		return @"CGFloat";
	}
	if ([attrString hasPrefix:@"TB"] || [attrString hasPrefix:@"Tc"]) {
		return @"BOOL";
	}

	return @"Unknown";
}

#pragma mark - SQL Generation

+ (NSString *)createTableSQL
{
	NSMutableArray *columns = [NSMutableArray array];
	[columns addObject:[NSString stringWithFormat:@"%@ INTEGER PRIMARY KEY AUTOINCREMENT", [self primaryKey]]];

	for (NSString *propName in [self propertyNames]) {
		if ([propName isEqualToString:[self primaryKey]]) continue;

		NSString *type = [self propertyType:propName];
		NSString *sqlType = @"TEXT";

		if ([type isEqualToString:@"NSNumber"]) {
			sqlType = @"INTEGER";
		} else if ([type isEqualToString:@"NSDate"]) {
			sqlType = @"REAL";
		} else if ([type isEqualToString:@"NSData"]) {
			sqlType = @"BLOB";
		} else if ([type isEqualToString:@"NSInteger"] || [type isEqualToString:@"BOOL"]) {
			sqlType = @"INTEGER";
		} else if ([type isEqualToString:@"CGFloat"]) {
			sqlType = @"REAL";
		}

		[columns addObject:[NSString stringWithFormat:@"%@ %@", propName, sqlType]];
	}

	return [NSString stringWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@)",
			[self tableName], [columns componentsJoinedByString:@", "]];
}

#pragma mark - CRUD Operations

- (BOOL)save
{
	FMDatabase *db = [[self class] database];
	if (!db) return NO;

	[[self class] createTable]; // Ensure table exists

	NSArray *properties = [[self class] propertyNames];
	NSMutableArray *columns = [NSMutableArray array];
	NSMutableArray *placeholders = [NSMutableArray array];
	NSMutableArray *values = [NSMutableArray array];

	for (NSString *propName in properties) {
		if ([propName isEqualToString:[[self class] primaryKey]]) continue;

		id value = [self valueForKey:propName];
		if (value) {
			[columns addObject:propName];
			[placeholders addObject:@"?"];
			[values addObject:[self databaseValueForProperty:propName value:value]];
		}
	}

	BOOL result = NO;

	if (self.id == nil) {
		// INSERT
		NSString *sql = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)",
						 [[self class] tableName],
						 [columns componentsJoinedByString:@", "],
						 [placeholders componentsJoinedByString:@", "]];

		result = [db executeUpdate:sql withArgumentsInArray:values];

		if (result) {
			self.id = @([db lastInsertRowId]);
		}
	} else {
		// UPDATE
		NSMutableArray *setClauses = [NSMutableArray array];
		for (NSString *col in columns) {
			[setClauses addObject:[NSString stringWithFormat:@"%@ = ?", col]];
		}

		NSString *sql = [NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE %@ = ?",
						 [[self class] tableName],
						 [setClauses componentsJoinedByString:@", "],
						 [[self class] primaryKey]];

		NSMutableArray *allValues = [values mutableCopy];
		[allValues addObject:self.id];

		result = [db executeUpdate:sql withArgumentsInArray:allValues];
	}

	if (!result) {
		LogError(@"Failed to save %@: %@", [[self class] tableName], [db lastErrorMessage]);
	}

	return result;
}

- (BOOL)delete
{
	if (self.id == nil) return NO;

	FMDatabase *db = [[self class] database];
	if (!db) return NO;

	NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = ?",
					 [[self class] tableName], [[self class] primaryKey]];

	BOOL result = [db executeUpdate:sql, self.id];

	if (!result) {
		LogError(@"Failed to delete %@: %@", [[self class] tableName], [db lastErrorMessage]);
	}

	return result;
}

- (BOOL)reload
{
	if (self.id == nil) return NO;

	id obj = [[self class] findByPK:self.id];
	if (!obj) return NO;

	// Copy properties from reloaded object
	for (NSString *propName in [[self class] propertyNames]) {
		[self setValue:[obj valueForKey:propName] forKey:propName];
	}

	return YES;
}

#pragma mark - Query Methods

+ (nullable instancetype)findByPK:(id)primaryKeyValue
{
	return [self find:[self primaryKey] value:primaryKeyValue];
}

+ (nullable instancetype)find:(NSString *)property value:(id)value
{
	FMDatabase *db = [self database];
	if (!db) return nil;

	NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = ? LIMIT 1",
					 [self tableName], property];

	FMResultSet *rs = [db executeQuery:sql, value];

	if ([rs next]) {
		id obj = [self modelFromResultSet:rs];
		[rs close];
		return obj;
	}

	[rs close];
	return nil;
}

+ (NSArray *)findAll:(NSString *)property value:(id)value
{
	return [self where:[NSString stringWithFormat:@"%@ = ?", property] params:@[value]];
}

+ (NSArray *)all
{
	return [self where:nil params:nil];
}

+ (NSArray *)where:(NSString *)condition params:(nullable NSArray *)params
{
	return [self where:condition params:params orderBy:nil limit:0];
}

+ (NSArray *)where:(NSString *)condition params:(nullable NSArray *)params orderBy:(nullable NSString *)orderBy
{
	return [self where:condition params:params orderBy:orderBy limit:0];
}

+ (NSArray *)where:(NSString *)condition params:(nullable NSArray *)params orderBy:(nullable NSString *)orderBy limit:(NSInteger)limit
{
	FMDatabase *db = [self database];
	if (!db) return @[];

	NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT * FROM %@", [self tableName]];

	if (condition && condition.length > 0) {
		[sql appendFormat:@" WHERE %@", condition];
	}

	if (orderBy && orderBy.length > 0) {
		[sql appendFormat:@" ORDER BY %@", orderBy];
	}

	if (limit > 0) {
		[sql appendFormat:@" LIMIT %ld", (long)limit];
	}

	FMResultSet *rs = params ? [db executeQuery:sql withArgumentsInArray:params] : [db executeQuery:sql];

	NSMutableArray *results = [NSMutableArray array];
	while ([rs next]) {
		[results addObject:[self modelFromResultSet:rs]];
	}

	[rs close];
	return results;
}

+ (NSInteger)count
{
	return [self countWhere:nil params:nil];
}

+ (NSInteger)countWhere:(NSString *)condition params:(nullable NSArray *)params
{
	FMDatabase *db = [self database];
	if (!db) return 0;

	NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT COUNT(*) FROM %@", [self tableName]];

	if (condition && condition.length > 0) {
		[sql appendFormat:@" WHERE %@", condition];
	}

	FMResultSet *rs = params ? [db executeQuery:sql withArgumentsInArray:params] : [db executeQuery:sql];

	NSInteger count = 0;
	if ([rs next]) {
		count = [rs intForColumnIndex:0];
	}

	[rs close];
	return count;
}

#pragma mark - Schema Management

+ (BOOL)createTable
{
	FMDatabase *db = [self database];
	if (!db) return NO;

	NSString *sql = [self createTableSQL];
	BOOL result = [db executeUpdate:sql];

	if (!result) {
		LogError(@"Failed to create table %@: %@", [self tableName], [db lastErrorMessage]);
	}

	return result;
}

+ (BOOL)dropTable
{
	FMDatabase *db = [self database];
	if (!db) return NO;

	NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", [self tableName]];
	BOOL result = [db executeUpdate:sql];

	if (!result) {
		LogError(@"Failed to drop table %@: %@", [self tableName], [db lastErrorMessage]);
	}

	return result;
}

+ (BOOL)tableExists
{
	FMDatabase *db = [self database];
	if (!db) return NO;

	FMResultSet *rs = [db executeQuery:@"SELECT name FROM sqlite_master WHERE type='table' AND name=?", [self tableName]];
	BOOL exists = [rs next];
	[rs close];

	return exists;
}

#pragma mark - Helpers

+ (nullable instancetype)modelFromResultSet:(FMResultSet *)rs
{
	id model = [[self alloc] init];

	for (NSString *propName in [self propertyNames]) {
		NSString *type = [self propertyType:propName];
		id value = nil;

		if ([type isEqualToString:@"NSString"]) {
			value = [rs stringForColumn:propName];
		} else if ([type isEqualToString:@"NSNumber"] || [type isEqualToString:@"NSInteger"] || [type isEqualToString:@"BOOL"]) {
			if (![rs columnIsNull:propName]) {
				value = @([rs longLongIntForColumn:propName]);
			}
		} else if ([type isEqualToString:@"NSDate"]) {
			double timestamp = [rs doubleForColumn:propName];
			if (timestamp > 0) {
				value = [NSDate dateWithTimeIntervalSince1970:timestamp];
			}
		} else if ([type isEqualToString:@"NSData"]) {
			value = [rs dataForColumn:propName];
		} else if ([type isEqualToString:@"CGFloat"]) {
			value = @([rs doubleForColumn:propName]);
		}

		if (value) {
			[model setValue:value forKey:propName];
		}
	}

	return model;
}

- (id)databaseValueForProperty:(NSString *)propName value:(id)value
{
	if ([value isKindOfClass:[NSDate class]]) {
		return @([(NSDate *)value timeIntervalSince1970]);
	}

	return value;
}

- (NSDictionary *)toDictionary
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];

	for (NSString *propName in [[self class] propertyNames]) {
		id value = [self valueForKey:propName];
		if (value) {
			dict[propName] = value;
		}
	}

	return dict;
}

+ (nullable instancetype)fromDictionary:(NSDictionary *)dict
{
	id model = [[self alloc] init];

	for (NSString *key in dict) {
		@try {
			[model setValue:dict[key] forKey:key];
		}
		@catch (NSException *exception) {
			LogError(@"Failed to set property %@ on %@: %@", key, [self tableName], exception);
		}
	}

	return model;
}

- (NSDictionary *)dictionaryRepresentation
{
	// Alias for backwards compatibility
	return [self toDictionary];
}

#pragma mark - NSCoding

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	NSDictionary *dict = [self toDictionary];
	for (NSString *key in dict) {
		id value = dict[key];
		if (value && value != [NSNull null]) {
			[coder encodeObject:value forKey:key];
		}
	}
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self) {
		NSArray *properties = [self.class propertyNames];
		for (NSString *key in properties) {
			@try {
				id value = [coder decodeObjectForKey:key];
				if (value) {
					[self setValue:value forKey:key];
				}
			}
			@catch (NSException *exception) {
				LogError(@"Failed to decode property %@: %@", key, exception);
			}
		}
	}
	return self;
}

@end
