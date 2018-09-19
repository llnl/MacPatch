//
//  MPNetConfig.m
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

#import "MPNetConfig.h"
#import "MPNetServer.h"
// #import "MPDefaults.h"

#undef  ql_component
#define ql_component lcl_cMPNetConfig

@implementation MPNetConfig
{
    NSFileManager *fm;
    NSMutableArray *tmpServers;
}

@synthesize servers;

- (id)init
{
    self = [super init];
    if (self)
    {
        fm = [NSFileManager defaultManager];
        tmpServers = [[NSMutableArray alloc] init];
        BOOL useMaster = YES;
        if ([fm fileExistsAtPath:AGENT_SERVERS_PLIST])
        {
            NSDictionary *agentServerConf = [NSDictionary dictionaryWithContentsOfFile:AGENT_SERVERS_PLIST];
            if ([agentServerConf objectForKey:@"servers"])
            {
                if ([[agentServerConf objectForKey:@"servers"] count] > 0)
                {
                    for (NSDictionary *s in [agentServerConf objectForKey:@"servers"])
                    {
                        MPNetServer *ns = [MPNetServer serverObjectWithDictionary:s];
                        [tmpServers addObject:ns];
                    }
                    self.servers = [NSArray arrayWithArray:tmpServers];
                    useMaster = NO;
                }
            }
        }

        if (useMaster == YES)
        {
            MPNetServer *sns = [[MPNetServer alloc] init];
            /*
            MPDefaults *d = [[MPDefaults alloc] init];
            NSDictionary *defaults = [d defaults];
            [sns setHost:[defaults objectForKey:@"MPServerAddress"]];
            [sns setPort:[[defaults objectForKey:@"MPServerPort"] integerValue]];
            [sns setUseHTTPS:([[defaults objectForKey:@"MPServerSSL"] integerValue] ? YES : NO)];
            [sns setUseTLSAuth:([[defaults objectForKey:@"MPClientAuth"] integerValue] ? YES : NO)];
            [sns setAllowSelfSigned:([[defaults objectForKey:@"MPServerAllowSelfSigned"] integerValue] ? YES : NO)];
            [sns setServerType:0];
             */
            self.servers = [NSArray arrayWithObject:sns];
        }


    }
    return self;
}

- (id)initWithServer:(MPNetServer *)netServer
{
    self = [super init];
    if (self)
    {
        self.servers = [NSArray arrayWithObject:netServer];
    }
    return self;
}

@end
