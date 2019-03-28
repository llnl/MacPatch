//
//  FMXDatabaseConfigration.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDatabase.h"

@class FMXModelRepository;

@interface FMXDatabaseConfiguration : NSObject

@property (strong, nonatomic) NSString *databasePath;
@property (strong, nonatomic) NSString *databasePathInDocuments;

- (id)initWithDatabasePath:(NSString *)databasePath;

- (FMDatabase *)database;

@end
