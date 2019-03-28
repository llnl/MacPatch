//
//  MPInv.m
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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

#import "MPInv.h"
#import "NSDirectoryServices.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "CHDiskInfo.h"
#import "MPUsersAndGroups.h"
#import "MPFileVaultInfo.h"
#import <CommonCrypto/CommonDigest.h>
#import "BatteryInfo.h"
#import "PowerProfile.h"
#import "MPDirectoryServices.h"
#import "MacAppStoreDataItem.h"
#import "NSMetadataQuery+Synchronous.h"
#import "MPServerEntry.h"
#import "MPInventoryPlugin.h"
#import "InventoryPlugin.h"

#define kSP_DATA_Dir			@"/private/tmp/.mpData"
#define kSP_APP                 @"/usr/sbin/system_profiler"
#define kINV_SUPPORTED_TYPES	@"SPHardwareDataType,SPSoftwareDataType,SPNetworkDataType,SPApplicationsDataType,SPFrameworksDataType,DirectoryServices,InternetPlugins,AppUsage,ClientTasks,DiskInfo,Users,Groups,FileVault,PowerManagment,BatteryInfo,ConfigProfiles,SINetworkInfo,AppStoreApps,MPServerList,MPServerListInfo"
#define kTasksPlist             @"/Library/MacPatch/Client/.tasks/gov.llnl.mp.tasks.plist"
#define kInvHashData            @"/Library/MacPatch/Client/Data/.gov.llnl.mp.inv.data.plist"

#define LIBXML_SCHEMAS_ENABLED
#include <libxml/xmlschemastypes.h>

@interface MPInv ()

- (NSString *)hashForArray:(NSArray *)aArray;
- (BOOL)hasInvDataChanged:(NSString *)aInvType hash:(NSString *)aHash;
- (void)writeInvDataHashToFile:(NSString *)aInvType hash:(NSString *)aHash;

@end

@implementation MPInv

@synthesize invResults;
@synthesize cUUID;

#pragma mark -

- (id)init 
{
	self = [super init];
	if (self) {
		[self setCUUID:[MPSystemInfo clientUUID]];
	}	
	return self;
}
 
#pragma mark -

- (BOOL)hasInvDataInDB
{
    BOOL res = NO;
    NSError *err = nil;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    res = [mpws clientHasInvDataInDB:&err];
    if (err) {
        logit(lcl_vError,@"%@",err.localizedDescription);
        return NO;
    }

    return res;
}

- (int)postInvDataState
{
    int res = -1;
    NSError *err = nil;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    res = [mpws postClientHasInvData:&err];
    if (err) {
        logit(lcl_vError,@"%@",err.localizedDescription);
        return 1;
    }

    return res;
}

- (int)collectInventoryData
{
	return [self collectInventoryDataForType:@"All"];
}

- (int)collectCustomData
{
	return 0;
}

- (BOOL)validateCollectionType:(NSString *)aColType
{
	BOOL result = NO;
	NSArray *supportedTypes = [kINV_SUPPORTED_TYPES componentsSeparatedByString:@","];
	
	if ([supportedTypes indexOfObject:aColType] != NSNotFound)
		result=YES;
	
	return result;
}

- (int)collectInventoryDataForType:(NSString *)aSPType
{
    BOOL postCompleteInvData = NO;
	NSArray *invColTypes;
	if ([aSPType isEqual:@"All"])
    {
        // This is gathered incase a client has been deleted and the INV data needs to be repopluated
        postCompleteInvData = [self hasInvDataInDB];
        invColTypes = [kINV_SUPPORTED_TYPES componentsSeparatedByString:@","];
	} else {
		if ([self validateCollectionType:aSPType] == NO) {
			logit(lcl_vError,@"Inventory collection type %@ is not supported. Inventory will not run.",aSPType);
			return 1;
		}	
		invColTypes = [NSArray arrayWithObject:aSPType];
	}
    NSArray *invPlugins = nil;
    MPInventoryPlugin *mpip = [[MPInventoryPlugin alloc] init];
    invPlugins = [mpip loadPlugins];
    
    if (invPlugins) {
        for (NSDictionary *p in invPlugins)
        {
            InventoryPlugin *plugin = [p objectForKey:@"plugin"];
            if (!plugin) continue;
            [plugin setPluginName:[p objectForKey:@"pluginName"]];
            [plugin setPluginVersion:[p objectForKey:@"pluginVersion"]];
            NSDictionary *plugRes = [plugin runInventoryCollection];
            NSLog(@"%@",plugRes);
        }
    }
    
    return 0;
	
	
	
	NSMutableArray *resultsArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *result;
	NSError *err = nil;
	NSString *filePath = NULL;
    NSString *invType;
	int i = 0;
	for (i=0;i<[invColTypes count];i++)
	{
        // Multiple Types, PREFIX of SP is system profiler and SI sysinfocachegen
		logit(lcl_vInfo,@"Collecting inventory for type %@",[invColTypes objectAtIndex:i]);
        invType = [invColTypes objectAtIndex:i];
        if ([invType hasPrefix:@"SI"] == NO)
        {
            err = nil;
            filePath = [self getProfileData:[invColTypes objectAtIndex:i] error:&err];
            if (err) {
                logit(lcl_vError,@"Gathering inventory for data type %@",[invColTypes objectAtIndex:i]);
                continue;
            } else {
                result = [[NSMutableDictionary alloc] init];
                [result setObject:filePath forKey:@"file"];
                [result setObject:[invColTypes objectAtIndex:i] forKey:@"type"];

                // This needs to be cleaned up in the next release,

                if ([[invColTypes objectAtIndex:i] isEqual:@"SPSoftwareDataType"]) {
                    [result setObject:@"SPSystemOverview" forKey:@"wstype"];
                } else if ([[invColTypes objectAtIndex:i] isEqual:@"SPHardwareDataType"]) {
                    [result setObject:@"SPHardwareOverview" forKey:@"wstype"];
                } else {
                    [result setObject:[[invColTypes objectAtIndex:i] replace:@"DataType" replaceString:@""] forKey:@"wstype"];
                }
                
                [resultsArray addObject:result];
                result = nil;
            }
        } else if ([invType hasPrefix:@"SI"]) {
            if ([invType isEqualToString:@"SINetworkInfo"]) {
                NSArray *networkDataArray = [self getSysInfoGenDataForType:@"Mac_NetworkInterfaceElement" error:NULL];
                result = [[NSMutableDictionary alloc] init];
                [result setObject:[kSP_DATA_Dir stringByAppendingPathComponent:@"sysInfoGen.plist"] forKey:@"file"];
                [result setObject:networkDataArray forKey:@"data"];
                [result setObject:invType forKey:@"type"];
                [result setObject:@"SINetworkInfo" forKey:@"wstype"];
                [resultsArray addObject:result];
                result = nil;
            }
        }
	}
	
	NSFileManager *fm = [NSFileManager defaultManager];
	MPDataMgr	*dataMgr	= [[MPDataMgr alloc] init];
	NSDictionary *item;
	NSString *dataMgrJSON;
	NSArray *tmpArr = nil;
    NSString *invCollectionHash;
	
	for (i=0;i<[resultsArray count];i++)
	{
		item = [NSDictionary dictionaryWithDictionary:[resultsArray objectAtIndex:i]];
		if ([fm fileExistsAtPath:[item objectForKey:@"file"]]) {
			// Get Array Object, then gen DataMgr String
			if ([[item objectForKey:@"type"] isEqual:@"SPHardwareDataType"] ) {
				tmpArr = [self parseHardwareOverview:[item objectForKey:@"file"]];
			} else if ([[item objectForKey:@"type"] isEqual:@"SPSoftwareDataType"]) {
				tmpArr = [self parseSystemOverviewData:[item objectForKey:@"file"]];
			} else if ([[item objectForKey:@"type"] isEqual:@"SPNetworkDataType"]) {
				tmpArr = [self parseNetworkData:[item objectForKey:@"file"]];
			} else if ([[item objectForKey:@"type"] isEqual:@"SPApplicationsDataType"]) {
				tmpArr = [self parseApplicationsDataFromXML:[item objectForKey:@"file"]];
			} else if ([[item objectForKey:@"type"] isEqual:@"SPFrameworksDataType"]) {
				tmpArr = [self parseFrameworksDataFromXML:[item objectForKey:@"file"]];	
			} else if ([[item objectForKey:@"type"] isEqual:@"DirectoryServices"]) {	
				tmpArr = [self parseDirectoryServicesData];
			} else if ([[item objectForKey:@"type"] isEqual:@"InternetPlugins"]) {	
				tmpArr = [self parseInternetPlugins];
			} else if ([[item objectForKey:@"type"] isEqual:@"AppUsage"]) {	
				tmpArr = [self parseAppUsageData];
			} else if ([[item objectForKey:@"type"] isEqual:@"ClientTasks"]) {	
				tmpArr = [self parseLocalClientTasks];
			} else if ([[item objectForKey:@"type"] isEqual:@"DiskInfo"]) {	
				tmpArr = [self parseLocalDiskInfo];
			} else if ([[item objectForKey:@"type"] isEqual:@"Users"]) {	
				tmpArr = [self parseLocalUsers];
			} else if ([[item objectForKey:@"type"] isEqual:@"Groups"]) {
				tmpArr = [self parseLocalGroups];
			} else if ([[item objectForKey:@"type"] isEqual:@"FileVault"]) {
				tmpArr = [self parseFileVaultInfo];
			} else if ([[item objectForKey:@"type"] isEqual:@"PowerManagment"]) {
				tmpArr = [self parsePowerManagmentInfo];
			} else if ([[item objectForKey:@"type"] isEqual:@"BatteryInfo"]) {
				tmpArr = [self parseBatteryInfo];
			} else if ([[item objectForKey:@"type"] isEqual:@"ConfigProfiles"]) {
				tmpArr = [self parseConfigProfilesInfo];
			} else if ([[item objectForKey:@"type"] isEqual:@"SINetworkInfo"]) {
				tmpArr = [self parseSysInfoNetworkData:[item objectForKey:@"data"]];
			} else if ([[item objectForKey:@"type"] isEqual:@"AppStoreApps"]) {
				tmpArr = [self parseAppStoreData];
            } else if ([[item objectForKey:@"type"] isEqual:@"MPServerList"]) {
                tmpArr = [self parseAgentServerList];
            } else if ([[item objectForKey:@"type"] isEqual:@"MPServerListInfo"]) {
                tmpArr = [self parseAgentServerInfo];
            }

			if (tmpArr) {
                // Gen a hash for the inv results, if it has not changed dont post it.
                invCollectionHash = [self hashForArray:tmpArr];
                if ([self hasInvDataChanged:[item objectForKey:@"type"] hash:invCollectionHash] == NO) {
                    if (postCompleteInvData == NO) {
                        logit(lcl_vInfo,@"Results for %@ have not changed. No need to post.",[item objectForKey:@"type"]);
                        continue;
                    }
                }

				dataMgrJSON = [dataMgr GenJSONForDataMgr:tmpArr
											   dbTable:[item objectForKey:@"wstype"] 
										 dbTablePrefix:@"mpi_" 
										 dbFieldPrefix:@"mpa_"
										  updateFields:@"rid,cuuid"
											 deleteCol:@"cuuid"
										deleteColValue:[self cUUID]];

				if ([self sendResultsToWebService:dataMgrJSON]) {
					logit(lcl_vInfo,@"Results for %@ posted.",[item objectForKey:@"wstype"]);
                    [self writeInvDataHashToFile:[item objectForKey:@"type"] hash:invCollectionHash];
				} else {
					logit(lcl_vError,@"Results for %@ not posted.",[item objectForKey:@"wstype"]);
				}

                [dataMgrJSON writeToFile:[@"/private/tmp" stringByAppendingPathComponent:[item objectForKey:@"wstype"]] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                [self writeInvDataHashToFile:[item objectForKey:@"type"] hash:invCollectionHash];
				dataMgrJSON = NULL;
			}
		}
	}
	
	// Collect Audit Data
	if ([aSPType isEqual:@"All"]) {
		int x = 0;
		x = [self collectAuditTypeData];
	}
    // Post that INV data has been posted
    if (postCompleteInvData == NO)
    {
        [self postInvDataState];
    }
	return 0;
}

- (BOOL)sendResultsToWebService:(NSString *)aDataMgrXML
{
	BOOL result = NO;

	// Encode to base64 and send to web service
	//NSString	*cleanXMLString = [aDataMgrXML validXMLString];
    NSString    *b64String   = [[aDataMgrXML dataUsingEncoding:NSUTF8StringEncoding] base64Encoding];
	if (!b64String) {
		logit(lcl_vError,@"Unable to encode xml data.");
		return result;
	}

    MPWebServices *mpws = [[MPWebServices alloc] init];
    NSError *wsErr = nil;
    result = [mpws postDataMgrJSON:b64String error:&wsErr];
    if (wsErr) {
        logit(lcl_vError,@"Results posted to webservice returned false.");
        logit(lcl_vError,@"%@",wsErr.localizedDescription);
    } else {
        logit(lcl_vInfo,@"Results posted to webservice.");
        result = YES;
    }

	return result;
}

- (NSString *)getProfileData:(NSString *)profileType error:(NSError **)error
{	
	
	// SystemProfiler Output file Name
	NSString *spFileName;
	spFileName = [NSString stringWithFormat:@"%@.spx",profileType];
	
    NSTask *spTask = [[NSTask alloc] init];
    [spTask setLaunchPath: kSP_APP];
	
	// Should it be XML or Text
	if ([profileType isEqualToString:@"SPApplicationsDataType"] || [profileType isEqualToString:@"SPFrameworksDataType"]) {
		[spTask setArguments:[NSArray arrayWithObjects:profileType,@"-xml",nil]];
		spFileName = [NSString stringWithFormat:@"%@.plist",profileType];
	} else {
		[spTask setArguments:[NSArray arrayWithObjects:profileType,nil]];
	}
	
	NSFileManager *fm = [NSFileManager defaultManager];
	
	BOOL isDir;
	if (([fm fileExistsAtPath:kSP_DATA_Dir isDirectory:&isDir] && isDir) == NO) {
        [fm createDirectoryAtPath:kSP_DATA_Dir withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	
	if (![fm isWritableFileAtPath:kSP_DATA_Dir]) {
		logit(lcl_vError, @"Temp directory (%@) is not writable. Inventory will no get processed properly.",kSP_DATA_Dir);
	}
	
	// If File Exists then delete it
	if ([fm fileExistsAtPath:[kSP_DATA_Dir stringByAppendingPathComponent:spFileName] isDirectory:NO]) {
        [fm removeItemAtPath:[kSP_DATA_Dir stringByAppendingPathComponent:spFileName] error:NULL];
	}

	NSPipe *pipe;
    pipe = [NSPipe pipe];
    [spTask setStandardOutput: pipe];
	
	NSFileHandle *file;
    file = [pipe fileHandleForReading];
	
	[spTask launch];

	NSData *data = [file readDataToEndOfFile];
	
    NSString *string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
	logit(lcl_vInfo,@"Writing result to %@",[kSP_DATA_Dir stringByAppendingPathComponent:spFileName]);
	[string writeToFile:[kSP_DATA_Dir stringByAppendingPathComponent:spFileName] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	
	
	return [kSP_DATA_Dir stringByAppendingPathComponent:spFileName];
}

- (id)getSysInfoGenDataForType:(NSString *)aType error:(NSError **)error
{
	// SystemProfiler Output file Name
	NSString *spFileName = [kSP_DATA_Dir stringByAppendingPathComponent:@"sysInfoGen.plist"];

	NSFileManager *fm = [NSFileManager defaultManager];

	BOOL isDir;
	if (([fm fileExistsAtPath:kSP_DATA_Dir isDirectory:&isDir] && isDir) == NO) {
        [fm createDirectoryAtPath:kSP_DATA_Dir withIntermediateDirectories:YES attributes:nil error:NULL];
	}

	if (![fm isWritableFileAtPath:kSP_DATA_Dir]) {
		logit(lcl_vError, @"Temp directory (%@) is not writable. Inventory will no get processed properly.",kSP_DATA_Dir);
	}

	// If File Exists then delete it
	if ([fm fileExistsAtPath:spFileName isDirectory:NO]) {
        [fm removeItemAtPath:spFileName error:NULL];
	}

    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath:@"/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Support/sysinfocachegen"];

    NSArray *arguments;
    arguments = [NSArray arrayWithObjects:@"-p",spFileName,nil];
    [task setArguments: arguments];

    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];

    NSFileHandle *file;
    file = [pipe fileHandleForReading];

    [task launch];

    NSData *data;
    data = [file readDataToEndOfFile];

    NSString *string;
    string = [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding];
    qltrace(@"Completed running sysinfocachegen, %@",string);
    
	logit(lcl_vInfo,@"Writing result to %@",spFileName);
    NSDictionary *_data = [NSDictionary dictionaryWithContentsOfFile:spFileName];
    if ([_data objectForKey:@"Objects"]) {
        if ([[_data objectForKey:@"Objects"] objectForKey:aType]) {
            return [[_data objectForKey:@"Objects"] objectForKey:aType];
        } else {
            qlerror(@"%@ was not found in Objects",aType);
        }
    } else {
        qlerror(@"Objects object was not found sys info data.");
        return nil;
    }

    return nil;
}

#pragma mark -

- (int)collectAuditTypeData
{
	logit(lcl_vInfo,@"Collecting and processing audit files."); 
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableArray *files = [NSMutableArray array];
	NSString *thePath = [NSString pathWithComponents:[NSArray arrayWithObjects:MP_ROOT_CLIENT,@"Data",@"inv",nil]];
	NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:thePath];
	id file;
	while (file = [enumerator nextObject])
	{
		if ([[file pathExtension] isEqual:@"xml"])
		{
			// Do something with file.xml
			[files addObject:[thePath stringByAppendingPathComponent:file]];
		}
	}
	
	logit(lcl_vInfo,@"%d audit files found to process.",(int)[files count]);
	int i = 0;
	NSString *xmlText;
	for (i=0; i<[files count]; i++)
	{
		if ([self validateDataMgrXML:[files objectAtIndex:i]]) {
		 	xmlText = [self replaceXMLVariables:[files objectAtIndex:i]];
			if ([self sendResultsToWebService:xmlText]) {
				logit(lcl_vInfo,@"Results for %@ posted.",[[files objectAtIndex:i] lastPathComponent]);
                NSError *rmError = nil;
				[fm removeItemAtPath:[files objectAtIndex:i] error:&rmError];
                if (rmError) {
                    logit(lcl_vError,@"%@",[rmError localizedDescription]);
                }
			} else {
				logit(lcl_vError,@"Results for %@ not posted.",[[files objectAtIndex:i] lastPathComponent]);
			}
		}
	}

	return 0;	
}

- (NSString *)replaceXMLVariables:(NSString *)aFilePath
{
    NSString *tmpStr = NULL;
    tmpStr = [NSString stringWithContentsOfFile:aFilePath encoding:NSUTF8StringEncoding error:NULL];
    
    NSString *_chkFields = @"rid,cuuid";
    NSString *_length = @"255";
    NSString *_dataType = @"CF_SQL_VARCHAR";
    NSString *_mpColReq = @"<field Increment=\"true\" Length=\"11\" ColumnName=\"rid\" CF_DATATYPE=\"CF_SQL_INTEGER\" PrimaryKey=\"true\"></field> \
    <field ColumnName=\"cuuid\" Length=\"50\" CF_DATATYPE=\"CF_SQL_VARCHAR\"></field> \
    <field ColumnName=\"date\" Default=\"0000-00-00 00:00:00\" CF_DATATYPE=\"CF_SQL_DATE\"></field> \
    <field ColumnName=\"mdate\" Default=\"0000-00-00 00:00:00\" CF_DATATYPE=\"CF_SQL_DATE\"></field>";
	
    NSString *_mpColRowReq = @"<field name=\"cuuid\" value=\"$cuuid\"></field>\
    <field name=\"date\" value=\"$date\"></field>\
    <field name=\"mdate\" value=\"$date\"></field>";
    
	// Replace variables for table, cuuid and ,date
    tmpStr = [tmpStr replaceAll:@"<mpColReq />" replaceString:_mpColReq];
    tmpStr = [tmpStr replaceAll:@"<mpColRowReq />" replaceString:_mpColRowReq];
    tmpStr = [tmpStr replaceAll:@"$table" replaceString:[NSString stringWithFormat:@"mpi_%@",[[aFilePath lastPathComponent] stringByDeletingPathExtension]]];
    tmpStr = [tmpStr replaceAll:@"$cuuid" replaceString:[self cUUID]];
    tmpStr = [tmpStr replaceAll:@"$date" replaceString:[MPDate dateTimeStamp]];
    tmpStr = [tmpStr replaceAll:@"$mdate" replaceString:[MPDate dateTimeStamp]];
    tmpStr = [tmpStr replaceAll:@"$checkfields" replaceString:_chkFields];
    tmpStr = [tmpStr replaceAll:@"$length" replaceString:_length];
    tmpStr = [tmpStr replaceAll:@"$datatype" replaceString:_dataType];
	
    return tmpStr;
}

- (BOOL)validateDataMgrXML:(NSString *)aFilePath
{
    BOOL isValid = YES;
	if ([[NSFileManager defaultManager] fileExistsAtPath:aFilePath] == NO) {
		logit(lcl_vError,@"File (%@) to validate is missing.",aFilePath);
		return NO;
	}
    
    NSString *xsdFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mpAudit.xsd"];
    [MP_XSD_AUDIT writeToFile:xsdFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    
    xmlDocPtr doc;
    xmlSchemaPtr schema = NULL;
    xmlSchemaParserCtxtPtr ctxt;
    
    xmlLineNumbersDefault(1);
    
    ctxt = xmlSchemaNewParserCtxt([xsdFile UTF8String]);
    
    xmlSchemaSetParserErrors(ctxt, (xmlSchemaValidityErrorFunc) fprintf, (xmlSchemaValidityWarningFunc) fprintf, stderr);
    schema = xmlSchemaParse(ctxt);
    xmlSchemaFreeParserCtxt(ctxt);
    //xmlSchemaDump(stdout, schema); //To print schema dump
    
    doc = xmlReadFile([aFilePath UTF8String], NULL, 0);
    if (doc == NULL)
    {
        logit(lcl_vError,@"Could not parse XML file.");
        return NO;
    } else {
        xmlSchemaValidCtxtPtr ctxt;
        int ret;
        
        ctxt = xmlSchemaNewValidCtxt(schema);
        xmlSchemaSetValidErrors(ctxt, (xmlSchemaValidityErrorFunc) fprintf, (xmlSchemaValidityWarningFunc) fprintf, stderr);
        ret = xmlSchemaValidateDoc(ctxt, doc);
        if (ret == 0)
        {
            logit(lcl_vDebug,@"Valid Inventory XML file.");
        }
        else if (ret > 0)
        {
            logit(lcl_vError,@"Could not validate XML file.");
            isValid = NO;
        }
        else
        {
            logit(lcl_vError,@"Validation generated an internal error.");
            isValid = NO;
        }
        xmlSchemaFreeValidCtxt(ctxt);
        xmlFreeDoc(doc);
    }
    
    // free the resource
    if(schema != NULL)
        xmlSchemaFree(schema);
    
    xmlSchemaCleanupTypes();
    xmlCleanupParser();
    xmlMemoryDump();

	return isValid;
}

- (NSString *)hashForArray:(NSArray *)aArray
{
    NSString *err = nil;
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:aArray format:NSPropertyListBinaryFormat_v1_0 errorDescription:&err];
    if (err) {
        return @"ERROR";
    }

	unsigned char outputData[CC_MD5_DIGEST_LENGTH];
	CC_MD5([data bytes], (CC_LONG)[data length], outputData);

	NSMutableString *hashStr = [NSMutableString string];
	int i = 0;
	for (i = 0; i < CC_MD5_DIGEST_LENGTH; ++i)
    {
		[hashStr appendFormat:@"%02x", outputData[i]];
    }

	return (NSString *)hashStr;
}

- (BOOL)hasInvDataChanged:(NSString *)aInvType hash:(NSString *)aHash
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:kInvHashData]) {
        NSMutableDictionary *invData = [NSMutableDictionary dictionaryWithContentsOfFile:kInvHashData];
        if ([invData objectForKey:aInvType]) {
            if ([[[invData objectForKey:aInvType] lowercaseString] isEqualToString:[aHash lowercaseString]]) {
                return NO;
            } else {
                return YES;
            }
        } else {
            return YES;
        }
    } else {
        return YES;
    }
}

- (void)writeInvDataHashToFile:(NSString *)aInvType hash:(NSString *)aHash
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary *invData;
    if ([fm fileExistsAtPath:kInvHashData])
    {
        invData = [NSMutableDictionary dictionaryWithContentsOfFile:kInvHashData];
        [invData setObject:aHash forKey:aInvType];
        [invData writeToFile:kInvHashData atomically:YES];
    }
}

#pragma mark -

// Parse Profiler Data
- (NSArray *)parseHardwareOverview:(NSString *)fileToParse
{
	NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
	[d setObject:@"na" forKey:@"model_name"];
	[d setObject:@"na" forKey:@"model_identifier"];
	[d setObject:@"na" forKey:@"processor_name"];
	[d setObject:@"na" forKey:@"processor_speed"];
	[d setObject:@"na" forKey:@"number_of_processors"];
	[d setObject:@"na" forKey:@"total_number_of_cores"];
	[d setObject:@"na" forKey:@"l2_cache"];
	[d setObject:@"na" forKey:@"memory"];
	[d setObject:@"na" forKey:@"bus_speed"];
	[d setObject:@"na" forKey:@"boot_rom_version"];
	[d setObject:@"na" forKey:@"smc_version"];
	[d setObject:@"na" forKey:@"serial_number"];

	NSString *dataString = [[NSString alloc] initWithContentsOfFile:fileToParse encoding:NSUTF8StringEncoding error:NULL];
	NSArray *lines = [dataString componentsSeparatedByString:@"\n"];
	
	NSEnumerator *enumerator = [lines objectEnumerator];
	id obj;
	NSString *title;
	NSString *value;
	while (obj = [enumerator nextObject]) {
		if ([[obj trim] length] >=1)
		{
			title = NULL;
			value = NULL;
			if ([[obj trim] isEqual:@"Hardware:"] == NO)
			{
				if ([[obj trim] isEqual:@"Hardware Overview:"])
				{
					// Nothing
				} else if ([[obj trim] containsString:@"Number Of CPUs"]) {
					title = @"Number_Of_Processors";
					value = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim];
				} else if ([[obj trim] containsString:@"L2 Cache"]) {
					title = @"L2_Cache";
					value = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim];
				} else if ([[obj trim] containsString:@"(system):"]) {
					title = [[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:0];
					title = [[[title trim] replaceAll:@" " replaceString:@"_"] trim];
					title = [[[title trim] replaceAll:@"_(system)" replaceString:@""] trim];
					value = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim];
				} else {
					title = [[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:0];
					title = [[[title trim] replaceAll:@" " replaceString:@"_"] trim];
					value = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim];
				} // if, hardware overview
				
				if ([[title trim] length] > 2)
				{
					[d setObject:value forKey:[title lowercaseString]];
				} // if, title len
			} // if, Hardware 
		} // if, length
	} // end while

	NSDictionary *result = [NSDictionary dictionaryWithDictionary:d];
	return [NSArray arrayWithObject:result];
}

- (NSArray *)parseNetworkData:(NSString *)fileToParse
{
	NSMutableArray *networkData = [[NSMutableArray alloc] init];
	NSMutableDictionary *d = nil;
	
	// Read contents of the file...
	NSString *dataString = [[NSString alloc] initWithContentsOfFile:fileToParse encoding:NSUTF8StringEncoding error:NULL];
	
	// Parse by line endings and put in to an array
	NSArray *lines = [dataString componentsSeparatedByString:@"\n"];
	
	NSEnumerator *enumerator = [lines objectEnumerator];
	id obj;
	NSString *tmpTxt;
	NSString *tmpTxt2;
	NSString *title;
	NSString *value;
	NSString *valPrefix = @"";
	while (obj = [enumerator nextObject]) {
		if ([[obj trim] length] >=1)
		{
			if ([[obj trim] isEqual:@"Network:"] == NO)
			{
				if ([[obj midStartAt:4 end:1] isEqual:@" "] == NO)
				{						
					// Add entry 
					if (d) {
						[networkData addObject:d];
						d = nil;
					}
					
					d = [[NSMutableDictionary alloc] init];
					[d setObject:[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:0] forKey:@"name"];
					[d setObject:@"na" forKey:@"type"];
					[d setObject:@"na" forKey:@"hardware"];
					[d setObject:@"na" forKey:@"bsd_device_name"];
					[d setObject:@"na" forKey:@"has_ip_assigned"];
					[d setObject:@"na" forKey:@"ipv4_addresses"];
					[d setObject:@"na" forKey:@"ipv4_configuration_method"];
					[d setObject:@"na" forKey:@"ipv4_interface_name"];
					[d setObject:@"na" forKey:@"ipv4_networksignature"];
					[d setObject:@"na" forKey:@"ipv4_router"];
					[d setObject:@"na" forKey:@"ipv4_subnet_masks"];
					[d setObject:@"na" forKey:@"appletalk_configuration_method"];
					[d setObject:@"na" forKey:@"appletalk_default_zone"];
					[d setObject:@"na" forKey:@"appletalk_interface_name"];
					[d setObject:@"na" forKey:@"appletalk_network_id"];
					[d setObject:@"na" forKey:@"appletalk_node_id"];
					[d setObject:@"na" forKey:@"dns_search_domains"];
					[d setObject:@"na" forKey:@"dns_server_addresses"];
					[d setObject:@"na" forKey:@"proxies_exceptions_list"];
					[d setObject:@"na" forKey:@"proxies_ftp_passive_mode"];
					[d setObject:@"na" forKey:@"proxies_http_proxy_enabled"];
					[d setObject:@"na" forKey:@"proxies_http_proxy_port"];
					[d setObject:@"na" forKey:@"proxies_http_proxy_server"];
					[d setObject:@"na" forKey:@"ethernet_mac_address"];
					[d setObject:@"na" forKey:@"ethernet_media_options"];
					[d setObject:@"na" forKey:@"ethernet_media_subtype"];
				} else {
					if ([[[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim] length] == 0) {
						// Set the valPrefix
						tmpTxt2 = [[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:0];
						if ([tmpTxt2 isEqual:@"IPv4"] || [tmpTxt2 isEqual:@"DHCP Server Responses"] || [tmpTxt2 isEqual:@"AirPort"] || [tmpTxt2 isEqual:@"AppleTalk"] || [tmpTxt2 isEqual:@"DNS"] || [tmpTxt2 isEqual:@"Proxies"] || [tmpTxt2 isEqual:@"Ethernet"] ) {
							if ([tmpTxt2 isEqual:@"DHCP Server Responses"])
								tmpTxt2 = @"DHCP";
							valPrefix = [NSString stringWithFormat:@"%@_",tmpTxt2];
						} else {
							valPrefix = @"";
						}
					} else {
						title = NULL;
						value = NULL;
						tmpTxt = [[obj trim] replace:@":" replaceString:@"^"];
						title = [[[tmpTxt componentsSeparatedByString:@"^"] objectAtIndex:0] replaceAll:@" " replaceString:@"_"];
						title = [title replaceAll:@"(" replaceString:@""];
						title = [title replaceAll:@")" replaceString:@""];
						title = [NSString stringWithFormat:@"%@%@",valPrefix,[title lowercaseString]];
						value = [[[tmpTxt componentsSeparatedByString:@"^"] objectAtIndex:1] trim];
						value = [value replaceAll:@"(" replaceString:@""];
						value = [value replaceAll:@")" replaceString:@""];
						[d setObject:value forKey:[title lowercaseString]];
					}
				} // if, mid
			} // if, Network 
		} // if, length
	} // end while
	
	// Add the last record
	if (d) {
		[networkData addObject:d];
		d = nil;
	}
	NSArray *result = nil;
	if (networkData)
		result = [NSArray arrayWithArray:networkData];
	
	return result;
}

- (NSArray *)parseSystemOverviewData:(NSString *)fileToParse
{
	NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
	[d setObject:@"NA" forKey:@"name"];
	[d setObject:@"NA" forKey:@"system_version"];
	[d setObject:@"NA" forKey:@"kernel_version"];
	[d setObject:@"NA" forKey:@"boot_volume"];
	[d setObject:@"NA" forKey:@"boot_mode"];
	[d setObject:@"NA" forKey:@"computer_name"];
	[d setObject:@"NA" forKey:@"user_name"];
	[d setObject:@"NA" forKey:@"time_since_boot"];
	
	
	NSString *dataString = [[NSString alloc] initWithContentsOfFile:fileToParse encoding:NSUTF8StringEncoding error:NULL];
	NSArray *lines = [dataString componentsSeparatedByString:@"\n"];
	
	NSEnumerator *enumerator = [lines objectEnumerator];
	id obj;
	NSString *title = @"";
	NSString *value = @"";
	while (obj = [enumerator nextObject]) {
		if ([[obj trim] length] >=1)
		{
			if ([[obj trim] isEqual:@"Software:"] == NO)
			{
				if ([[obj trim] isEqual:@"System Software Overview:"])
				{
					title = @"Name";
					value = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim];
				} else {
					title = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:0] trim];
					title = [[[title trim] replaceAll:@" " replaceString:@"_"] trim];
					value = [[[[obj trim] componentsSeparatedByString:@":"] objectAtIndex:1] trim];
				} // if, Software overview
				
				if ([[title trim] length] > 2)
				{
					[d setObject:value forKey:[title lowercaseString]];
				} // if, title len
			} // if, Software 
		} // if, length
	} // end while
	
	NSDictionary *result = [NSDictionary dictionaryWithDictionary:d];
	return [NSArray arrayWithObject:result];
}

- (NSArray *)parseApplicationsDataFromXML:(NSString *)xmlFileToParse
{
	NSArray *result = nil;
	NSFileManager *dm = [NSFileManager defaultManager];
	if ([dm fileExistsAtPath:xmlFileToParse] == NO)
	{
		logit(lcl_vError,@"Inventory cache file was not found. Data will not be parsed.");
		return result;
	}
	
	NSArray *spX = [NSArray arrayWithContentsOfFile:xmlFileToParse];
	NSDictionary *rootDict = [spX objectAtIndex:0];
 	NSArray *itemsArray = [rootDict objectForKey:@"_items"];
	
	NSArray *tmpKeys = [NSArray arrayWithObjects:@"Version",@"Last_Modified",@"Kind",@"Get_Info_String",@"Location",nil];
	NSArray *tmpObj = [NSArray arrayWithObjects:@"NA",@"NA",@"NA",@"NA",@"NA",nil];
	NSDictionary *tmpDict = [NSDictionary dictionaryWithObjects:tmpObj forKeys:tmpKeys];
	
	NSMutableArray *newItemsArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *rec;
	NSDictionary *curItem;
	int i = 0;
	for (i=0;i<[itemsArray count];i++)
	{
		curItem = [itemsArray objectAtIndex:i];
		rec = [[NSMutableDictionary alloc] initWithDictionary:tmpDict];

		if ([[curItem allKeys] containsObject:@"_name"]) {
			[rec setObject:[curItem objectForKey:@"_name"] forKey:@"Name"];
		}	
		if ([[curItem allKeys] containsObject:@"version"]) {
			[rec setObject:[curItem objectForKey:@"version"] forKey:@"Version"];
		}	
		if ([[curItem allKeys] containsObject:@"lastModified"]) {
			[rec setObject:[curItem objectForKey:@"lastModified"] forKey:@"Last_Modified"];
		}	
		if ([[curItem allKeys] containsObject:@"runtime_environment"]) {
			[rec setObject:[curItem objectForKey:@"runtime_environment"] forKey:@"Kind"];
		}	
		if ([[curItem allKeys] containsObject:@"path"]) {
			[rec setObject:[curItem objectForKey:@"path"] forKey:@"Location"];
		}	
		
		[newItemsArray addObject:rec];
		rec = nil;
	}
	
	result = [NSArray arrayWithArray:newItemsArray];
	return result;	
}

- (NSArray *)parseFrameworksDataFromXML:(NSString *)xmlFileToParse
{
	NSArray *result = nil;
	NSFileManager *dm = [NSFileManager defaultManager];
	if ([dm fileExistsAtPath:xmlFileToParse] == NO)
	{
		logit(lcl_vError,@"Inventory cache file was not found. Data will not be parsed.");
		return result;
	}
	/*
	 <dict>
		 <key>_name</key>
		 <key>has64BitIntelCode</key>
		 <key>info</key>
		 <key>lastModified</key>
		 <key>path</key>
		 <key>private_framework</key>
		 <key>runtime_environment</key>
		 <key>version</key>
	 </dict>
	*/	
	
	NSArray *spX = [NSArray arrayWithContentsOfFile:xmlFileToParse];
	NSDictionary *rootDict = [spX objectAtIndex:0];
 	NSArray *itemsArray = [rootDict objectForKey:@"_items"];
	
	NSArray *tmpKeys = [NSArray arrayWithObjects:@"Name",@"has64BitIntelCode",@"lastModified",@"Location",@"Private_Framework",@"Kind",@"Version",nil];
	NSArray *tmpObj = [NSArray arrayWithObjects:@"NA",@"NA",@"NA",@"NA",@"NA",@"NA",@"NA",nil];
	NSDictionary *tmpDict = [NSDictionary dictionaryWithObjects:tmpObj forKeys:tmpKeys];
	
	NSMutableArray *newItemsArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *rec;
	NSDictionary *curItem;
	int i = 0;
	for (i=0;i<[itemsArray count];i++)
	{
		curItem = [itemsArray objectAtIndex:i];
		rec = [[NSMutableDictionary alloc] initWithDictionary:tmpDict];

		if ([[curItem allKeys] containsObject:@"_name"]) {
			[rec setObject:[curItem objectForKey:@"_name"] forKey:@"Name"];
		}	
		if ([[curItem allKeys] containsObject:@"version"]) {
			[rec setObject:[curItem objectForKey:@"version"] forKey:@"Version"];
		}	
		if ([[curItem allKeys] containsObject:@"lastModified"]) {
			[rec setObject:[curItem objectForKey:@"lastModified"] forKey:@"lastModified"];
		}	
		if ([[curItem allKeys] containsObject:@"runtime_environment"]) {
			[rec setObject:[curItem objectForKey:@"runtime_environment"] forKey:@"Kind"];
		}	
		if ([[curItem allKeys] containsObject:@"private_framework"]) {
			[rec setObject:[curItem objectForKey:@"private_framework"] forKey:@"Private_Framework"];
		}	
		if ([[curItem allKeys] containsObject:@"path"]) {
			[rec setObject:[curItem objectForKey:@"path"] forKey:@"Location"];
		}	
		if ([[curItem allKeys] containsObject:@"has64BitIntelCode"]) {
			[rec setObject:[curItem objectForKey:@"has64BitIntelCode"] forKey:@"has64BitIntelCode"];
		}	
		
		[newItemsArray addObject:rec];
		rec = nil;
	}
	
	result = [NSArray arrayWithArray:newItemsArray];
	
	return result;	
}

- (NSArray *)parseApplicationsData:(NSString *)fileToParse
{
	NSMutableArray *applicationData = [[NSMutableArray alloc] init];
	NSMutableDictionary *d = nil;
	
	// Read contents of the file...
	NSString *dataString = [[NSString alloc] initWithContentsOfFile:fileToParse encoding:NSUTF8StringEncoding error:NULL];
	
	// This is done to remove unicode chars
	NSData *asciiData = [dataString dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	
	NSString *asciiString = [[NSString alloc] initWithData:asciiData encoding:NSASCIIStringEncoding];
	
	// Parse by line endings and put in to an array
	NSArray *lines = [asciiString componentsSeparatedByString:@"\n"];
	
	NSString *nextVal;
	NSString *nValue;
	NSString *line = @"";
	
	int i = 0;
	int l = 0;
	for (i = 0;i < [lines count]; i++)
	{
		line = [NSString stringWithString:[[lines objectAtIndex:i] trim]];
		if ([line length] >=1)
		{
			if ([[line componentsSeparatedByString:@":"] count] > 1 && [[[[line componentsSeparatedByString:@":"] objectAtIndex:1] trim] length] == 0)
			{
				if ([line isEqual:@"Applications:"] == NO && [line containsString:@":"] == YES)
				{
					@try 
					{
						d = [[NSMutableDictionary alloc] init];
						[d setObject:[[line componentsSeparatedByString:@":"] objectAtIndex:0] forKey:@"name"];
						[d setObject:@"NA" forKey:@"version"];
						[d setObject:@"NA" forKey:@"last_modified"];
						[d setObject:@"NA" forKey:@"kind"];
						[d setObject:@"NA" forKey:@"get_info_string"];
						[d setObject:@"NA" forKey:@"location"];
						
						for (l = (i+1);l < (i+16); l++)
						{	
							nextVal = @"";
							//First Make Sure the line has a : to Separate the attr title
							if ([line containsString:@":"])
							{
								// Replace the Title delimiter with a new Charater so that Date & Time shows right
								nValue = [[[lines objectAtIndex:l] trim] replace:@":" replaceString:@"^"];
								// ----------------------------------------
								// Look for data that matches the defined
								// attributes using if and In string exists
								// ----------------------------------------
								if ([[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:0] trim] containsString:@"Version"]) {
									// If next line is true, add it to the current line
									if ([[lines objectAtIndex:(l+1)] containsString:@":"]) {
										nextVal = [NSString stringWithString:[lines objectAtIndex:(l+1)]];
									}
									[d setObject:[NSString stringWithFormat:@"%@%@",[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:1] trim], nextVal] forKey:@"version"];
									
								} else if ([[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:0] trim] containsString:@"Last Modified"]) {
									// If next line is true, add it to the current line
									if ([[lines objectAtIndex:(l+1)] containsString:@":"]) {
										nextVal = [NSString stringWithString:[lines objectAtIndex:(l+1)]];
									}
									[d setObject:[NSString stringWithFormat:@"%@%@",[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:1] trim], nextVal] forKey:@"last_modified"];
									
								} else if ([[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:0] trim] containsString:@"Kind"]) {
									// If next line is true, add it to the current line
									if ([[lines objectAtIndex:(l+1)] containsString:@":"]) {
										nextVal = [NSString stringWithString:[lines objectAtIndex:(l+1)]];
									}
									[d setObject:[NSString stringWithFormat:@"%@%@",[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:1] trim], nextVal] forKey:@"kind"];
									
								} else if ([[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:0] trim] containsString:@"Get Info String"]) {
									// If next line is true, add it to the current line
									if ([[lines objectAtIndex:(l+1)] containsString:@":"]) {
										nextVal = [NSString stringWithString:[lines objectAtIndex:(l+1)]];
									}
									[d setObject:[NSString stringWithFormat:@"%@%@",[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:1] trim], nextVal] forKey:@"get_info_string"];
									
								} else if ([[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:0] trim] containsString:@"Location"]) {
									// If next line is true, add it to the current line
									if ([[lines objectAtIndex:(l+1)] containsString:@":"]) {
										nextVal = [NSString stringWithString:[lines objectAtIndex:(l+1)]];
									}
									[d setObject:[NSString stringWithFormat:@"%@%@",[[[nValue componentsSeparatedByString:@"^"] objectAtIndex:1] trim], nextVal] forKey:@"location"];
									break;
								} // Attributes if
							} // if line contains :
						} // for loop
						[applicationData addObject:d];
						d = nil;
					}	
					@catch (NSException * e) {
						logit(lcl_vError,@"Error: %@",[e description]);
						d = nil;
					}
				}
			}
		}
	}
	
	
	NSArray *result = [NSArray arrayWithArray:applicationData];
	return result;
}

- (NSDictionary *)emptyDirectoryServicesDataRecord
{
	NSDictionary *result = nil;
	NSMutableDictionary *record = [[NSMutableDictionary alloc] init];
	[record setObject:@"NA" forKey:@"distinguishedName"];
	[record setObject:@"NA" forKey:@"cn"];
	[record setObject:@"NA" forKey:@"DNSName"];
	[record setObject:@"NA" forKey:@"ADDomain"];
	[record setObject:@"0" forKey:@"HasSLAM"];
	[record setObject:@"NA" forKey:@"AD_Computer_ID"];
	[record setObject:@"NA" forKey:@"AD_Kerberos_ID"];
	[record setObject:@"0" forKey:@"Bound_To_Domain"];
	result = [NSDictionary dictionaryWithDictionary:record];
	return result;
}

- (NSArray *)parseDirectoryServicesData
{	
	NSDictionary *osVerInfo = [MPSystemInfo osVersionOctets];
	if ([[osVerInfo objectForKey:@"minor"] intValue] <= 6) {
		logit(lcl_vDebug,@"parseDirectoryServicesData <= 6");
		return [self parseDirectoryServicesDataForPreLion];
	}
	if ([[osVerInfo objectForKey:@"minor"] intValue] >= 7) {
		logit(lcl_vDebug,@"parseDirectoryServicesData >= 7");
		return [self parseDirectoryServicesDataForLion];
	}
	
	logit(lcl_vError,@"parseDirectoryServicesData, did not figure out os version for parsing.");
	return nil;
}

- (NSArray *)parseDirectoryServicesDataForLion
{
	NSArray *result;
	NSMutableDictionary *record = [[NSMutableDictionary alloc] initWithDictionary:[self emptyDirectoryServicesDataRecord]];
	
	@try {
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *dirPath = @"/Library/Preferences/OpenDirectory/Configurations/Active Directory";
		NSArray *dirContents = [fm contentsOfDirectoryAtPath:dirPath error:NULL];
		if ([dirContents count] >= 1) {
			[record setObject:@"1" forKey:@"Bound_To_Domain"];
		}
		NSString *adPlist = [NSString stringWithFormat:@"%@/%@",dirPath,[dirContents objectAtIndex:0]];
		if (![fm fileExistsAtPath:adPlist])
			goto done;
		NSDictionary *adInfo = [NSDictionary dictionaryWithContentsOfFile:adPlist];
        if (!adInfo) {
            NSHost *_host = [NSHost currentHost];
            adInfo = [NSDictionary dictionaryWithObjectsAndKeys:[[_host localizedName] stringByAppendingString:@"$"],@"trustaccount",@"NA",@"AD_Kerberos_ID",@"NA",@"ADDomain",nil];
        }

		// Computer Name
		if ([[adInfo allKeys] containsObject:@"trustaccount"]) {
			[record setObject:[adInfo objectForKey:@"trustaccount"] forKey:@"AD_Computer_ID"];
		}
		// Kerbname
		if ([[adInfo allKeys] containsObject:@"trustkerberosprincipal"]) {
			[record setObject:[adInfo objectForKey:@"trustkerberosprincipal"] forKey:@"AD_Kerberos_ID"];
		}
		// AD Domain Name
		if ([[adInfo allKeys] containsObject:@"module options"]) {
			if ([[[adInfo objectForKey:@"module options"] allKeys] containsObject:@"ActiveDirectory"]) {
				if ([[[[adInfo objectForKey:@"module options"] objectForKey:@"ActiveDirectory"] allKeys] containsObject:@"domain"]) {	
					[record setObject:[[[adInfo objectForKey:@"module options"] objectForKey:@"ActiveDirectory"] objectForKey:@"domain"] forKey:@"ADDomain"];
				}	
			}	
		}	
			
		/* Old Way  */
		NSDirectoryServices *dsSearch = [[NSDirectoryServices alloc] init];
		NSDictionary *computerAccountInfo = [dsSearch getRecord:[adInfo objectForKey:@"trustaccount"] ofType:DHDSComputerAccountType fromNode:DHDSSEARCHNODE];
		
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:distinguishedName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:distinguishedName"] forKey:@"distinguishedName"];
		} else {
            if ([computerAccountInfo objectForKey:@"dsAttrTypeStandard:AppleMetaRecordName"]) {
                [record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeStandard:AppleMetaRecordName"] forKey:@"distinguishedName"];
            } else {
                [record setObject:@"NA" forKey:@"distinguishedName"];
            }
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:cn"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:cn"] forKey:@"cn"];
		} else {
            if ([computerAccountInfo objectForKey:@"dsAttrTypeStandard:RealName"]) {
                [record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeStandard:RealName"] forKey:@"cn"];
            } else {
                [record setObject:@"NA" forKey:@"cn"];
            }
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:DNSName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:DNSName"] forKey:@"DNSName"];
		} else {
            if ([computerAccountInfo objectForKey:@"dsAttrTypeStandard:DNSName"]) {
                [record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeStandard:DNSName"] forKey:@"DNSName"];
            } else {
                [record setObject:@"NA" forKey:@"DNSName"];
            }
		}
		
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:llnlHosts"]) {
			if ([[computerAccountInfo objectForKey:@"dsAttrTypeNative:llnlHosts"] count] > 0) {
				[record setObject:@"1" forKey:@"HasSLAM"];	
			}
		} else {
			[record setObject:@"0" forKey:@"HasSLAM"];	
		}

        /* New Way, not working yet
        MPDirectoryServices *mpds = [[MPDirectoryServices alloc] init];
		NSDictionary *computerAccountInfo = [mpds computerInfo:[adInfo objectForKey:@"trustaccount"]];

		if ([computerAccountInfo objectForKey:@"dsAttrTypeStandard:AppleMetaRecordName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeStandard:AppleMetaRecordName"] forKey:@"distinguishedName"];
		} else {
			[record setObject:@"NA" forKey:@"distinguishedName"];
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeStandard:RealName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeStandard:RealName"] forKey:@"cn"];
		} else {
			[record setObject:@"NA" forKey:@"cn"];
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeStandard:DNSName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeStandard:DNSName"] forKey:@"DNSName"];
		} else {
			[record setObject:@"NA" forKey:@"DNSName"];
		}

		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:llnlHosts"]) {
			if ([[computerAccountInfo objectForKey:@"dsAttrTypeNative:llnlHosts"] count] > 0) {
				[record setObject:@"1" forKey:@"HasSLAM"];
			}
		} else {
			[record setObject:@"0" forKey:@"HasSLAM"];
		}
         */
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"%@",[e description]);
	}	

done:	
	logit(lcl_vDebug,@"%@",record);
	result = [NSArray arrayWithObject:record];
	return result;	
}

- (NSArray *)parseDirectoryServicesDataForPreLion
{
	NSArray *result;
	NSDictionary *adPlist;
	NSMutableDictionary *record = [[NSMutableDictionary alloc] initWithDictionary:[self emptyDirectoryServicesDataRecord]];
	NSString *computerName = @"NA";
	
	@try {
		if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Library/Preferences/DirectoryService/ActiveDirectory.plist"] == NO) 
			goto done;
		
		// Will need to change for 10.7 support
		
		adPlist = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/DirectoryService/ActiveDirectory.plist"];
		// Is Bound
		if ([[adPlist allKeys] containsObject:@"AD Bound to Domain"]) {
			if ([[adPlist valueForKey:@"AD Bound to Domain"] boolValue] == TRUE) {
				[record setObject:@"1" forKey:@"Bound_To_Domain"];
			} else {
				goto done;
			}
		}
		// Computer Name
		if ([[adPlist allKeys] containsObject:@"AD Computer ID"]) {
			computerName = [NSString stringWithString:[adPlist objectForKey:@"AD Computer ID"]];
			[record setObject:computerName forKey:@"AD_Computer_ID"];
		}
		// Kerbname
		if ([[adPlist allKeys] containsObject:@"AD Computer Kerberos ID"]) {
			[record setObject:[adPlist objectForKey:@"AD Computer Kerberos ID"] forKey:@"AD_Kerberos_ID"];
		}
		
		NSDirectoryServices *dsSearch = [[NSDirectoryServices alloc] init];
		NSDictionary *computerAccountInfo = [dsSearch getRecord:computerName ofType:DHDSComputerAccountType fromNode:DHDSSEARCHNODE];
		
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:distinguishedName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:distinguishedName"] forKey:@"distinguishedName"];
		} else {
			[record setObject:@"NA" forKey:@"distinguishedName"];
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:cn"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:cn"] forKey:@"cn"];
		} else {
			[record setObject:@"NA" forKey:@"cn"];
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:DNSName"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:DNSName"] forKey:@"DNSName"];
		} else {
			[record setObject:@"NA" forKey:@"DNSName"];
		}
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:ADDomain"]) {
			[record setObject:[computerAccountInfo objectForKey:@"dsAttrTypeNative:ADDomain"] forKey:@"ADDomain"];
		} else {
			[record setObject:@"NA" forKey:@"ADDomain"];
		}
		
		if ([computerAccountInfo objectForKey:@"dsAttrTypeNative:llnlHosts"]) {
			if ([[computerAccountInfo objectForKey:@"dsAttrTypeNative:llnlHosts"] count] > 0) {
				[record setObject:@"1" forKey:@"HasSLAM"];	
			}
		} else {
			[record setObject:@"0" forKey:@"HasSLAM"];	
		}
		
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"%@",[e description]);
	}		
	
done:
	logit(lcl_vDebug,@"%@",record);
	result = [NSArray arrayWithObject:record];
	return result;
}

- (NSArray *)parseAppUsageData
{
	logit(lcl_vInfo, @"Begin parsing application usage data.");
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *appSupportDir = @"/Library/Application Support/MPClientStatus";
	NSString *appDB = [appSupportDir stringByAppendingPathComponent:@"mpapp.db"];
	
	if ([fm fileExistsAtPath:appSupportDir] == NO) {
		logit(lcl_vInfo, @"No application usage data to parse.");
		return nil;
	}
	
	if ([fm fileExistsAtPath:appDB] == NO) {
		logit(lcl_vError, @"Application usage data is missing.");
		return nil;
	}
	NSMutableArray *rows = [[NSMutableArray alloc] init];
	NSMutableDictionary *_rec = nil;
	NSArray *columns = [NSArray arrayWithObjects:@"app_name",@"app_path",@"app_version",@"last_launched",@"times_launched",nil];
	FMDatabase *db = [FMDatabase databaseWithPath:appDB];
	if (![db open]) {
        logit(lcl_vError,@"Could not open app usage data file.");
        return nil;
    }
	FMResultSet *rs = [db executeQuery:@"select app_name,app_path,app_version,last_launched,times_launched from appUsage"];
    while ([rs next]) {
		_rec = [[NSMutableDictionary alloc] init];
		for (id col in columns) {
			if ([rs stringForColumn:col]) {
				[_rec setObject:[rs stringForColumn:col] forKey:col];
			} else {
				[_rec setObject:@"" forKey:col];
			}
		}
		logit(lcl_vDebug, @"App Usage Row: %@",_rec);
		[rows addObject:_rec];
		_rec = nil;
    }
    // close the result set.
    // it'll also close when it's dealloc'd, but we're closing the database before
    // the autorelease pool closes, so sqlite will complain about it.
    [rs close]; 
	[db close];
	NSArray *results = [NSArray arrayWithArray:rows];
	rows = nil;
	logit(lcl_vDebug, @"App Usage results: %@",results);
	return results;
}

- (NSArray *)parseInternetPlugins
{
	/*
	 *	Locations
	 *	/Library/Internet Plug-Ins
	 *	/System/Library/Internet Plug-Ins
	 *	~/Library/Internet Plug-Ins
	*/ 
	/*
	 *	Data Struct 
		<dict>
			<key>name</key>
			<key>path</key>
			<key>path_real</key>
			<key>version</key>
			<key>lastModified</key>
			<key>WebPluginName</key>
			<key>BundleIdentifier</key>
		</dict>
	*/
	NSArray *plugins = nil;
	NSFileManager *fm = [NSFileManager defaultManager];
	
	NSArray *searchPaths = [NSArray arrayWithObjects:@"/Library/Internet Plug-Ins",@"/System/Library/Internet Plug-Ins",nil];
	NSPredicate *pluginPredicate = [NSPredicate predicateWithFormat:@"(SELF ENDSWITH 'plugin') OR (SELF ENDSWITH 'webplugin')"];
	
	NSMutableArray *plugInsTmp = [[NSMutableArray alloc] init];
	NSMutableArray *plugInsDictArray = [[NSMutableArray alloc] init];
	NSArray *curDirPlugins;
	
	for (NSString *path in searchPaths) { 
		curDirPlugins = [[fm contentsOfDirectoryAtPath:path error:NULL] filteredArrayUsingPredicate:pluginPredicate];
		for (NSString *p_path in curDirPlugins) {
			[plugInsTmp addObject:[NSString stringWithFormat:@"%@/%@",path,p_path]];
		}	
	}	
	
	// Build Array of Internet Plugin Info
	NSMutableDictionary *tmpPluginDict;
	for (NSString *plugin in plugInsTmp) {
		tmpPluginDict = [[NSMutableDictionary alloc] init];
		[tmpPluginDict setObject:[plugin lastPathComponent] forKey:@"name"];
		[tmpPluginDict setObject:plugin forKey:@"path"];
		[tmpPluginDict setObject:plugin forKey:@"path_real"];
		
		// If the path is a sym link we need the full path to get attributes
		if ([[[fm attributesOfItemAtPath:plugin error:NULL] fileType] isEqualToString:NSFileTypeSymbolicLink]) {
			[tmpPluginDict setObject:[fm destinationOfSymbolicLinkAtPath:plugin error:NULL] forKey:@"path_real"];		
		}
		
		[tmpPluginDict setObject:[[fm attributesOfItemAtPath:plugin error:NULL] fileModificationDate] forKey:@"lastModified"];
		[tmpPluginDict setObject:[self readKeyFromFile:[tmpPluginDict objectForKey:@"path_real"] key:@"WebPluginName" error:NULL] forKey:@"WebPluginName"];
		[tmpPluginDict setObject:[self readKeyFromFile:[tmpPluginDict objectForKey:@"path_real"] key:@"CFBundleShortVersionString" error:NULL] forKey:@"version"];
		[tmpPluginDict setObject:[self readKeyFromFile:[tmpPluginDict objectForKey:@"path_real"] key:@"CFBundleIdentifier" error:NULL] forKey:@"BundleIdentifier"];
		
		[plugInsDictArray addObject:tmpPluginDict];
		tmpPluginDict=nil;
	}	
	
		
	plugins = [NSArray arrayWithArray:plugInsDictArray];
	
	return plugins;
}

- (NSArray *)parseLocalClientTasks
{
	NSArray *_tasks = nil;
	NSFileManager *fm = [NSFileManager defaultManager];
	
	if ([fm fileExistsAtPath:kTasksPlist]) {
		NSDictionary *_tasksDict = [NSDictionary dictionaryWithContentsOfFile:kTasksPlist];
		_tasks = [NSArray arrayWithArray:[_tasksDict objectForKey:@"mpTasks"]];
	}
	
	return _tasks;
}

- (NSString *)readKeyFromFile:(NSString *)aPath key:(NSString *)aKey error:(NSError **)err
{
	NSString *result = @"NA";
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableDictionary *details;
	NSString *pathContents = [aPath stringByAppendingPathComponent:@"Contents"];
	NSString *pathInfo = [pathContents stringByAppendingPathComponent:@"Info.plist"];
	
	if ([fm fileExistsAtPath:pathInfo]) {
		
	} else {
		if (err != NULL) {
			// populate the error object with the details
			details = [NSMutableDictionary dictionary];
			[details setValue:[NSString stringWithFormat:@"File %@ does not exist.",pathInfo] forKey:NSLocalizedDescriptionKey];
			if (err != NULL)  *err = [NSError errorWithDomain:@"world" code:1 userInfo:details];
			logit(lcl_vError, @"File %@ does not exist.",pathInfo);
		}
		return result;
	}
	
	NSString *l_error = NULL;
	NSPropertyListFormat format;
	NSData *data = [NSData dataWithContentsOfFile:pathInfo];
	NSMutableDictionary *thePlist = [NSPropertyListSerialization propertyListFromData:data 
																	 mutabilityOption:NSPropertyListImmutable 
																			   format:&format 
																	 errorDescription:&l_error];
	
	if (!thePlist) {
		details = [NSMutableDictionary dictionary];
		[details setValue:[NSString stringWithFormat:@"Error, %@ reading plist %@.",l_error, pathInfo] forKey:NSLocalizedDescriptionKey];
		if (err != NULL) *err = [NSError errorWithDomain:@"world" code:2 userInfo:details];
		logit(lcl_vError, @"Error, %@ reading plist %@.",l_error, pathInfo);
		return result;
	} 
	
	if ([thePlist objectForKey:aKey]) {
		result = [NSString stringWithString:[thePlist objectForKey:aKey]];
	}	

	return result;
}

- (NSArray *)parseLocalDiskInfo
{
    CHDiskInfo *cdi = [CHDiskInfo new];
    NSArray *_disks = [NSArray arrayWithArray:[cdi collectDiskInfoForLocalDisks]];
    return _disks;
}

- (NSArray *)parseLocalUsers
{
    MPUsersAndGroups *m = [[MPUsersAndGroups alloc] init];
    NSError *err = nil;
    NSArray *_users = [m getLocalUsers:&err];
    if (err) {
        logit(lcl_vError,@"Getting local users, %@",[err description]);
        return nil;
    }
    return _users;
}

- (NSArray *)parseLocalGroups
{
    MPUsersAndGroups *m = [[MPUsersAndGroups alloc] init];
    NSError *err = nil;
    NSArray *_groups = [m getLocalGroups:&err];
    if (err) {
        logit(lcl_vError,@"Getting local groups, %@",[err description]);
        return nil;
    }
    return _groups;
}

- (NSArray *)parseFileVaultInfo
{
    MPFileVaultInfo *fv = [[MPFileVaultInfo alloc] init];
    NSMutableDictionary *fvDict = [[NSMutableDictionary alloc] init];
    [fvDict setObject:[NSString stringWithFormat:@"%d",[fv state]] forKey:@"state" defaultObject:@"0"];
    [fvDict setObject:[fv status] forKey:@"status" defaultObject:@"na"];
    [fvDict setObject:[fv users] forKey:@"users" defaultObject:@"na"];
    
    NSArray *res = [NSArray arrayWithObject:(NSDictionary *)fvDict];
    return res;
}

- (NSArray *)parsePowerManagmentInfo
{
    NSArray *pwrDataProfiles = nil;
    NSMutableArray *_pwrDataProfiles = [[NSMutableArray alloc] init];
    NSFileManager *fm = [NSFileManager defaultManager];
	NSString *pmPlist = @"/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist";
	PowerProfile *profile;
    /* Needs to be completed */
	if ([fm fileExistsAtPath:pmPlist])
    {
        NSDictionary *pmDataRaw = [NSDictionary dictionaryWithContentsOfFile:pmPlist];
        if ([pmDataRaw objectForKey:@"Custom Profile"])
        {
            NSDictionary *customProfiles = [pmDataRaw objectForKey:@"Custom Profile"];
            for (NSString *key in [customProfiles allKeys])
            {
                profile = [[PowerProfile alloc] initWithProfileName:key];
                [_pwrDataProfiles addObject:[profile parseWithDictionary:[customProfiles objectForKey:key]]];
            }
        }
	} else {
        logit(lcl_vError, @"File %@ does not exist.",pmPlist);
	}
    
    pwrDataProfiles = [NSArray arrayWithArray:_pwrDataProfiles];
    return pwrDataProfiles;
}

- (NSArray *)parseBatteryInfo
{
    NSArray *invData = nil;
    NSMutableArray *_invData = [[NSMutableArray alloc] init];

    BatteryInfo *bi = [[BatteryInfo alloc] init];
    if (bi.hasBatteryInstalled)
    {
        [_invData addObject:[bi dictionaryRepresentation]];
        invData = [NSArray arrayWithArray:_invData];
    }

    return invData;
}

- (NSArray *)parseConfigProfilesInfo
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *fileName = [NSString stringWithFormat: @"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"plist"];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    qldebug(@"Config profile data: %@",filePath);

    // Write Profile Data To Plist
    NSArray *cmdArgs = [NSArray arrayWithObjects:@"-P",@"-o",filePath, nil];
    [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/profiles" arguments:cmdArgs] waitUntilExit];

    if (![fm fileExistsAtPath:filePath]) {
        return nil;
    }

    NSDictionary *profileDict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    NSMutableArray *profiles = [[NSMutableArray alloc] init];
    NSMutableDictionary *profile;

    if ([profileDict objectForKey:@"_computerlevel"])
    {
        for (NSDictionary *p in [profileDict objectForKey:@"_computerlevel"])
        {
            profile = [[NSMutableDictionary alloc] init];
            [profile setObject:[p objectForKey:@"ProfileIdentifier"] forKey:@"ProfileIdentifier"];
            [profile setObject:[p objectForKey:@"ProfileDisplayName"] forKey:@"ProfileDisplayName"];
            [profile setObject:[p objectForKey:@"ProfileInstallDate"] forKey:@"ProfileInstallDate"];
            [profile setObject:[p objectForKey:@"ProfileUUID"] forKey:@"ProfileUUID"];
            [profile setObject:[p objectForKey:@"ProfileVersion"] forKey:@"ProfileVersion"];
            [profiles addObject:profile];
        }
    } else {
        return nil;
    }
    // Quick Clean Up
    //[fm removeItemAtPath:filePath error:NULL];
    qldebug(@"Collected Profiles: %@",profiles);
    return [NSArray arrayWithArray:profiles];
}

- (NSArray *)parseSysInfoNetworkData:(NSArray *)networkData
{
    NSArray *netKeys = [NSArray arrayWithObjects:@"HardwareAddress",@"IsPrimary",@"InterfaceName",@"PrimaryIPAddress",
                        @"ConfigurationType",@"AllDNSServers",@"PrimaryDNSServer",@"IsActive",@"RouterAddress",
                        @"ConfigurationName",@"DomainName",@"AllIPAddresses", nil];

    NSMutableDictionary *netDict = [[NSMutableDictionary alloc] init];
    for (NSString *key in netKeys) {
        [netDict setObject:@"NA" forKey:key];
    }

    NSDictionary *item;
    NSMutableDictionary *result;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    for (int i = 0; i < [networkData count]; i++)
    {
        item = [networkData objectAtIndex:i];
        result = [[NSMutableDictionary alloc] initWithDictionary:netDict];
        for (NSString *akey in netKeys)
        {
            if ([item objectForKey:akey]) {
                if ([[item objectForKey:akey] isKindOfClass:[NSNumber class]]) {
                    [result setObject:[[item objectForKey:akey] stringValue] forKey:akey];
                }
                if ([[item objectForKey:akey] isKindOfClass:[NSString class]]) {
                    [result setObject:[item objectForKey:akey] forKey:akey];
                }
            }
        }
        [items addObject:result];
    }

    return [NSArray arrayWithArray:items];
}

- (NSArray *)parseAppStoreData
{
    NSDictionary *appData;
    NSMutableArray *items = [[NSMutableArray alloc] init];

    NSSet *dirs = [NSSet setWithObject:@"/Applications/"];
    NSMetadataQuery *metadataSearch=[[NSMetadataQuery alloc] init];
    NSArray *res = [metadataSearch resultsForSearchString:@"kMDItemAppStoreHasReceipt == '1'" inFolders:dirs];
    MacAppStoreDataItem *di;
    for (NSMetadataItem *item in res) {
        di = [[MacAppStoreDataItem alloc] initWithNSMetadataItem:item];
        appData = nil;
        appData = [NSDictionary dictionaryWithDictionary:[di dictionaryRepresentation]];
        if (appData) {
            [items addObject:appData];
        }
    }

    return [NSArray arrayWithArray:items];
}

- (NSArray *)parseAgentServerInfo
{
    NSArray *mpServerInfo = nil;
    NSMutableDictionary *mpServerListInfo;
    NSFileManager *fm = [NSFileManager defaultManager];
    /* Needs to be completed */
    if ([fm fileExistsAtPath:AGENT_SERVERS_PLIST])
    {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:AGENT_SERVERS_PLIST];
        if ([d objectForKey:@"name"])
        {
            mpServerListInfo = [[NSMutableDictionary alloc] init];
            [mpServerListInfo setObject:[d objectForKey:@"name"] forKey:@"name"];
            if ([d objectForKey:@"version"]) {
                if ([[d objectForKey:@"version"] isKindOfClass:[NSNumber class]]) {
                    [mpServerListInfo setObject:[[d objectForKey:@"version"] stringValue] forKey:@"version"];
                } else {
                    [mpServerListInfo setObject:[d objectForKey:@"version"] forKey:@"version"];
                }
            } else {
                [mpServerListInfo setObject:@"0" forKey:@"version"];
            }
            if ([d objectForKey:@"id"]) {
                if ([[d objectForKey:@"id"] isKindOfClass:[NSNumber class]]) {
                    [mpServerListInfo setObject:[[d objectForKey:@"id"] stringValue] forKey:@"id"];
                } else {
                    [mpServerListInfo setObject:[d objectForKey:@"id"] forKey:@"id"];
                }
            } else {
                [mpServerListInfo setObject:@"0" forKey:@"id"];
            }

            mpServerInfo = [NSArray arrayWithObject:mpServerListInfo];
        } else {
            logit(lcl_vError, @"name object does not exist.");
        }
    } else {
        logit(lcl_vError, @"Parse Server Info. File %@ does not exist.",AGENT_SERVERS_PLIST);
    }

    return mpServerInfo;
}

- (NSArray *)parseAgentServerList
{
    NSArray *mpServers = nil;
    NSMutableArray *serverItems = [[NSMutableArray alloc] init];
    NSFileManager *fm = [NSFileManager defaultManager];
    MPServerEntry *se;
    /* Needs to be completed */
    if ([fm fileExistsAtPath:AGENT_SERVERS_PLIST])
    {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:AGENT_SERVERS_PLIST];
        if ([d objectForKey:@"servers"])
        {
            NSArray *serverArray = [d objectForKey:@"servers"];
            for (int i = 0;i<serverArray.count;i++)
            {
                se = [[MPServerEntry alloc] initWithServerDictionary:[serverArray objectAtIndex:i] index:[NSString stringWithFormat:@"%d",i]];
                [serverItems addObject:[se dictionaryRepresentation]];
            }
        } else {
            logit(lcl_vError, @"servers object does not exist.");
        }
    } else {
        logit(lcl_vError, @"File %@ does not exist.",AGENT_SERVERS_PLIST);
    }

    mpServers = [NSArray arrayWithArray:serverItems];
    return mpServers;
}

#pragma mark Helper

- (NSDictionary *)stringToDict:(NSString *)theString theDelimiter:(NSString *)theDelimiter
{
	//First, we want to split out based on line endings
	NSMutableDictionary *keyValData = [NSMutableDictionary dictionary];
	NSArray *lines = [theString componentsSeparatedByString:@"\n"];
	
	int i = 0;
	for (i=0;i<[lines count];i++)
	{
		NSArray *split = [[lines objectAtIndex:i] componentsSeparatedByString:theDelimiter];
		if ([split count] == 2) {
			[keyValData setObject:[split lastObject] forKey:[split objectAtIndex:0]];
		}
	}

	return (NSDictionary *)keyValData;
}

@end
