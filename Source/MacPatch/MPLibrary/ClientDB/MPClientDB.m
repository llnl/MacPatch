//
//  MPDB.m
//  FMDBme
//
//  Created by Charles Heizer on 10/23/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import "MPClientDB.h"

// Models
#import "History.h"
#import "InstalledSoftware.h"
#import "RequiredPatch.h"

NSString *const dbFile = @"/private/var/db/MPData.plist";

/* DB File
 
 {
	history : [], // Array History Model
 	installed_patches : [], // Array Installed Patches Model
 	installed_software : [], // Array Installed SW Model
 	required_patches : [] // Array Required Patches Model
 }
 
 */


@interface MPClientDB ()
{
	NSFileManager *fm;
}

@property (nonatomic, strong) NSMutableArray *installedPatches;
@property (nonatomic, strong) NSMutableArray *installedSoftware;
@property (nonatomic, strong) NSMutableArray *requiredPatches;
@property (nonatomic, strong) NSMutableArray *history;

- (void)setupFile;
- (void)save;

@end

@implementation MPClientDB

- (id)init
{
	self = [super init];
	if (self)
	{
		fm = [NSFileManager defaultManager];
		[self setupFile];
	}
	return self;
}

- (void)setupFile
{
	if (![fm fileExistsAtPath:dbFile]) // Does not exist
	{
        self.installedPatches = [NSMutableArray new];
        self.installedSoftware = [NSMutableArray new];
        self.requiredPatches = [NSMutableArray new];
        self.history = [NSMutableArray new];
        
		[self save];
	} else {
		// Maybe add check for each section
		[self open];
	}

	return;
}

/**
 Record the install of a software task.

 @param swTask - Software Task Dictionary
 @return BOOL
 */
- (BOOL)recordSoftwareInstall:(NSDictionary *)swTask
{
	BOOL result = NO;
	@try
	{
		BOOL add = NO;
		NSUInteger index;
		InstalledSoftware *sw;
		sw = [self findValueForKeyInArray:swTask[@"id"] key:@"tuuid" array:self.installedSoftware];
		if (sw) {
			index = [self.installedSoftware indexOfObject:sw];
			// Found, need to update
			if (swTask[@"Software"][@"sw_uninstall"]) {
				sw.has_uninstall = 1;
				sw.uninstall = swTask[@"Software"][@"sw_uninstall"];
			} else {
				sw.has_uninstall = 0;
				sw.uninstall = @"";
			}
			
		} else {
			add = YES;
			// Add Record
			sw = [InstalledSoftware new];
			sw.id = [[NSUUID UUID] UUIDString];
			sw.name = swTask[@"name"];
			sw.tuuid = swTask[@"id"];
			sw.suuid = swTask[@"Software"][@"sid"];
			if (swTask[@"Software"][@"sw_uninstall"]) {
				sw.has_uninstall = 1;
				sw.uninstall = swTask[@"Software"][@"sw_uninstall"];
			} else {
				sw.has_uninstall = 0;
				sw.uninstall = @"";
			}
		}
		
		sw.install_date = [NSDate date];
		NSError *error = nil;
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:swTask options:0 error:&error];
		if (!jsonData) {
			qlerror(@"%s: error: %@", __func__, error.localizedDescription);
			sw.json_data = @"[]";
		} else {
			sw.json_data = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
		}
		
		if (add) {
			// Add new
            [self.installedSoftware addObject:sw];
		} else {
			// Update current
            [self.installedSoftware replaceObjectAtIndex:index  withObject:sw];
		}
		
		// Save dictionary to file
		[self save];
		
		result = YES;
		[self recordHistory:kMPSoftwareType name:swTask[@"name"] uuid:swTask[@"id"] action:kMPInstallAction result:0 errorMsg:NULL];
		return result;
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
		return result;
	}
	return result;
	
	return YES;
}

/**
 Record the uninstall of a software task.

 @param swTaskName - SW Task Name
 @param swTaskID - SW Task ID
 @return BOOL
 */
- (BOOL)recordSoftwareUninstall:(NSString *)swTaskName taskID:(NSString *)swTaskID
{
	NSUInteger index;
    InstalledSoftware *sw = [self findValueForKeyInArray:swTaskID key:@"tuuid" array:self.installedSoftware];
	if (sw) {
        index = [self.installedSoftware indexOfObject:sw];
        [self.installedSoftware removeObjectAtIndex:index];
        
        // Save dictionary to file
		[self save];
	}
	
	[self recordHistory:kMPSoftwareType name:swTaskName uuid:swTaskID action:kMPUnInstallAction result:0 errorMsg:NULL];
	return YES;
}


/**
 Return an array of all software task ids installed

 @return NSArray
 */
- (NSArray *)retrieveInstalledSoftwareTasks
{
	NSMutableArray *swTasks = [NSMutableArray new];
	@try
	{
		NSMutableArray *installedSoftwareArray = [self.installedSoftware mutableCopy];
		
		for (InstalledSoftware *sw in installedSoftwareArray) {
			[swTasks addObject:sw.tuuid];
		}

		return [swTasks copy];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	
	return [swTasks copy];
}

/**
 Return an array of dictionaries of all software tasks installed

 @return NSArray
 */

- (NSArray *)retrieveInstalledSoftwareTasksDict
{
    NSMutableArray *swTasks = [NSMutableArray new];
    @try
    {
        NSMutableArray *installedSoftwareArray = [self.installedSoftware mutableCopy];
        
        for (InstalledSoftware *sw in installedSoftwareArray) {
            [swTasks addObject:@{@"name":sw.name, @"tuuid":sw.tuuid, @"suuid":sw.suuid, @"hasUninstall":@(sw.has_uninstall)}];
        }

        return [swTasks copy];
    }
    @catch (NSException *exception) {
        qlerror(@"%@",exception);
    }
    
    return [swTasks copy];
}

/**
 Method answers if a software task is installed.
 
 @param swTaskID - Software task id
 @return BOOL
 */
- (BOOL)isSoftwareTaskInstalled:(NSString *)swTaskID
{
	InstalledSoftware *sw;
	NSMutableArray *installedSoftwareArray = [self.installedSoftware mutableCopy];
	sw = [self findValueForKeyInArray:swTaskID key:@"tuuid" array:installedSoftwareArray];
	if (sw) {
		return YES;
	}
	
	return NO;
}

/**
 Get a software yask using a Sw TaskID
 
 @param swTaskID - Software task id
 @return IntsalledSoftware object or nil
 */
- (InstalledSoftware *)getSoftwareTaskUsingID:(NSString *)swTaskID
{
	NSMutableArray *installedSoftwareArray = [self.installedSoftware mutableCopy];
	InstalledSoftware *sw = [self findValueForKeyInArray:swTaskID key:@"tuuid" array:installedSoftwareArray];
	if (sw) {
		return sw;
	}
	
	return nil;
}

#pragma mark - Patches
// Patch

/**
 Record the insatll of a patch

 @param patch - NSDictionary
 @return BOOL
 */
- (BOOL)recordPatchInstall:(NSDictionary *)patch
{
	qldebug(@"[recordPatchInstall]: %@",patch[@"patch"]);
	BOOL result = NO;
	@try
	{
		NSString *_patch = patch[@"patch"];
		NSString *_patchID;
		NSString *_type;
		if ([patch[@"type"] isEqualToString:@"Apple"]) {
			_patchID = patch[@"patch"];
			_type = @"Apple";
		} else {
			_patchID = patch[@"patch_id"];
			_type = @"Third";
		}
		
		result = [self recordHistory:kMPPatchType name:_patch uuid:_patchID action:kMPInstallAction result:0 errorMsg:NULL];
		[self removeRequiredPatch:_type patchID:_patchID patch:_patch];
		qldebug(@"%@ patch install was added to local db.",_patch);
	}
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
	}
	
	return result;
}

/**
 Add required patch to database

 @param patch - NSDictionary
 @return BOOL
 */
- (BOOL)addRequiredPatch:(NSDictionary *)patch
{
	BOOL result = NO;
	@try
	{
		qldebug(@"[addRequiredPatch]: %@",patch);
		
		NSNumber *patchReboot = @(0);
		NSString *patchVersion = @"0";
		NSString *patchID = [patch[@"type"] isEqualToString:@"Apple"] ? patch[@"patch"] : patch[@"patch_id"];
		
        //qlinfo(@"[addRequiredPatch]: patchID=%@",patchID);
    
		if ([patch[@"restart"] isEqualToString:@"Yes"]) patchReboot = @(1);
		if (![patch[@"version"] isKindOfClass:[NSNull class]]) patchVersion = patch[@"version"];
		
		RequiredPatch *rp = [RequiredPatch new];
        if (patch[@"type"]) {
            rp.type = patch[@"type"];
        } else {
            qlerror(@"Required patch is missing type.");
            return result;
        }
        if (patchID) {
            rp.patch_id = patchID;
        } else {
            qlerror(@"Required patch is missing patch ID.");
            return result;
        }
        if (patch[@"patch"]) {
            rp.patch = patch[@"patch"];
        } else {
            qlerror(@"Required patch is missing patch.");
            return result;
        }
        if (patchVersion) {
            rp.patch_version = patchVersion;
        } else {
            qlerror(@"Required patch is missing patchVersion.");
            rp.patch_version = @"0";
        }

		rp.patch_reboot = [patchReboot integerValue];
		rp.patch_data = [NSKeyedArchiver archivedDataWithRootObject:patch];
		rp.patch_scandate = [NSDate date];
	
		// Add new entry to history array
        [self.requiredPatches addObject:rp];
		
        // Save dictionary to file
		[self save];
		
		result = YES;
		return result;
    }
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
	}

	return result;
}


/**
 After patch has been installed the record is removed from database table of required patches.

 @param type - NSString
 @param patchID - NSString
 @param patch - NSString
 @return BOOL
 */
- (BOOL)removeRequiredPatch:(NSString *)type patchID:(NSString *)patchID patch:(NSString *)patch
{
	@try
	{
		NSMutableArray *toDelete = [NSMutableArray array];
		NSMutableArray *rpArray = [self.requiredPatches mutableCopy];
		for (RequiredPatch *p in rpArray)
		{
			if ([p.type isEqualToString:type] && [p.patch_id isEqualToString:patchID] && [p.patch isEqualToString:patch])
			{
				[toDelete addObject:p];
			}
		}
		
        [self.requiredPatches removeAllObjects];
        [rpArray removeObjectsInArray:toDelete];
        self.requiredPatches = [rpArray mutableCopy];
		
        qltrace(@"Save");
		[self save];
		
		return YES;
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	
	return NO;
}


/**
 Returns an array of required patches

 @return NSArray
 */
- (NSArray *)retrieveRequiredPatches
{
	NSArray *rpArray = [self.requiredPatches copy];
	return rpArray;
}

/**
 Clear all required patches from database table. This is
 done prior to adding new found patches after a scan.
 
 @return BOOL
 */
- (BOOL)clearRequiredPatches
{
    [self.requiredPatches removeAllObjects];
	[self save];
	return YES;
}

#pragma mark - History
// History

/**
 Record a action in the history table. This is done for software installs and
 uninstalls. It's also done for patch installs.

 @param hstType - History Type
 @param aName - Name
 @param aUUID - Type ID PUUID or TUUID
 @param aAction - Action type (install or remove)
 @param code - Action return code
 @param aErrMsg - If, error message
 @return BOOL
 */
- (BOOL)recordHistory:(DBHistoryType)hstType name:(NSString *)aName uuid:(NSString *)aUUID
			   action:(DBHistoryAction)aAction result:(NSInteger)code errorMsg:(nullable NSString *)aErrMsg
{
	@try
	{
		History *hst = [History new];
		hst.id = [[NSUUID UUID] UUIDString];
		hst.type = (NSInteger)hstType;
		hst.name = aName;
		hst.uuid = aUUID;
		NSString *_action = (aAction == kMPInstallAction) ? @"Install" : @"Uninstall";
		hst.action = _action;
		hst.result_code = (NSInteger)code;
		if (aErrMsg != NULL) {
			hst.error_msg = aErrMsg;
		} else {
			hst.error_msg = @"";
		}
		hst.cdate = [NSDate date];
        [self.history addObject:hst];

		// Save dictionary to file
		[self save];
		return YES;
	}
	@catch (NSException *exception)
	{
		qlerror(@"[recordHistory]: %@",exception);
		return NO;
	}
}

/**
 Return an array of all history tasks

 @return NSArray
 */
- (NSArray *)retrieveHistory
{
	@try
	{
        NSArray *hstArr = [self.history copy];
		return hstArr;
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	
	return [NSArray array];
}


#pragma mark - Private

- (void)open
{
	NSError *err = nil;
	NSMutableDictionary *dbDict = [[NSKeyedUnarchiver unarchiveObjectWithFile:dbFile] mutableCopy];
    
    self.requiredPatches = [[dbDict objectForKey:@"required_patches"] mutableCopy];
    self.installedPatches = [[dbDict objectForKey:@"installed_patches"] mutableCopy];
    self.installedSoftware = [[dbDict objectForKey:@"installed_software"] mutableCopy];
    self.history = [[dbDict objectForKey:@"history"] mutableCopy];
	
	// 10.13 and higher
	//NSData *data = [NSData dataWithContentsOfFile:dbFile];
	//dbDict = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class] fromData:data error:&err];
	
	if (err) {
		qlerror(@"Error %@.",err.localizedDescription);
	}
}

- (void)save
{
    NSDictionary *d = @{ @"history":self.history,
           @"installed_patches":self.installedPatches,
           @"installed_software":self.installedSoftware,
           @"required_patches":self.requiredPatches };

	BOOL result = [NSKeyedArchiver archiveRootObject:d toFile:dbFile];
	if (!result) {
		qlerror(@"Error writing data to %@.",dbFile);
	}
    
	/* 10.13 and higher
	NSError *err = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dbDict requiringSecureCoding:YES error:&err];
	if (err) {
		NSLog(@"Error %@.",err.localizedDescription);
	} else {
		BOOL result = [data writeToFile:dbFile atomically:NO];
		if (!result) {
			NSLog(@"Error writing data to %@.",dbFile);
		}
	}
	*/
    
	return;
}

- (id)findValueForKeyInArray:(NSString *)findValue key:(NSString *)key array:(NSArray *)array
{
	for (id x in array) {
		NSDictionary *d = [x dictionaryRepresentation];
		if ([d objectForKey:key]) {
			if ([d[key] isEqual:findValue]) {
				return x;
			}
		}
	}
	return nil;
}
@end

