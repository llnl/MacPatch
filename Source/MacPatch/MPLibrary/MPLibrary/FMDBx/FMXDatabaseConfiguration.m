//
//  FMXDatabaseConfigration.m
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import "FMXDatabaseConfiguration.h"

@implementation FMXDatabaseConfiguration

/**
 *  Setup new database configuration with database path.
 *
 *  @param databasePath database path
 *  @return FMXDatabaseConfiguration instance.
 */
- (id)initWithDatabasePath:(NSString *)databasePath
{
    self = [super init];
    if (self) {
        NSFileManager *fm= [NSFileManager defaultManager];
        self.databasePath = databasePath;
        
#if TARGET_OS_IOS
        // Set a database file path in the documents directory.
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        self.databasePathInDocuments = [dir stringByAppendingPathComponent:databasePath];
        
        // Initialize database file.
        if (![fm fileExistsAtPath:self.databasePathInDocuments]) {
            // The database file is not found in the documents directory. Create empty database file.
            [fm createFileAtPath:self.databasePathInDocuments contents:nil attributes:nil];
            NSLog(@"[FMDBx] Create initial database file: %@", self.databasePathInDocuments);
        }
#elif defined TARGET_OS_OSX
        // Set database file path.
        self.databasePathInDocuments = databasePath;
        NSString *pathToDatabase = [databasePath stringByDeletingLastPathComponent];
        
        NSError *error = nil;
        if(![fm createDirectoryAtPath:pathToDatabase withIntermediateDirectories:YES attributes:nil error:&error]) {
            // An error has occurred, do something to handle it
            if (error) {
                NSLog(@"Failed to create directory \"%@\". Error: %@", pathToDatabase, error.localizedDescription);
            }
            
            // Set the default path to /Users/Shared, incase no user is logged in durring init
            self.databasePathInDocuments = [@"/Users/Shared" stringByAppendingPathComponent:[databasePath lastPathComponent]];
        }
        
        // Initialize database file.
        if (![fm fileExistsAtPath:self.databasePathInDocuments]) {
            // The database file is not found in the documents directory. Create empty database file.
            [fm createFileAtPath:self.databasePathInDocuments contents:nil attributes:nil];
            NSLog(@"[FMDBx] Create initial database file: %@", self.databasePathInDocuments);
        }
#endif
    }
    return self;
}

/**
 *  Get a FMDatabase instance.
 *
 *  @return FMDatabase instance.
 */
-(FMDatabase *)database {
    return [FMDatabase databaseWithPath:self.databasePathInDocuments];
}

@end
