//
//  main.m
//  MPAgent
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
#import <SystemConfiguration/SystemConfiguration.h>
#import "MacPatch.h"
#import "SoftwareController.h"
#import "MPAgentRegister.h"
#import "CheckIn.h"
#import "MPInv.h"
#import "MPOSUpgrade.h"
#import "TasksDaemon.h"
#import "MPProvision.h"
#import "MPAgentUpdater.h"
//#import "MPFailedRequests.h"
#import "Patching.h"
#import "MPFileVault.h"
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <unistd.h>

#define APPVERSION	@"4.0.0.0"
#define APPNAME		@"MPAgent"
// This Define will be modified durning MPClientBuild script
#define APPBUILD	@"[BUILD]"


void usage(void);
const char * consoleUser(void);

typedef NS_ENUM(NSInteger, CommandType) {
    CommandTypeNone,
    CommandTypeDaemon,
    CommandTypeCheckIn,
    CommandTypePatchScan,
    CommandTypePatchUpdate,
    CommandTypeAgentUpdater,
    CommandTypeInventory,
    CommandTypeClientID,
    CommandTypeVersion,
    CommandTypeRegister,
    CommandTypeFileVault,
    CommandTypeOSMigration,
    CommandTypeSoftware,
    CommandTypeProvision,
    CommandTypeProvisionConfig,
    CommandTypePostFailedWebServiceRequests,
    CommandTypePostAgentInstall
};

CommandType parseCommand(const char *cmd) {
    if (strcmp(cmd, "daemon") == 0) return CommandTypeDaemon;
    if (strcmp(cmd, "checkIn") == 0) return CommandTypeCheckIn;
    if (strcmp(cmd, "checkin") == 0) return CommandTypeCheckIn;
    if (strcmp(cmd, "-c") == 0) return CommandTypeCheckIn; // Legacy
    if (strcmp(cmd, "patchScan") == 0) return CommandTypePatchScan;
    if (strcmp(cmd, "scan") == 0) return CommandTypePatchScan;
    if (strcmp(cmd, "patchUpdate") == 0) return CommandTypePatchUpdate;
    if (strcmp(cmd, "update") == 0) return CommandTypePatchUpdate;
    if (strcmp(cmd, "agentUpdater") == 0) return CommandTypeAgentUpdater;
    if (strcmp(cmd, "inventory") == 0) return CommandTypeInventory;
    if (strcmp(cmd, "inv") == 0) return CommandTypeInventory;
    if (strcmp(cmd, "clientID") == 0) return CommandTypeClientID;
    if (strcmp(cmd, "-C") == 0) return CommandTypeClientID; // Legacy
    if (strcmp(cmd, "id") == 0) return CommandTypeClientID;
    if (strcmp(cmd, "version") == 0) return CommandTypeVersion;
    if (strcmp(cmd, "-v") == 0) return CommandTypeVersion;
    if (strcmp(cmd, "--version") == 0) return CommandTypeVersion;
    if (strcmp(cmd, "register") == 0) return CommandTypeRegister;
    if (strcmp(cmd, "osupgrade") == 0) return CommandTypeOSMigration;
    if (strcmp(cmd, "-k") == 0) return CommandTypeOSMigration; // Legacy
    if (strcmp(cmd, "oslabel") == 0) return CommandTypeOSMigration;
    if (strcmp(cmd, "-l") == 0) return CommandTypeOSMigration; // Legacy
    if (strcmp(cmd, "osUpgradeID") == 0) return CommandTypeOSMigration;
    if (strcmp(cmd, "-m") == 0) return CommandTypeOSMigration; // Legacy
    if (strcmp(cmd, "fileVault") == 0) return CommandTypeFileVault;
    if (strcmp(cmd, "authRestartStatus") == 0) return CommandTypeFileVault;
    if (strcmp(cmd, "--fvCheck") == 0) return CommandTypeFileVault; // Legacy
    if (strcmp(cmd, "-Z") == 0) return CommandTypeFileVault; // Legacy
    if (strcmp(cmd, "software") == 0) return CommandTypeSoftware;
    if (strcmp(cmd, "provision") == 0) return CommandTypeProvision;
    if (strcmp(cmd, "-L") == 0) return CommandTypeProvision; // Legacy
    if (strcmp(cmd, "provisionConfig") == 0) return CommandTypeProvisionConfig;
    if (strcmp(cmd, "-z") == 0) return CommandTypeProvisionConfig; // Legacy
    if (strcmp(cmd, "postFailedWSRequests") == 0) return CommandTypePostFailedWebServiceRequests;
    if (strcmp(cmd, "agentInstall") == 0) return CommandTypePostAgentInstall;
    if (strcmp(cmd, "--agentInstall") == 0) return CommandTypePostAgentInstall; // Legacy
    if (strcmp(cmd, "-K") == 0) return CommandTypePostAgentInstall; // Legacy
    
    
    return CommandTypeNone;
}

void printUsage(const char *progname) {
    fprintf(stderr, "Usage: %s <command> [OPTIONS]\n\n", progname);
    fprintf(stderr, "Commands:\n");
    fprintf(stderr, "  daemon        Run in daemon mode\n");
    fprintf(stderr, "  checkIn       Run client check in\n");
    fprintf(stderr, "  patchScan     Run patch scan on host\n");
    fprintf(stderr, "  patchUpdate   Run patch updates on host\n");
    fprintf(stderr, "  agentUpdater  Scan and update the Agent updater\n");
    fprintf(stderr, "  software      Install software for options\n");
    fprintf(stderr, "    Options:\n");
    fprintf(stderr, "    -g, --group        Software Group\n");
    fprintf(stderr, "    -d, --swid         Software Task ID\n");
    fprintf(stderr, "    -P, --plist        Software Task ID(s) Plist\n");
    fprintf(stderr, "    -M, --mandatory    Scan and Install Mandatory Software\n\n");
    fprintf(stderr, "  inventory     Run inventory collection on host\n");
    fprintf(stderr, "    Options:\n");
    fprintf(stderr, "    -t, --type INVENTORY TYPE\n\n");
    fprintf(stderr, "    Inventory Types:\n");
    fprintf(stderr, "     • All (Default when no type specified)\n");
    fprintf(stderr, "     • SPHardwareDataType\n");
    fprintf(stderr, "     • SPSoftwareDataType\n");
    fprintf(stderr, "     • SPNetworkDataType (Depricated)\n");
    fprintf(stderr, "     • SINetworkInfo\n");
    fprintf(stderr, "     • SPApplicationsDataType\n");
    fprintf(stderr, "     • SPFrameworksDataType\n");
    fprintf(stderr, "     • SPExtensionsDataType\n");
    fprintf(stderr, "     • DirectoryServices\n");
    fprintf(stderr, "     • InternetPlugins\n");
    fprintf(stderr, "     • AppUsage\n");
    fprintf(stderr, "     • ClientTasks\n");
    fprintf(stderr, "     • DiskInfo\n");
    fprintf(stderr, "     • Users\n");
    fprintf(stderr, "     • Groups\n");
    fprintf(stderr, "     • LocalAdminAccounts\n");
    fprintf(stderr, "     • FileVault\n");
    fprintf(stderr, "     • PowerManagment\n");
    fprintf(stderr, "     • BatteryInfo\n");
    fprintf(stderr, "     • ConfigProfiles\n");
    fprintf(stderr, "     • AppStoreApps\n");
    fprintf(stderr, "     • MPServerList\n");
    fprintf(stderr, "     • Plugins\n");
    fprintf(stderr, "     • FirmwarePasswordInfo\n\n");
    fprintf(stderr, "  fileVault    Check if file valut authrestart is set\n\n");
    fprintf(stderr, "  register     Register Agent With Server\n");
    fprintf(stderr, "    Options:\n");
    fprintf(stderr, "    -k, --key        Agent Registration Key\n");
    fprintf(stderr, "    -s, --status     Agent Registration Status\n\n");
    fprintf(stderr, "  provisionConfig, -z  Download and create the provisioning config file.\n");
    fprintf(stderr, "  provision, -L        Start the provisioing process. Including any pre-scripts and software installs\n\n");
    fprintf(stderr, "  clientID, -C    Return Client ID\n");
    
    //fprintf(stderr, "  postFailedWSRequests     Try to repost any failed web service commands\n\n");
    fprintf(stderr, "Global Options:\n");
    fprintf(stderr, "  -V, --verbose       Enable verbose/debug logging\n");
    fprintf(stderr, "  -e, --echo          Echo logging to stdout\n");
}

int main (int argc, char * argv[])
{
	@autoreleasepool
    {
        if (argc < 2) {
            printUsage(argv[0]);
            return 1;
        }
        
        CommandType command = parseCommand(argv[1]);
        if (command == CommandTypeNone) {
            fprintf(stderr, "Error: Unknown command '%s'\n\n", argv[1]);
            printUsage(argv[0]);
            return 1;
        }
        
        optind = 2;
        
        const char *short_opts;
        struct option *long_opts;
        
        // Argparse Option Groups
        static struct option global_options[] = {
            {"echo", no_argument,       0, 'e'},
            {"verbose", no_argument,    0, 'V'},
            {"trace", no_argument,      0, 'T'},
            {0, 0, 0, 0}
        };
        
        static struct option daemon_options[] = {
            {"echo", no_argument,       0, 'e'},
            {"verbose", no_argument,    0, 'V'},
            {"trace", no_argument,      0, 'T'},
            {0, 0, 0, 0}
        };
        
        static struct option patch_options[] = {
            {"echo", no_argument,       0, 'e'},
            {"verbose", no_argument,    0, 'V'},
            {"trace", no_argument,      0, 'T'},
            {0, 0, 0, 0}
        };
        
        static struct option inventory_options[] = {
            {"echo", no_argument,       0, 'e'},
            {"verbose", no_argument,    0, 'V'},
            {"trace", no_argument,      0, 'T'},
            {"type", required_argument, 0, 't'},
            {0, 0, 0, 0}
        };
        
        static struct option register_options[] = {
            {"echo",    no_argument,        0,    'e'},
            {"verbose", no_argument,        0,    'V'},
            {"trace",   no_argument,        0,    'T'},
            {"key",     optional_argument,  NULL, 'k'},
            {"status",  no_argument,        0,    's'},
            {0, 0, 0, 0}
        };
        
        static struct option osupgrade_options[] = {
            {"echo",        no_argument,        0, 'e'},
            {"verbose",     no_argument,        0, 'V'},
            {"trace",       no_argument,        0, 'T'},
            {"start",       no_argument,        0, 'b'},
            {"stop",        no_argument,        0, 'f'},
            {"label",       required_argument,  0, 'l'},
            {"upgradeid",   required_argument,  0, 'm'},
            {0, 0, 0, 0}
        };
        
        static struct option software_options[] = {
            {"echo",        no_argument,        0, 'e'},
            {"verbose",     no_argument,        0, 'V'},
            {"trace",       no_argument,        0, 'T'},
            {"group",       required_argument,  0, 'g'},
            {"swid",        required_argument,  0, 'd'},
            {"plist",       required_argument,  0, 'P'},
            {"mandatory",   no_argument,        0, 'M'},
            {0, 0, 0, 0}
        };
                
        switch (command) {
            case CommandTypeDaemon:
                short_opts = "VeT";
                long_opts = daemon_options;
                break;
            case CommandTypeCheckIn:
                short_opts = "VeT";
                long_opts = patch_options;
                break;
            case CommandTypePatchScan:
                short_opts = "VeT";
                long_opts = patch_options;
                break;
            case CommandTypePatchUpdate:
                short_opts = "VeT";
                long_opts = patch_options;
                break;
            case CommandTypeInventory:
                short_opts = "Vet:T";
                long_opts = inventory_options;
                break;
            case CommandTypeClientID:
                break;
            case CommandTypeVersion:
                break;
            case CommandTypeRegister:
                short_opts = "Vek:sT";
                long_opts = register_options;
                break;
            case CommandTypeSoftware:
                short_opts = "Veg:d:p:T";
                long_opts = software_options;
                break;
            case CommandTypeProvision:
                short_opts = "VeT";
                long_opts = global_options;
                break;
            case CommandTypeProvisionConfig:
                short_opts = "VeT";
                long_opts = global_options;
                break;
            case CommandTypeFileVault:
                short_opts = "VeT";
                long_opts = global_options;
                break;
            case CommandTypeAgentUpdater:
                short_opts = "VeT";
                long_opts = global_options;
                break;
            case CommandTypePostFailedWebServiceRequests:
                short_opts = "VeT";
                long_opts = global_options;
                break;
            case CommandTypePostAgentInstall:
                short_opts = "VeT";
                long_opts = global_options;
                break;
            default:
                return 1;
        }
                
        BOOL verbose = NO, debug = NO, echo = NO, trace = NO;
        BOOL daemon = NO, osmigrationstart=NO, osmigrationstop=NO;
        BOOL regStatus = NO, mandatory = NO, iload = NO;
        NSString *invetoryType = @"all";
        NSString *regKey = @"999999999";
        NSString *osUpgradeLabel = nil;
        NSString *osUpgradeID = @"auto";
        // Software
        NSString *group = nil;
        NSString *swid = nil;
        NSString *plist = nil;
        
        NSError  *err = nil;
        
        int opt;
        while ((opt = getopt_long(argc, argv, short_opts, long_opts, NULL)) != -1) {
            switch (opt) {
                case 'V': verbose = YES; break;
                case 'e': echo = YES; break;
                case 'T': trace = YES; break;
                case 't': invetoryType = [NSString stringWithUTF8String:optarg]; break;
                case 'k':
                    regKey = [NSString stringWithUTF8String:optarg];
                    break;
                case 's': regStatus = YES; break;
                case 'b': osmigrationstart = YES; break;
                case 'f': osmigrationstop = YES; break;
                case 'l': osUpgradeLabel = [NSString stringWithUTF8String:optarg]; break;
                case 'm': osUpgradeID = [NSString stringWithUTF8String:optarg]; break;
                case 'd': daemon = YES; break;
                case '?': return 1;
                default: abort();
            }
        }
        
        [[MPAgent sharedInstance] setG_agentVer:APPVERSION];
        [[MPAgent sharedInstance] setG_agentPid:[NSString stringWithFormat:@"%d",[[NSProcessInfo processInfo] processIdentifier]]];
        
        // Setup Logging
        NSString *_logFile = @"/Library/Logs/MPAgent.log";
        Logger *logger = [Logger sharedLogger];
        [logger setupWithLogPath:_logFile subsystem:@"gov.llnl.mp.mpagent" category:@"daemon"];
        [logger setEnableFunctionName:NO];
        [logger setEnableFileNameAndLineNumber:NO];
        [logger setEnableStderrLogging:NO];
        
        if (verbose || debug) {
            logger.minimumLogLevel = LogLevelDebug;
            if (verbose || echo) {
                logger.enableStderrLogging = YES;
            }
            LogInfo(@"***** %@ Debug Enabled *****", APPNAME);
        } else if (trace) {
            logger.minimumLogLevel = LogLevelDebug;
            [logger setEnableFunctionName:YES];
            [logger setEnableFileNameAndLineNumber:YES];
            if (verbose || echo) {
                logger.enableStderrLogging = YES;
            }
        } else {
            logger.minimumLogLevel = LogLevelInfo;
            if (echo) {
                logger.enableStderrLogging = YES;
            }
        }
                
        // Execute command with parsed options
        switch (command) {
            case CommandTypeDaemon: {
                LogInfo(@"***** %@ v%@ started *****", APPNAME, APPVERSION);
                // Echo PID to stdout when requested and always log it
                pid_t pid = getpid();
                if (echo) {
                    printf("%d\n", pid);
                    fflush(stdout);
                }
                MPLOG_INFO(@"Daemon PID: %d", pid);
                LogInfo( @"Daemon PID: %d", pid);
                TasksDaemon *td = [[TasksDaemon alloc] init];
                [td runAsDaemon];
                return 0;
            } break;
            case CommandTypeCheckIn: {
                LogInfo( @"Running Local Command - Client Checkin...");
                CheckIn *ac = [[CheckIn alloc] init];
                [ac runClientCheckIn];
                return 0;
            } break;
            case CommandTypePatchScan: {
                LogInfo( @"Running Local Command - Patch Scan...");
                Patching *p = [[Patching alloc] init];
                [p patchScan];
                return 0;
            } break;
            case CommandTypePatchUpdate: {
                LogInfo( @"Running Local Command - Patch Scan & Update...");
                Patching *p = [[Patching alloc] init];
                [p patchScanAndUpdate];
                return 0;
            } break;
            case CommandTypeInventory: {
                int result = 1;
                MPInv *inv = [[MPInv alloc] init];
                if ([[invetoryType lowercaseString] isEqual:@"custom"]) {
                    LogInfo( @"Running Local Command - Inventory with custome type...");
                    result = [inv collectAuditTypeData];
                } else if ([[invetoryType lowercaseString] isEqual:@"all"]) {
                    LogInfo( @"Running Local Command - Inventory...");
                    result = [inv collectInventoryData];
                } else {
                    LogInfo( @"Running Local Command - Inventory for type %@...", invetoryType);
                    result = [inv collectInventoryDataForType:invetoryType];
                }
                return result;
            } break;
            case CommandTypeClientID:
                printf("%s\n",[[MPSystemInfo clientUUID] UTF8String]);
                break;
            case CommandTypeVersion:
                printf("MPAgent Version: %s", [APPVERSION UTF8String]);
                break;
            case CommandTypeRegister: {
                int result = 1;
                MPAgentRegister *mpar = [[MPAgentRegister alloc] init];
                if (regStatus) {
                    if ([mpar clientIsRegistered]) {
                        printf("\nAgent is registered.\n");
                        exit(0);
                    } else {
                        printf("Warning: Agent is not registered.\n");
                        exit(1);
                    }
                } else {
                    // Can not register agent is regStatus is invoked
                    LogInfo( @"Running Local Command - Agent Registration...");
                    if (regKey) {
                        if (![regKey isEqualToString:@"999999999"]) {
                            result = [mpar registerClient:regKey error:&err];
                        } else {
                            result = [mpar registerClient:&err];
                        }
                    } else {
                        result = [mpar registerClient:&err];
                    }
                    
                    if (err) {
                        LogError(@"Error registering agent. %@",err.localizedDescription);
                    }
                    
                    if (result == 0) {
                        printf("\nAgent has been registered.\n");
                        exit(0);
                    } else {
                        fprintf(stderr, "Agent registration has failed.\n");
                        exit(1);
                    }
                }
                exit(0);
            } break;
            case CommandTypeAgentUpdater: {
                LogInfo( @"Running Local Command - Agent Updater...");
                MPAgentUpdater *agentUpdater = [[MPAgentUpdater alloc] init];
                [agentUpdater scanAndUpdateAgentUpdater];
                return 0;
            } break;
            case CommandTypeOSMigration: {
                // OS Migration
                LogInfo( @"Running Local Command - OS Migration...");
                NSString *osMigAction = NULL;
                if (osmigrationstart) {
                    osMigAction = @"start";
                } else if (osmigrationstop) {
                    osMigAction = @"stop";
                }
                
                NSString *uID = nil;
                MPOSUpgrade *mposu = [[MPOSUpgrade alloc] init];
                if ([[osUpgradeID lowercaseString] isEqualTo:@"auto"]) {
                    if (osmigrationstop) {
                        uID = [mposu  migrationIDFromFile:OS_MIGRATION_STATUS];
                    } else {
                        uID = [[NSUUID UUID] UUIDString];
                    }
                } else {
                    uID = osUpgradeID;
                }
                NSError *err = nil;
                int result = [mposu postOSUpgradeStatus:osMigAction label:osUpgradeLabel upgradeID:uID error:&err];
                if (err) {
                    LogError(@"%@",err.localizedDescription);
                    fprintf(stderr, "%s\n", [err.localizedDescription UTF8String]);
                    exit(1);
                }
                if (result != 0) {
                    LogError(@"Post OS Upgrade status failed with result %d.\n", result);
                    fprintf(stderr, "Post OS Upgrade status failed.\n");
                    exit(1);
                }
                return 0;
            } break;
            case CommandTypeSoftware: {
                // Software - Install Group
                int result = 1;
                SoftwareController *swc = [[SoftwareController alloc] init];
                if (group && !plist && !swid && !mandatory) {
                    LogInfo( @"Running Local Command - Software install for group %@...", group);
                    [swc setILoadMode:iload];
                    result = [swc installSoftwareTasksForGroup:group];
                    return result;
                } else if (!group && plist && !swid && !mandatory) {
                    LogInfo( @"Running Local Command - Software install using plist %@...", plist);
                    [swc setILoadMode:iload];
                    result = [swc installSoftwareTasksUsingPLIST:plist];
                    return result;
                } else if (!group && !plist && swid && !mandatory) {
                    LogInfo( @"Running Local Command - Software install using task id %@...", swid);
                    [swc setILoadMode:iload];
                    result = [swc installSoftwareTask:swid];
                    return result;
                } else if (!group && !plist && !swid && mandatory) {
                    [swc setILoadMode:iload];
                    LogInfo( @"Running Local Command - Software install for mondatory apps...");
                    result = [swc installMandatorySoftware];
                    return result;
                } else {
                    fprintf(stderr, "Only one software option can be used at a time (group, swid, plist, mandatory).");
                    exit(1);
                }
            } break;
            case CommandTypeProvision: {
                LogInfo( @"Running Local Command - Provision Host...");
                MPProvision *mpProv = [[MPProvision alloc] init];
                [mpProv provisionHost];
            } break;
            case CommandTypeProvisionConfig: {
                LogInfo( @"Running Local Command - Provision Host Config...");
                int result = 1;
                MPProvision *mpProv = [[MPProvision alloc] init];
                result = [mpProv provisionSetupAndConfig];
                exit(result);
            } break;
            case CommandTypeFileVault: {
                LogInfo( @"Running Local Command - Checking FileVault Authrestart status...");
                MPFileVault *mpfv = [[MPFileVault alloc] init];
                [mpfv authRestartCheck];
                exit(0);
            } break;
            case CommandTypePostFailedWebServiceRequests: {
                LogInfo( @"Running Local Command - Post any failed web service requests...");
                MPFailedRequests *mpf = [[MPFailedRequests alloc] init];
                [mpf postFailedRequests];
            } break;
            case CommandTypePostAgentInstall: {
                MPAgent *agent = [[MPAgent alloc] init];
                [agent postAgentHasBeenInstalled];
            } break;
            default:
                break;
        }
    }
    return 0;
}

void usage(void)
{
	printf("%s: MacPatch Agent\n",[APPNAME UTF8String]);
	printf("Version %s\n\n",[APPVERSION UTF8String]);
	printf("Usage: %s [OPTIONS]\n\n",[APPNAME UTF8String]);
	printf(" -c \t --CheckIn \t\tRun client checkin.\n\n");
	// Agent Registration
	printf("Agent Registration \n");
	printf(" -r \t --register \tRegister Agent [ RegKey (Optional) ] based on configuration.\n");
	printf(" -R \t --regInfo \tDisplays if client is registered.\n\n");
	// Scan & Update
	printf("Patching \n");
	printf(" -s \t --Scan \tScan for patches.\n");
	printf(" -u \t --Update \tScan & Update approved patches.\n\n");
    printf(" -Z \t --fvCheck \tCheck if file valut authrestart is set.\n\n");
	// printf(" -x \tScan & Update critical patches only.\n");
	
	// Software Dist
	printf("Software \n");
	printf(" -g \t[Software Group Name] Install Software in group.\n");
	printf(" -d \tInstall software using TaskID\n");
	printf(" -P \t[Software Plist] Install software using plist.\n\n");
	printf(" -S \tInstall client group mandatory software.\n\n");
	
	// Mac OS Profiles
    printf("OS Profiles \n");
    printf(" -p \t --Profile \tScan & Install macOS profiles.\n\n");
	// Agent Updater
	printf("Agent Updater \n");
    printf(" -G \t --AgentUpdater \tUpdate the MacPatch agent updater agent.\n\n");
	// OS Migration - iLoad etc.
	printf("OS Provisioning - iLoad \n");
	printf(" -i \t --iLoad \tiLoad flag for provisioning output.\n\n");
	
	printf("OS Migration \n");
    printf(" -k \t --OSUpgrade \tOS Migration/Upgrade action state (Start/Stop)\n");
    printf(" -l \t --OSLabel \tOS Migration/Upgrade label\n");
    printf(" -m \t --OSUpgradeID \tA Unique Migration/Upgrade ID (Optional Will Auto Gen by default)\n\n");
	// Anti-Virus
	printf("Antivirus (Symantec) \n");
	printf(" -a \t --AVScan \tCollects Antivirus data installed on system.\n");
	printf(" -U \t --AVUpdate \tUpdates antivirus defs.\n\n");
	// Inventory
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
	printf(" \t\tSPExtensionsDataType\n");
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

