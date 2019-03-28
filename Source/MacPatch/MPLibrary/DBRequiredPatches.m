//
//  DBRequiredPatches.m
//  MPLibrary
//
//  Created by Charles Heizer on 2/12/19.
//

#import "DBRequiredPatches.h"

@implementation DBRequiredPatches

+ (void)defaultTableMap:(FMXTableMap *)table
{
	[table setTableName:@"required_patches"];
	
	[table hasIntIncrementsColumn:@"id"];   // defines as a primary key.
	[table hasStringColumn:@"type"];
	[table hasStringColumn:@"patch_id"];
	[table hasStringColumn:@"patch"];
	[table hasStringColumn:@"patch_version"];
	[table hasIntColumn:@"patch_reboot"];
	[table hasDataColumn:@"patch_data"];
	[table hasDateColumn:@"patch_scandate"];
	
}

@end
