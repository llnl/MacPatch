//
//  FileVault.m
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

#import "MPFileVault.h"
#import "MacPatch.h"

@implementation MPFileVault

- (void)authRestartCheck
{
    NSError *err = nil;
    BOOL isValid = NO;
    MPFileCheck *fu = [MPFileCheck new];
    if ([fu fExists:MP_AUTHSTATUS_FILE])
    {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
        if ([d[@"enabled"] boolValue])
        {
            [self cliPrint:@"AuthRestart is enabled."];
            
            if ([d[@"useRecovery"] boolValue])
            {
                [self cliPrint:@"AuthRestart is using recovery key."];
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:MP_AUTHSTATUS_ITEM error:&err];
                if (!err)
                {
                    isValid = [self recoveryKeyIsValid:pi.userPass];
                    [self cliPrint:@"AuthRestart Recovery Key %@ valid.",isValid ? @"is":@"is not"];
                } else {
                    [self cliPrint:@"Error retrieving password item for service."];
                    [self cliPrint:@"Error: %@",err.localizedDescription];
                }
            } else {
                DHCachedPasswordUtil *dh = [DHCachedPasswordUtil new];
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:MP_AUTHSTATUS_ITEM error:&err];
                if (!err)
                {
                    isValid = [dh checkPassword:pi.userPass forUserWithName:pi.userName];
                    [self cliPrint:@"AuthRestart UserName and Password %@ valid.",isValid ? @"is":@"is not"];
                } else {
                    [self cliPrint:@"Error retrieving password item for service."];
                    [self cliPrint:@"Error: %@",err.localizedDescription];
                }
            }
        } else {
            [self cliPrint:@"AuthRestart is not enabled."];
        }
    }
}

- (BOOL)recoveryKeyIsValid:(NSString *)rKey
{
    BOOL isValid = NO;

    NSString *script = [NSString stringWithFormat:@"#!/bin/bash \n"
    "/usr/bin/expect -f- << EOT \n"
    "spawn /usr/bin/fdesetup validaterecovery; \n"
    "expect \"Enter the current recovery key:*\" \n"
    "send -- %@ \n"
    "send -- \"\\r\" \n"
    "expect \"true\" \n"
    "expect eof; \n"
    "EOT",rKey];
    
    MPScript *mps = [MPScript new];
    NSString *res = [mps runScriptReturningResult:script];
    // Now Look for our result ...
    NSArray *arr = [res componentsSeparatedByString:@"\n"];
    for (NSString *l in arr) {
        if ([l containsString:@"fdesetup"]) {
            continue;
        }
        if ([l containsString:@"Enter the "]) {
            continue;
        }
        if ([[l trim] isEqualToString:@"false"]) {
            isValid = NO;
            break;
        }
        if ([[l trim] isEqualToString:@"true"]) {
            isValid = YES;
            break;
        }
    }

    return isValid;
}

- (void)cliPrint:(NSString *)text,...
{
    @try {
        va_list args;
        va_start(args, text);
        NSString *textStr = [[NSString alloc] initWithFormat:text arguments:args];
        va_end(args);
        
        printf("%s\n", [textStr cStringUsingEncoding:[NSString defaultCStringEncoding]]);
    }
    @catch (NSException *exception) {
        qlerror(@"%@",exception);
    }
}
@end
