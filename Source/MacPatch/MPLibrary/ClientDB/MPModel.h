//
//  MPModel.h
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

#import <Foundation/Foundation.h>
#import "FMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/**
 MPModel - Lightweight ORM base class for MacPatch

 Provides automatic CRUD operations with FMDB using Objective-C runtime
 for property introspection.

 Usage:
 @interface MyModel : MPModel
 @property (nonatomic, strong) NSString *name;
 @property (nonatomic, strong) NSNumber *age;
 @end

 // Save
 MyModel *obj = [MyModel new];
 obj.name = @"Test";
 [obj save];

 // Find
 MyModel *found = [MyModel find:@"uuid" value:@"12345"];
 NSArray *all = [MyModel all];

 // Delete
 [obj delete];
 */
@interface MPModel : NSObject <NSCoding, NSSecureCoding>

/// Primary key value (usually 'id')
@property (nonatomic, strong, nullable) NSNumber *id;

/// Database path (override in subclass if needed)
+ (NSString *)databasePath;

/// Table name (defaults to class name, override if different)
+ (NSString *)tableName;

/// Primary key column name (defaults to 'id')
+ (NSString *)primaryKey;

/// Columns to ignore during save/load (override to exclude properties)
+ (NSArray<NSString *> *)ignoredProperties;

#pragma mark - CRUD Operations

/// Save the model (INSERT if new, UPDATE if exists)
- (BOOL)save;

/// Delete the model from database
- (BOOL)delete;

/// Reload properties from database
- (BOOL)reload;

#pragma mark - Query Methods

/// Find by primary key
+ (nullable instancetype)findByPK:(id)primaryKeyValue;

/// Find first record matching property
+ (nullable instancetype)find:(NSString *)property value:(id)value;

/// Find all records matching property
+ (NSArray *)findAll:(NSString *)property value:(id)value;

/// Find all records
+ (NSArray *)all;

/// Find with custom WHERE clause
+ (NSArray *)where:(NSString *)condition params:(nullable NSArray *)params;

/// Find with custom WHERE clause and ORDER BY
+ (NSArray *)where:(NSString *)condition params:(nullable NSArray *)params orderBy:(nullable NSString *)orderBy;

/// Find with custom WHERE clause, ORDER BY, and LIMIT
+ (NSArray *)where:(NSString *)condition params:(nullable NSArray *)params orderBy:(nullable NSString *)orderBy limit:(NSInteger)limit;

/// Count all records
+ (NSInteger)count;

/// Count with WHERE clause
+ (NSInteger)countWhere:(NSString *)condition params:(nullable NSArray *)params;

#pragma mark - Schema Management

/// Create table if it doesn't exist (override to customize schema)
+ (BOOL)createTable;

/// Drop table
+ (BOOL)dropTable;

/// Check if table exists
+ (BOOL)tableExists;

#pragma mark - Database Access

/// Get database instance (manages connections)
+ (FMDatabase *)database;

/// Execute query with database (for custom queries)
+ (nullable id)executeQuery:(void(^)(FMDatabase *db))block;

#pragma mark - Utilities

/// Convert model to dictionary
- (NSDictionary *)toDictionary;

/// Alias for toDictionary (backwards compatibility)
- (NSDictionary *)dictionaryRepresentation;

/// Create model from dictionary
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
