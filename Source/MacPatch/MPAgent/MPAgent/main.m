//
//  main.m
//  MPAgent
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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
#import <SystemConfiguration/SystemConfiguration.h>
#import "AgentController.h"
#import "MPAgentRegister.h"
#import "MPInv.h"
#import "MPOSUpgrade.h"
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <unistd.h>

#define APPVERSION	@"3.2.0.1"
#define APPNAME		@"MPAgent"

void usage(void);
const char * consoleUser(void);

int main (int argc, char * argv[])
{
	@autoreleasepool
    {
		int a_Type              = 99;
		BOOL echoToConsole      = NO;
		BOOL debugLogging       = NO;
		BOOL traceLogging       = NO;
		BOOL verboseLogging     = NO;
        
        // Registration
        BOOL doRegistration     = NO;
        BOOL readRegInfo        = NO;
        BOOL runZetaTest        = NO;
        NSString *regKeyArg     = @"999999999";
        NSString *regKeyHash    = @"999999999";
        
        // Inventory
        NSString *invArg        = NULL;
        
        // OS Migration
        BOOL osMigration        = NO;
        NSString *osMigAction   = NULL;
        NSString *osMigLabel    = @"";
        NSString *osMigID       = @"auto";
		
		// Setup argument processing
		int c;
		while (1)
		{
			static struct option long_options[] =
			{
				{"Daemon"			,no_argument	    ,0, 'd'},
				{"Queue"			,no_argument	    ,0, 'q'},
				{"Debug"			,no_argument	    ,0, 'D'},
				{"Trace"			,no_argument	    ,0, 'T'},
				{"CheckIn"			,no_argument	    ,0, 'c'},
				{"Scan"				,no_argument	    ,0, 's'},
				{"Update"			,no_argument	    ,0, 'u'},
				{"Inventory"		,no_argument	    ,0, 'i'},
				{"AVScan"			,no_argument	    ,0, 'a'},
				{"AVUpdate"			,no_argument	    ,0, 'U'},
				{"AgentUpdater"		,no_argument	    ,0, 'G'},
                {"SWScanUpdate" 	,no_argument	    ,0, 'S'},
                {"Profile"          ,no_argument	    ,0, 'p'},
                {"WebServicePost"   ,no_argument	    ,0, 'w'},
				{"Echo"				,no_argument		,0, 'e'},
				{"Verbose"			,no_argument		,0, 'V'},
				{"version"			,no_argument		,0, 'v'},
				{"help"				,no_argument		,0, 'h'},
                {"register"		    ,optional_argument	,0, 'r'},
                {"regInfo"		    ,optional_argument  ,0, 'R'},
                // Inventory, not documented yet
                {"type"                 ,required_argument	,0, 't'},
                {"Audit"                ,no_argument		,0, 'A'},
                {"cuuid"                ,no_argument		,0, 'C'},
                // OS Migration
                {"OSUpgrade"            ,required_argument	,0, 'k'},
                {"OSLabel"              ,required_argument	,0, 'l'},
                {"OSUpgradeID"          ,required_argument	,0, 'm'},
                // Current Console User
                {"consoleUser"          ,no_argument		,0, 'x'},
                // TEST
                {"zeta"                 ,no_argument        ,0, 'Z'},
				{0, 0, 0, 0}
			};
			// getopt_long stores the option index here.
			int option_index = 0;
			c = getopt_long (argc, argv, "dqDTcsuiaUGSpweVvhr::R::t:ACk:l:m:xZ", long_options, &option_index);
			
			// Detect the end of the options.
			if (c == -1)
				break;
			
			switch (c)
			{
				case 'd':
					a_Type = 99;
					break;
				case 'q':
					a_Type = 99;
					break;
				case 'c':
					a_Type = 1;
					break;
				case 'i':
					a_Type = 2;
					break;
                case 's':
					a_Type = 3;
					break;
				case 'u':
					a_Type = 4;
					break;
				case 'a':
					a_Type = 5;
					break;
				case 'U':
					a_Type = 6;
					break;
				case 'G':
					a_Type = 7;
					break;
                case 'S':
					a_Type = 8;
					break;
                case 'p':
					a_Type = 9;
					break;
                case 'w':
					a_Type = 11;
					break;
                // Inventory
                case 't':
                    invArg = [NSString stringWithUTF8String:optarg];
                    a_Type = 12;
                    break;
                case 'A':
                    invArg = @"Custom";
                    a_Type = 12;
                    break;
                case 'C':
                    printf("%s\n",[[MPSystemInfo clientUUID] UTF8String]);
                    return 0;
                case 'k':
                    if ([[[NSString stringWithUTF8String:optarg] lowercaseString] isEqualTo:@"start"]) {
                        osMigAction = @"start";
                        osMigration = YES;
                    } else if ([[[NSString stringWithUTF8String:optarg] lowercaseString] isEqualTo:@"stop"]) {
                        osMigAction = @"stop";
                        osMigration = YES;
                    } else {
                        osMigAction = @"ERR";
                        printf("Error, \"OSUpgrade\" state must be either start or stop.\n");
                        return 1;
                    }
                    break;
                case 'l':
                    osMigLabel = [NSString stringWithUTF8String:optarg];
                    break;
                case 'm':
                    osMigID = [NSString stringWithUTF8String:optarg];
                    break;
				case 'V':
					verboseLogging = YES;
					break;
				case 'D':
					debugLogging = YES;
					break;
				case 'T':
					traceLogging = YES;
					break;
				case 'e':
					echoToConsole = YES;
					break;
                case 'x':
                    printf("%s\n",consoleUser());
                    return 0;
				case 'v':
					printf("%s\n",[APPVERSION UTF8String]);
					return 0;
                case 'r':
                    doRegistration = YES;
                    if (optarg) {
                        regKeyArg = [NSString stringWithUTF8String:optarg];
                    }
					break;
                case 'R':
                    readRegInfo = YES;
                    if (optarg) {
                        regKeyHash = [NSString stringWithUTF8String:optarg];
                    }
                    break;
                case 'Z':
                    runZetaTest = YES;
                    break;
				case 'h':
				case '?':
				default:
					usage();
			}
		}

        if (optind < argc) {
            while (optind < argc) {
                printf ("Invalid argument %s ", argv[optind++]);
            }
            usage();
            exit(0);
        }

		// Make sure the user is root or is using sudo
		if (getuid()) {
			printf("You must be root to run this app. Try using sudo.\n");
#if DEBUG
			printf("Running as debug...\n");
#else
			exit(0);
#endif
		}

    
        [[MPAgent sharedInstance] setG_agentVer:APPVERSION];
        [[MPAgent sharedInstance] setG_agentPid:[NSString stringWithFormat:@"%d",[[NSProcessInfo processInfo] processIdentifier]]];
        NSString *_logFile = [NSString stringWithFormat:@"%@/Logs/MPAgent.log",MP_ROOT_CLIENT];
		[MPLog setupLogging:_logFile level:lcl_vInfo];
		
		if (verboseLogging || debugLogging) {
			lcl_configure_by_name("*", lcl_vDebug);
			if (verboseLogging || echoToConsole) {
				[LCLLogFile setMirrorsToStdErr:YES];
			}
			logit(lcl_vInfo,@"***** %@ v.%@ started -- Debug Enabled *****", APPNAME, APPVERSION);
		} else if (traceLogging) {
			lcl_configure_by_name("*", lcl_vTrace);
			if (verboseLogging || echoToConsole) {
				[LCLLogFile setMirrorsToStdErr:YES];
			}
			logit(lcl_vInfo,@"***** %@ v.%@ started -- Trace Enabled *****", APPNAME, APPVERSION);
		} else {
			lcl_configure_by_name("*", lcl_vInfo);
			if (echoToConsole) {
				[LCLLogFile setMirrorsToStdErr:YES];
			}
			logit(lcl_vInfo,@"***** %@ v.%@ started *****", APPNAME, APPVERSION);
		}
        
        // Zeta Test
        if (runZetaTest)
        {
            /*
            MPHTTPRequest *ch = [MPHTTPRequest new];
            NSDictionary *data = [ch agentData];
            MPWSResult *result;
            result = [ch runSyncPOST:[@"/api/v1/client/checkin" stringByAppendingPathComponent:[data objectForKey:@"cuuid"]] body:data];
            if (!result) {
                NSLog(@"Error running sync POST");
            } else {
                NSLog(@"Status: %d",(int)result.statusCode);
                NSLog(@"Result: %@",result.toDictionary);
            }
            */
            exit(0);
             
        }
        
        // Process Inventory
        if (invArg !=NULL)
        {
            int x = 0;
            MPInv *inv = [[MPInv alloc] init];
            if ([invArg isEqual:@"Custom"]) {
                x = [inv collectAuditTypeData];
            } else if ([invArg isEqual:@"All"]) {
                x = [inv collectInventoryData];
            } else {
                x = [inv collectInventoryDataForType:invArg];
            }
            return x;
        }
        
        // Client Registration
        if (doRegistration)
        {
            int regResult = -1;
            NSError *regErr = nil;
            MPAgentRegister *mpar = [[MPAgentRegister alloc] init];
        
            if (![regKeyArg isEqualToString:@"999999999"]) {
                regResult = [mpar registerClient:regKeyArg error:&regErr];
            } else {
                regResult = [mpar registerClient:&regErr];
            }
            
            if (regErr) {
                NSLog(@"%@",regErr.localizedDescription);
            }
            
            if (regResult == 0) {
                printf("\nAgent has been registered.\n");
            } else {
                fprintf(stderr, "Agent registration has failed.\n");
                exit(1);
            }
            
            exit(0);
            
        // Verify Registration
        }
        else if (readRegInfo)
        {
            MPAgentRegister *mpar = [[MPAgentRegister alloc] init];
            
            if (![regKeyHash isEqualToString:@"999999999"]) {
                if ([mpar clientIsRegistered]) {
                    printf("\nAgent is registered.\n");
                    exit(0);
                } else {
                    printf("Warning: Agent is not registered.\n");
                    exit(1);
                }
            } else {
                // Will add additional check
                if ([mpar clientIsRegistered]) {
                    printf("\nAgent is registered.\n");
                    exit(0);
                } else {
                    printf("Warning: Agent is not registered.\n");
                    exit(1);
                }
            }

        // Post OS Migration Info
        }
        else if (osMigration)
        {
            NSString *uID;
            MPOSUpgrade *mposu = [[MPOSUpgrade alloc] init];
            if ([[osMigID lowercaseString] isEqualTo:@"auto"]) {
                if ([[osMigAction lowercaseString] isEqualTo:@"stop"]) {
                    uID = [mposu  migrationIDFromFile:OS_MIGRATION_STATUS];
                } else {
                    uID = [[NSUUID UUID] UUIDString];
                }
            } else {
                uID = osMigID;
            }
            NSError *err = nil;
            int res = [mposu postOSUpgradeStatus:osMigAction label:osMigLabel upgradeID:uID error:&err];
            if (err) {
                logit(lcl_vError,@"%@",err.localizedDescription);
                fprintf(stderr, "%s\n", [err.localizedDescription UTF8String]);
                exit(1);
            }
            if (res != 0) {
                fprintf(stderr, "Post OS Upgrade status failed.\n");
                exit(1);
            }
            
            exit(0);
            
        }
        else
        {
            AgentController *mpac = [[AgentController alloc] init];
            [mpac runWithType:a_Type];
            
            [[NSRunLoop currentRunLoop] run];
        }
		
    }
    return 0;
}

void usage(void)
{
    
	printf("%s: MacPatch Agent\n",[APPNAME UTF8String]);
	printf("Version %s\n\n",[APPVERSION UTF8String]);
	printf("Usage: %s [OPTIONS]\n\n",[APPNAME UTF8String]);
	printf(" -d \tRun as background daemon.\n");
    printf(" -q \tRun as background daemon using operation queues.\n");
	printf(" -c \t --CheckIn \t\tRun client checkin.\n");
    printf(" -w \t --WebServicePost \tRe-post failed post attempts.\n\n");
    printf("OS Profiles \n\n");
    printf(" -p \t --Profile \tScan & Install macOS profiles.\n\n");
    printf("Agent Updater \n\n");
    printf(" -G \t --AgentUpdater \tUpdate the MacPatch agent updater agent.\n\n");
    printf("Agent Registration \n\n");
    printf(" -r \t --register \tRegister Agent [ RegKey (Optional) ] based on configuration.\n");
    printf(" -R \t --regInfo \tDisplays if client is registered.\n\n");
    printf("OS Migration \n\n");
    printf(" -k \t --OSUpgrade \tOS Migration/Upgrade action state (Start/Stop)\n");
    printf(" -l \t --OSLabel \tOS Migration/Upgrade label\n");
    printf(" -m \t --OSUpgradeID \tA Unique Migration/Upgrade ID (Optional Will Auto Gen by default)\n\n");
	printf("Antivirus (Symantec) \n\n");
	printf(" -a \t --AVScan \tCollects Antivirus data installed on system.\n");
	printf(" -U \t --AVUpdate \tUpdates antivirus defs.\n\n");
    printf("Inventory \n");
    printf("Option: -t [ALL] or [SPType]\n\n");
    printf(" -t\tInventory type, All is default.\n");
    printf(" \tSupported types:\n");
    printf(" \t\tAll\n");
    printf(" \t\tSPHardwareDataType\n");
    printf(" \t\tSPSoftwareDataType\n");
    printf(" \t\tSPNetworkDataType (Depricated)\n");
    printf(" \t\tSINetworkInfo\n");
    printf(" \t\tSPApplicationsDataType\n");
    printf(" \t\tSPFrameworksDataType\n");
    printf(" \t\tDirectoryServices\n");
    printf(" \t\tInternetPlugins\n");
    printf(" \t\tAppUsage\n");
    printf(" \t\tClientTasks\n");
    printf(" \t\tDiskInfo\n");
    printf(" \t\tUsers\n");
    printf(" \t\tGroups\n");
	printf(" \t\tLocalAdminAccounts\n");
    printf(" \t\tFileVault\n");
    printf(" \t\tPowerManagment\n");
    printf(" \t\tBatteryInfo\n");
    printf(" \t\tConfigProfiles\n");
    printf(" \t\tAppStoreApps\n");
    printf(" \t\tMPServerList\n");
    printf(" \t\tPlugins\n");
    printf(" \t\tFirmwarePasswordInfo\n");
    printf(" -A \tCollect Audit data.\n\n");
    printf(" -C \tDisplay client ID.\n");
	printf(" -e \t --Echo \t\t\tEcho logging data to console.\n");
	printf(" -V \tVerbose logging.\n");
	printf("\n -v \tDisplay version info. \n");
	printf("\n");
    exit(0);
}

const char * consoleUser(void)
{
    NSString *result;
    SCDynamicStoreRef   store;
    CFStringRef         consoleUserName;
    
    store = SCDynamicStoreCreate(NULL, (CFStringRef)@"GetCurrentConsoleUser", NULL, NULL);
    consoleUserName = SCDynamicStoreCopyConsoleUser(store, NULL, NULL);
    
    NSString *nsString = (__bridge NSString*)consoleUserName;

    if (nsString) {
        result = nsString;
    } else {
        result = @"null";
    }

    if (consoleUserName)
        CFRelease(consoleUserName);
    
    return [result UTF8String];
}
