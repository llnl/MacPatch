//
//  MPDataMgr.m
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

#import "MPDataMgr.h"

#undef  ql_component
#define ql_component lcl_cMPDataMgr

@implementation MPDataMgr

#pragma mark - JSON DataMgr Code as String

- (NSString *)GenJSONForDataMgr:(NSArray *)aContent dbTable:(NSString *)aTable
{
	NSString *jsonString;
	jsonString = [self GenJSONForDataMgr:aContent
							   dbTable:aTable
						 dbTablePrefix:@"mpi_"
						 dbFieldPrefix:@"mpa_"
						  updateFields:@"cuuid"
							 deleteCol:@"NA"
						deleteColValue:@"NA"];
	return jsonString;
}

- (NSString *)GenJSONForDataMgr:(NSArray *)aContent dbTable:(NSString *)aTable
				 dbTablePrefix:(NSString *)aTablePrefix
{
	NSString *jsonString;
	jsonString = [self GenJSONForDataMgr:aContent
							   dbTable:aTable
						 dbTablePrefix:@"mpi_"
						 dbFieldPrefix:@"mpa_"
						  updateFields:@"cuuid"
							 deleteCol:@"NA"
						deleteColValue:@"NA"];
	return jsonString;
}

- (NSString *)GenJSONForDataMgr:(NSArray *)aContent dbTable:(NSString *)aTable
				 dbTablePrefix:(NSString *)aTablePrefix
				 dbFieldPrefix:(NSString *)aFieldPrefix
				  updateFields:(NSString *)aUpdateFields
{
	NSString *jsonString;
	jsonString = [self GenJSONForDataMgr:aContent
							   dbTable:aTable
						 dbTablePrefix:aTablePrefix
						 dbFieldPrefix:aFieldPrefix
						  updateFields:aUpdateFields
							 deleteCol:@"NA"
						deleteColValue:@"NA"];
	return jsonString;
}

- (NSString *)GenJSONForDataMgr:(NSArray *)aContent dbTable:(NSString *)aTable
				 dbTablePrefix:(NSString *)aTablePrefix
				 dbFieldPrefix:(NSString *)aFieldPrefix
{
	NSString *jsonString;
	jsonString = [self GenJSONForDataMgr:aContent
							   dbTable:aTable
						 dbTablePrefix:aTablePrefix
						 dbFieldPrefix:aFieldPrefix
						  updateFields:@"cuuid"
							 deleteCol:@"NA"
						deleteColValue:@"NA"];
	return jsonString;
}

- (NSString *)GenJSONForDataMgr:(NSArray *)aContent dbTable:(NSString *)aTable dbTablePrefix:(NSString *)aTablePrefix
				 dbFieldPrefix:(NSString *)aFieldPrefix
				  updateFields:(NSString *)aUpdateFields
					 deleteCol:(NSString *)aDelCol
				deleteColValue:(NSString *)aDelColVal
{
    NSDictionary *data = [self GenDataForDataMgr:aContent
                                         dbTable:aTable
                                   dbTablePrefix:aTablePrefix
                                   dbFieldPrefix:aFieldPrefix
                                    updateFields:aUpdateFields
                                       deleteCol:aDelCol
                                  deleteColValue:aDelColVal];
    
    
    // Create JSON String
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
    NSString *jsonString = nil;
    
    if (!jsonData) {
        qlerror(@"JSON Error: %@",error.localizedDescription);
    } else {
        jsonString = [[NSString alloc] initWithBytes:[jsonData bytes] length:[jsonData length] encoding:NSUTF8StringEncoding];
    }
    
    return jsonString;
    
}

#pragma mark - DataMgr as Data
- (NSDictionary *)GenDataForDataMgr:(NSArray *)aContent dbTable:(NSString *)aTable dbTablePrefix:(NSString *)aTablePrefix
                  dbFieldPrefix:(NSString *)aFieldPrefix
                   updateFields:(NSString *)aUpdateFields
                      deleteCol:(NSString *)aDelCol
                 deleteColValue:(NSString *)aDelColVal
{
    NSMutableDictionary *invDict = [[NSMutableDictionary alloc] init];
    // Set Key = cuuid
    NSString *_cuuid = [MPSystemInfo clientUUID];
    [invDict setObject:_cuuid forKey:@"key"];
    // Set Table Name
    [invDict setObject:[NSString stringWithFormat:@"%@%@",aTablePrefix,aTable] forKey:@"table"];
    
    if (aDelCol != NULL) {
        [invDict setObject:[NSNumber numberWithBool:NO] forKey:@"permanentRows"];
    } else {
        [invDict setObject:[NSNumber numberWithBool:YES] forKey:@"permanentRows"];
    }
    
    // Autofields, this will let the inv processor script add the schema required fields
    [invDict setObject:@"rid,cuuid,mdate" forKey:@"autoFields"];
    [invDict setObject:@"update" forKey:@"onexists"];
    [invDict setObject:@"rid,cuuid" forKey:@"checkFields"];
    
    NSMutableArray *fields = [[NSMutableArray alloc] init];
    /* Loop through the dictonary fields and build the table structure */
    /* We will use varchar column type for all data, with len of 255   */
    int i, x;
    if ([aContent count] > 0) {
        for (x = 0; x < [[[aContent objectAtIndex:0] allKeys] count]; x++)
        {
            [fields addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                               [NSString stringWithFormat:@"%@%@",aFieldPrefix,[[[aContent objectAtIndex:0] allKeys] objectAtIndex:x]],
                               @"name",@"varchar",@"dataType",@"255",@"length", nil]];
        }
    }
    [invDict setObject:[NSArray arrayWithArray:fields] forKey:@"fields"];
    
    /* start the data section, contains the rows */
    /* <tables><data><row>						 */
    
    // Now We Loop through the field values and add the rows
    NSDictionary *theDict;
    NSArray *theKeys;
    NSString *_dateTimeStamp = [MPDate dateTimeStamp];
    NSMutableArray *rows = [[NSMutableArray alloc] init];
    NSMutableDictionary *row;
    if ([aContent count] > 0)
    {
        for (i = 0; i < [aContent count]; i++)
        {
            row = [[NSMutableDictionary alloc] init];
            // Default Row Objects
            [row setObject:_cuuid forKey:@"cuuid"];
            [row setObject:_dateTimeStamp forKey:@"mdate"];
            
            theDict = [NSDictionary dictionaryWithDictionary:[aContent objectAtIndex:i]];
            theKeys = [NSArray arrayWithArray:[theDict allKeys]];
            
            for (x = 0; x < [theKeys count]; x++)
            {
                NSString *name = [NSString stringWithFormat:@"%@%@",aFieldPrefix,[theKeys objectAtIndex:x]];
                NSString *value;
                // C
                if ([[theDict valueForKey:[theKeys objectAtIndex:x]] isKindOfClass:[NSDate class]])
                {
                    value = [NSDate stringFromDate:[theDict valueForKey:[theKeys objectAtIndex:x]]];
                }
                else if ([[theDict valueForKey:[theKeys objectAtIndex:x]] isKindOfClass:[NSNumber class]])
                {
                    value = [[theDict valueForKey:[theKeys objectAtIndex:x]] stringValue];
                }
                else
                {
                    value = [[theDict valueForKey:[theKeys objectAtIndex:x]] stringByReplacingOccurrencesOfString:@" +0000" withString:@""];
                }
                
                [row setObject:value forKey:name];
            }
            [rows addObject:[NSDictionary dictionaryWithDictionary:row]];
        }
    }
    [invDict setObject:[NSArray arrayWithArray:rows] forKey:@"rows"];
    
    
    return (NSDictionary *)invDict;
}

@end
