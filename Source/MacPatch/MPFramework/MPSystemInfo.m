//
//  MPSystemInfo.m
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "MPSystemInfo.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <mach-o/arch.h>
#include <sys/sysctl.h>
#include <pwd.h>

#include <ifaddrs.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <arpa/inet.h>

typedef struct kinfo_proc kinfo_proc;

#undef  ql_component
#define ql_component lcl_cMPSystemInfo

@implementation MPSystemInfo

#pragma mark - MacPatch Client Info

+ (NSString *)clientUUID
{
    NSString *cUUID = NULL;
    
	io_struct_inband_t iokit_entry;
	uint32_t bufferSize = 4096; // this signals the longest entry we will take
	io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
	IORegistryEntryGetProperty(ioRegistryRoot, kIOPlatformUUIDKey, iokit_entry, &bufferSize);
	cUUID = [NSString stringWithCString:iokit_entry encoding:NSASCIIStringEncoding];
    
	IOObjectRelease((unsigned int) iokit_entry);
	IOObjectRelease(ioRegistryRoot);
	
	if ([cUUID length] < 35) {
        cUUID = [[NSString stringWithFormat:@"00000000-0000-1000-8000-%@",[MPSystemInfo getMacAddressForInterface:@"en0"]] stringByReplacingOccurrencesOfString:@":" withString:@""];
        qlwarning(@"Host is using old cuuid (%@) format.",cUUID);
    }    
	
	goto done;
	
done:
	return cUUID;
}

#pragma mark - Client Networking Info

+ (NSString *)getMacAddressForInterfaceUsingC:(NSString *)interface
{
	int                 mgmtInfoBase[6];
	char                *msgBuffer = NULL;
	size_t              length;
	unsigned char       macAddress[6];
	struct if_msghdr    *interfaceMsgStruct;
	struct sockaddr_dl  *socketStruct;
	NSString            *errorFlag = NULL;
	
	// Setup the management Information Base (mib)
	mgmtInfoBase[0] = CTL_NET;        // Request network subsystem
	mgmtInfoBase[1] = AF_ROUTE;       // Routing table info
	mgmtInfoBase[2] = 0;
	mgmtInfoBase[3] = AF_LINK;        // Request link layer information
	mgmtInfoBase[4] = NET_RT_IFLIST;  // Request all configured interfaces
	
	// With all configured interfaces requested, get handle index
	
	if ((mgmtInfoBase[5] = if_nametoindex([interface UTF8String])) == 0)
		errorFlag = @"if_nametoindex failure";
	else
	{
	 
		// Get the size of the data available (store in len)
		if (sysctl(mgmtInfoBase, 6, NULL, &length, NULL, 0) < 0)
			errorFlag = @"sysctl mgmtInfoBase failure";
		else
		{
			// Alloc memory based on above call
			if ((msgBuffer = malloc(length)) == NULL)
				errorFlag = @"buffer allocation failure";
			else
			{
				// Get system information, store in buffer
				if (sysctl(mgmtInfoBase, 6, msgBuffer, &length, NULL, 0) < 0)
					errorFlag = @"sysctl msgBuffer failure";
			}
		}
	}
	
	// Befor going any further...
	if (errorFlag != NULL)
	{
		NSLog(@"Error: %@", errorFlag);
		return errorFlag;
	}
	
	// Map msgbuffer to interface message structure
	interfaceMsgStruct = (struct if_msghdr *) msgBuffer;
	
	// Map to link-level socket structure
	socketStruct = (struct sockaddr_dl *) (interfaceMsgStruct + 1);
	
	// Copy link layer address data in socket structure to an array
	memcpy(&macAddress, socketStruct->sdl_data + socketStruct->sdl_nlen, 6);
	
	// Read from char array into a string object, into traditional Mac address format
	NSString *macAddressString = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
								  macAddress[0], macAddress[1], macAddress[2],
								  macAddress[3], macAddress[4], macAddress[5]];
	//NSLog(@"Mac Address: %@", macAddressString);
	
	// Release the buffer memory
	free(msgBuffer);
	
	return macAddressString;
}

+ (NSDictionary *)activeInterfaceData
{
	struct ifaddrs* interfaces = NULL;
	struct ifaddrs* temp_addr = NULL;
	NSDictionary *result = nil;
	
	// retrieve the current interfaces - returns 0 on success
	NSInteger success = getifaddrs(&interfaces);
	if (success == 0)
	{
		// Loop through linked list of interfaces
		temp_addr = interfaces;
		while (temp_addr != NULL)
		{
			if (temp_addr->ifa_addr->sa_family == AF_INET) // internetwork only
			{
				NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
				if (!name) {
					name = @"ERR";
				}
				if ([name rangeOfString:@"en"].location != NSNotFound)
				{
					qldebug(@"Getting data for interface: %@",name);
					NSString *address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
					if (!address) {
						address = @"0.0.0.0";
					}
					NSString *macAddr = [self getMacAddressForInterfaceUsingC:name];
					if (!macAddr) {
						macAddr = @"00:00:00:00:00:00";
					}
					qldebug(@"Getting MAC address for %@: %@",name, macAddr);
					qldebug(@"Getting IP for %@: %@",name, address);
					result = @{@"interface":name,@"macAddr":macAddr,@"ipAddr":address};
					break;
				}
			}
			
			temp_addr = temp_addr->ifa_next;
		}
	}
	
	// Free memory
	freeifaddrs(interfaces);
	return result;
}


+ (NSString *)getActiveInterface
{
    NSString *activeInterface = @"en0";
    SCDynamicStoreRef dynRefForIF = SCDynamicStoreCreate(kCFAllocatorSystemDefault,(CFStringRef)@"GetDynamicStoreForIP", NULL, NULL);
    NSArray *aIfList = (NSArray *)CFBridgingRelease(SCDynamicStoreCopyKeyList(dynRefForIF,CFSTR("State:/Network/Global/IPv4")));
    for (NSString *aIf in aIfList) {
        NSDictionary *dict = (NSDictionary *)CFBridgingRelease(SCDynamicStoreCopyValue(dynRefForIF,(__bridge CFStringRef)aIf));
        if (dict) {
            activeInterface = [NSString stringWithString:[dict objectForKey:@"PrimaryInterface"]];
            break;
        } 
    }
    //CFRelease(dynRefForIF);
    return activeInterface;
}

+ (NSString *)getMacAddressForActiveInterface
{
    return [MPSystemInfo getMacAddressForInterface:[MPSystemInfo getActiveInterface]];
}

+ (NSString *)getMacAddressForInterface:(NSString *)bsdIfName
{
    NSString				*macAddress			= nil;
	NSArray                 *allInterfaces      = (NSArray*)CFBridgingRelease(SCNetworkInterfaceCopyAll());
	NSEnumerator            *interfaceWalker	= [allInterfaces objectEnumerator];
	SCNetworkInterfaceRef   curInterface		= nil;
	
	while ((curInterface = (__bridge SCNetworkInterfaceRef)[interfaceWalker nextObject]))
	{
		if ( [(__bridge NSString*)SCNetworkInterfaceGetBSDName(curInterface) isEqualToString:bsdIfName])
		{
			macAddress = [NSString stringWithString:(__bridge NSString*)SCNetworkInterfaceGetHardwareAddressString(curInterface)];
			break;
		}
	}
	return macAddress;
}

+ (NSString *)getIPAddress
{
    return [MPSystemInfo getIPAddressForInterface:[MPSystemInfo getActiveInterface]];
}

+ (NSString *)getIPAddressForInterface:(NSString *)bsdIfName
{
    NSString *ipResult = @"NA";
    
    SCDynamicStoreRef dynRef=SCDynamicStoreCreate(kCFAllocatorSystemDefault,(CFStringRef)@"", NULL, NULL);
    NSArray *interfaceList=(NSArray *)CFBridgingRelease(SCDynamicStoreCopyKeyList(dynRef,(CFStringRef)@"State:/Network/Interface/.*/IPv4"));
    qldebug(@"interfaceList: %@",interfaceList);
    for (NSString *interface in interfaceList) 
    {
        if ([interface rangeOfString:bsdIfName].location != NSNotFound && [interface rangeOfString:@"lo0"].location == NSNotFound)
        {
            qldebug(@"interface: %@",interface);
            NSDictionary *interfaceDict = (NSDictionary *)CFBridgingRelease(SCDynamicStoreCopyValue(dynRef,(__bridge CFStringRef)interface));
            NSArray *iList = nil;
            iList = [NSArray arrayWithArray:[interfaceDict objectForKey:@"Addresses"]];
            if (iList) {
                if ([iList count] >= 1) {
                    ipResult = [iList objectAtIndex:0];
                    break;
                }
            }
        }
    }
    return ipResult;
}

#pragma mark - System Version Info

+ (NSDictionary *)consoleUserData
{
    NSMutableDictionary *uData = [[NSMutableDictionary alloc] init];
	[uData setObject:@"NA" forKey:@"consoleUser"];
	[uData setObject:@"NA" forKey:@"consoleUserUID"];
	[uData setObject:@"NA" forKey:@"consoleUserGID"];
    
    // Get Current User Info
	NSString *consoleUserName;
	uid_t	uid;
	gid_t	gid;
    
    consoleUserName = (NSString *)CFBridgingRelease(SCDynamicStoreCopyConsoleUser(NULL, &uid, &gid));
	if ([consoleUserName length] >= 1) {
		[uData setObject:(NSString *)consoleUserName forKey:@"consoleUser"];
		[uData setObject:[NSString stringWithFormat:@"%i",uid] forKey:@"consoleUserUID"];
		[uData setObject:[NSString stringWithFormat:@"%i",gid] forKey:@"consoleUserGID"];
	}
    
    NSDictionary *consoleUser = [NSDictionary dictionaryWithDictionary:uData];
    return consoleUser;
}

+ (NSDictionary *)hostAndComputerNames
{
    NSMutableDictionary *localInfo = [[NSMutableDictionary alloc] init];
	
	[localInfo setObject:@"NA" forKey:@"localComputerName"];
	[localInfo setObject:@"NA" forKey:@"localHostName"];
    
    // Get Local Computer Name
	CFStringRef localComputerName = SCDynamicStoreCopyLocalHostName(NULL);
	if (localComputerName && CFStringGetLength(localComputerName)!=0) {
		[localInfo setObject:(__bridge NSString *)localComputerName forKey:@"localComputerName"];
	}

    if (localComputerName) {
        CFRelease(localComputerName);
    }
    
	// Get Local Host Name
	NSHost *localHost = [NSHost currentHost];
	[localInfo setObject:[localHost name] forKey:@"localHostName"];
	
    NSDictionary *chNames = [NSDictionary dictionaryWithDictionary:localInfo];
	return chNames;
}

+ (NSDictionary *)osVersionInfo
{
    NSFileManager *fm = [NSFileManager defaultManager]; 
    NSMutableDictionary *osVers = [[NSMutableDictionary alloc] init];
	
    NSString *serverAppPath = @"/Applications/Server.app";
	NSString *clientVerPath = @"/System/Library/CoreServices/SystemVersion.plist";
	NSString *serverVerPath = @"/System/Library/CoreServices/ServerVersion.plist";
	
    if ([fm fileExistsAtPath:clientVerPath]) {
        osVers = [NSMutableDictionary dictionaryWithContentsOfFile:clientVerPath];
    } else if ([fm fileExistsAtPath:serverVerPath]) {
        osVers = [NSMutableDictionary dictionaryWithContentsOfFile:serverVerPath];
    } else {
        //Error
        [osVers setObject:@"NA" forKey:@"ProductBuildVersion"];
        [osVers setObject:@"NA" forKey:@"ProductBuildVersion"];
        [osVers setObject:@"NA" forKey:@"ProductCopyright"];
        [osVers setObject:@"NA" forKey:@"ProductName"];
        [osVers setObject:@"NA" forKey:@"ProductUserVisibleVersion"];
        [osVers setObject:@"NA" forKey:@"ProductVersion"];
    }
    
    if ([fm fileExistsAtPath:serverAppPath]) {
        // 10.7 and above
        [osVers setObject:@"Mac OS X Server" forKey:@"ProductName"];
    }
    
    NSDictionary *results = [NSDictionary dictionaryWithDictionary:osVers];
	return results;
}

+ (NSDictionary *)osVersionOctets
{
    NSDictionary *sysVer;

    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10) {
        NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
        sysVer = @{@"major":[NSNumber numberWithInt:(int)os.majorVersion],@"minor":[NSNumber numberWithInt:(int)os.minorVersion],@"revision":[NSNumber numberWithInt:(int)os.patchVersion]};
    } else {
        SInt32 OSmajor, OSminor, OSrevision;
        OSErr err1 = Gestalt(gestaltSystemVersionMajor, &OSmajor);
        OSErr err2 = Gestalt(gestaltSystemVersionMinor, &OSminor);
        OSErr err3 = Gestalt(gestaltSystemVersionBugFix, &OSrevision);
        if (!err1 && !err2 && !err3)
        {
            sysVer = @{@"major":[NSNumber numberWithInt:OSmajor],@"minor":[NSNumber numberWithInt:OSminor],@"revision":[NSNumber numberWithInt:OSrevision]};
        }
    }
    
    return sysVer;
}

+ (NSString *)hostArchitectureType
{
    const NXArchInfo *info = NXGetLocalArchInfo();
	
	switch (info->cputype) {
		case CPU_TYPE_POWERPC:
			return @"ppc";
			break;
		case CPU_TYPE_I386:
			return @"i386";
			break;
		case CPU_TYPE_POWERPC64:
			return @"ppc";
			break;
		case CPU_TYPE_X86_64:
			return @"i386";
			break;
		default:
			return @"na";
			break;
	}
}

+ (BOOL)hostNeedsReboot
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/tmp/.MPAuthRun"] == TRUE) {
		return YES;
	} else {
        return NO;
    }
}

+ (NSDictionary *)getMPApplicationVersions
{
    NSDictionary *result;
    
    NSFileManager *fm = [NSFileManager defaultManager]; 
    NSString *file = nil;
    NSString *taskResult = nil;
    
    
    NSMutableArray *files = [[NSMutableArray alloc] initWithArray:[fm directoryContentsAtPath:MP_ROOT_CLIENT]];
    [files addObject:@"/Library/Frameworks/MPFramework.framework"];
    
    NSMutableDictionary *apps = [[NSMutableDictionary alloc] init];
    NSError *err = nil;
    MPNSTask *task = [[MPNSTask alloc] init];
    for (NSString *item in files) {
        file = [MP_ROOT_CLIENT stringByAppendingPathComponent:item];
        if ([file containsString:@".app"] || [file containsString:@".framework"]) {
            [apps setObject:[NSString versionStringForApplication:file] forKey:item];
        } else {
            err = nil;
            taskResult = [task runTask:[MP_ROOT_CLIENT stringByAppendingPathComponent:item] binArgs:[NSArray arrayWithObject:@"-v"] error:&err];
            if ([taskResult isEqualToString:@"Error"] == NO && [taskResult containsString:@"Error" ignoringCase:YES] == NO) 
            {
                [apps setObject:taskResult forKey:item];	
            }
        }
    }
    
    result = [NSDictionary dictionaryWithDictionary:apps];
    return result;
}

#pragma mark -
#pragma mark BSD Process List

static int GetBSDProcessList(kinfo_proc **procList, size_t *procCount)
// Returns a list of all BSD processes on the system.  This routine
// allocates the list and puts it in *procList and a count of the
// number of entries in *procCount.  You are responsible for freeing
// this list (use "free" from System framework).
// On success, the function returns 0.
// On error, the function returns a BSD errno value.
{
    int                 err;
    kinfo_proc *        result;
    bool                done;
    static const int    name[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    // Declaring name as const requires us to cast it when passing it to
    // sysctl because the prototype doesn't include the const modifier.
    size_t              length;
    
    //    assert( procList != NULL);
    //    assert(*procList == NULL);
    //    assert(procCount != NULL);
    
    *procCount = 0;
    
    // We start by calling sysctl with result == NULL and length == 0.
    // That will succeed, and set length to the appropriate length.
    // We then allocate a buffer of that size and call sysctl again
    // with that buffer.  If that succeeds, we're done.  If that fails
    // with ENOMEM, we have to throw away our buffer and loop.  Note
    // that the loop causes use to call sysctl with NULL again; this
    // is necessary because the ENOMEM failure case sets length to
    // the amount of data returned, not the amount of data that
    // could have been returned.
    
    result = NULL;
    done = false;
    do {
        assert(result == NULL);
        
        // Call sysctl with a NULL buffer.
        
        length = 0;
        err = sysctl( (int *) name, (sizeof(name) / sizeof(*name)) - 1,
                     NULL, &length,
                     NULL, 0);
        if (err == -1) {
            err = errno;
        }
        
        // Allocate an appropriately sized buffer based on the results
        // from the previous call.
        
        if (err == 0) {
            result = malloc(length);
            if (result == NULL) {
                err = ENOMEM;
            }
        }
        
        // Call sysctl again with the new buffer.  If we get an ENOMEM
        // error, toss away our buffer and start again.
        
        if (err == 0) {
            err = sysctl( (int *) name, (sizeof(name) / sizeof(*name)) - 1,
                         result, &length,
                         NULL, 0);
            if (err == -1) {
                err = errno;
            }
            if (err == 0) {
                done = true;
            } else if (err == ENOMEM) {
                assert(result != NULL);
                free(result);
                result = NULL;
                err = 0;
            }
        }
    } while (err == 0 && ! done);
    
    // Clean up and establish post conditions.
    
    if (err != 0 && result != NULL) {
        free(result);
        result = NULL;
    }
    *procList = result;
    if (err == 0) {
        *procCount = length / sizeof(kinfo_proc);
    }
    
    assert( (err == 0) == (*procList != NULL) );
    
    return err;
}

+ (NSArray *)bsdProcessList
{
    kinfo_proc *mylist =NULL;
    size_t mycount = 0;
    GetBSDProcessList(&mylist, &mycount);
    
    NSMutableArray *processes = [NSMutableArray arrayWithCapacity:(int)mycount];
    
    for (int i = 0; i < mycount; i++) {
        struct kinfo_proc *currentProcess = &mylist[i];
        struct passwd *user = getpwuid(currentProcess->kp_eproc.e_ucred.cr_uid);
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithCapacity:4];
        
        NSNumber *processID = [NSNumber numberWithInt:currentProcess->kp_proc.p_pid];
        NSString *processName = [NSString stringWithFormat: @"%s",currentProcess->kp_proc.p_comm];
        if (processID)[entry setObject:processID forKey:@"processID"];
        if (processName)[entry setObject:processName forKey:@"processName"];
        
        if (user){
            NSNumber *userID = [NSNumber numberWithUnsignedInt:currentProcess->kp_eproc.e_ucred.cr_uid];
            NSString *userName = [NSString stringWithFormat: @"%s",user->pw_name];
            
            if (userID)[entry setObject:userID forKey:@"userID"];
            if (userName)[entry setObject:userName forKey:@"userName"];
        }
        
        [processes addObject:[NSDictionary dictionaryWithDictionary:entry]];
    }
    free(mylist);
    
    return [NSArray arrayWithArray:processes];
}

@end
