//
//  MPNetworkUtils.m
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

#import "MPNetworkUtils.h"
#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SCNetworkReachability.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <poll.h>

#undef  ql_component
#define ql_component lcl_cMPNetUtils

#define DEFAULT_TIMEOUT 3
static int isalive(struct sockaddr_in scanaddr);

@interface MPNetworkUtils()

@end

@implementation MPNetworkUtils

@synthesize hostConfig;

static int isalive(struct sockaddr_in scanaddr)
{
    short int sock;          /* our main socket */
    long arg;                /* for non-block */
    fd_set wset;             /* file handle for bloc mode */
    struct timeval timeout;  /* timeout struct for connect() */
    
    sock = socket(AF_INET, SOCK_STREAM, 0);
    
    if( (arg = fcntl(sock, F_GETFL, NULL)) < 0) { 
        fprintf(stderr,"Error fcntl(..., F_GETFL) (%s)\n",strerror(errno));
        return 1;
    }
    
    arg |= O_NONBLOCK;
    if(fcntl(sock, F_SETFL, arg) < 0) {
        fprintf(stderr,"Error fcntl(..., F_SETFL)  (%s)\n",strerror(errno));
        return 1;
    }
    
    /* 
     * set result stat then try a select if it can take
     * awhile. This is dirty but works 
     */
    int res = connect(sock,(struct sockaddr *)&scanaddr, sizeof(scanaddr));
    
    if (res < 0) {
        if (errno == EINPROGRESS) {
            timeout.tv_sec = DEFAULT_TIMEOUT;
            timeout.tv_usec = 0;
            FD_ZERO(&wset);
            FD_SET(sock, &wset);
            int rc = select(sock + 1, NULL, &wset, NULL, &timeout);
            
            /* This works great on dead hosts */
            if (rc == 0 && errno != EINTR) {
                //printf("Error connecting\n");
                close (sock);
                return 1;
            }
        }
    }
    
    close(sock);
    return 0;
}

static int isAliveWithTimeout(struct sockaddr_in scanaddr, int timeoutSeconds)
{
    short int sock;          /* our main socket */
    long arg;                /* for non-block */
    fd_set wset;             /* file handle for bloc mode */
    struct timeval timeout;  /* timeout struct for connect() */
    
    sock = socket(AF_INET, SOCK_STREAM, 0);
    
    if( (arg = fcntl(sock, F_GETFL, NULL)) < 0) {
        fprintf(stderr,"Error fcntl(..., F_GETFL) (%s)\n",strerror(errno));
        return 1;
    }
    
    arg |= O_NONBLOCK;
    if(fcntl(sock, F_SETFL, arg) < 0) {
        fprintf(stderr,"Error fcntl(..., F_SETFL)  (%s)\n",strerror(errno));
        return 1;
    }
    
    /*
     * set result stat then try a select if it can take
     * awhile. This is dirty but works
     */
    int res = connect(sock,(struct sockaddr *)&scanaddr, sizeof(scanaddr));
    
    if (res < 0) {
        if (errno == EINPROGRESS) {
            timeout.tv_sec = timeoutSeconds;
            timeout.tv_usec = 0;
            FD_ZERO(&wset);
            FD_SET(sock, &wset);
            int rc = select(sock + 1, NULL, &wset, NULL, &timeout);
            
            /* This works great on dead hosts */
            if (rc == 0 && errno != EINTR) {
                close (sock);
                return 1;
            }
        }
    }
    
    close(sock);
    return 0;
}

#pragma mark - Init

- (id)init 
{
	self = [super init];
	if (self) {
		[self setHostConfig:nil];
    }
	
    return self;
}

- (id)initWithDefaults:(NSDictionary *)aDictionary
{
	self = [super init];
	if (self) {
		[self setHostConfig:[self mpHostConfig:aDictionary]];
    }
    return self;
}


#pragma -

- (BOOL)isHostReachable:(NSString *)aHost
{
	BOOL isValid, result = 0;
	const char *host = [aHost UTF8String];
    
    SCNetworkConnectionFlags flags = 0;
    isValid = SCNetworkCheckReachabilityByName(host, &flags);
    if (isValid && ((flags & kSCNetworkFlagsReachable) && !(flags & kSCNetworkFlagsConnectionRequired))) 
    {
        result = YES;
    }
	
	return result;    
}

- (BOOL)isHostURLReachable:(NSString *)aURL
{
	BOOL isValid, result = 0;
	
	NSURL *theURL = [NSURL URLWithString:aURL];
	const char *host = [[theURL host] UTF8String];
    
    SCNetworkConnectionFlags flags = 0;
    isValid = SCNetworkCheckReachabilityByName(host, &flags);
    if (isValid && ((flags & kSCNetworkFlagsReachable) && !(flags & kSCNetworkFlagsConnectionRequired))) 
    {
        result = YES;
    }
	
	return result;    
}

- (BOOL)isURLValid:(NSString *)aURL returnCode:(int)aReturnCode
{
	BOOL result = 0;
	NSURL *theURL = [NSURL URLWithString:aURL];
	NSURLRequest *request = [NSURLRequest requestWithURL:theURL];
	NSHTTPURLResponse *response = nil;
	NSError *error = nil;
	[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	
	if (error) {
		qlinfo(@"error: %@",error.localizedDescription);
	}
	
	
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
	int statusCode = (int)[httpResponse statusCode];
	if (statusCode == aReturnCode) {
		result = YES;
	} else {
		qlerror(@"isURLValid[statusCode]: %d",statusCode);
		result = NO;
	}
	
	return result;
}

- (BOOL)isServerReachable:(NSString *)aHost port:(int)aPort connection:(NSString *)aHTTP
{
	/* This is cheating ...
	 I was having a issue that was impossible to track down where "isPortReachable"
	 would crash once or twice a day. I'm thinking it's a thread issue but I'm unable
	 to reproduce the issue.
	 
	 So I created a dummy web service to check to see if we were up and running.
	*/
	/*
	@try {
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%d%@?method=WSLTest",aHTTP,aHost,aPort,WS_CLIENT_FILE]];
        qldebug(@"isServerReachable url: %@",url);
		ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
		[request setValidatesSecureCertificate:NO];
		[request setTimeOutSeconds:10];
		[request startSynchronous];
		NSError *error = [request error];
		if (!error) {
			NSString *response = [request responseString];
            qltrace(@"%@",response);
			return YES;
		} else {
			qlerror(@"%@[%d]: %@",aHost,(int)[error code],[error localizedDescription]);
		}

	}
	@catch (NSException * e) {
		qlerror(@"%@",[e description]);
        qlinfo(@"isServerReachable NSException: %@",[e description]);
	}
     */
    qlerror(@"isServerReachable always returns false");
	return NO;
}

- (BOOL)isPortReachable:(int)aPort host:(NSString *)aHost
{
    return [self isPortReachable:aPort host:aHost withTimeout:DEFAULT_TIMEOUT];
}

- (BOOL)isPortReachable:(int)aPort host:(NSString *)aHost withTimeout:(int)aTimeout
{
    BOOL result = NO;
    @try {
        const char *addr = [aHost cStringUsingEncoding:NSASCIIStringEncoding];
        
        short int sock = -1;        // the socket descriptor
        struct hostent *host_info;  // host info structure
        struct sockaddr_in address; // address structures
        
        bzero((char *)&address, sizeof(address));  // init addr struct
        address.sin_addr.s_addr = inet_addr(addr); // assign the address
        address.sin_port = htons(aPort);           // translate int2port num
        
        // Hostname resolution
        if ((host_info = gethostbyname(addr))) {
            bcopy(host_info->h_addr,(char *)&address.sin_addr,host_info->h_length);
        } else if ((address.sin_addr.s_addr = inet_addr(addr)) == INADDR_NONE) {
            qlinfo(@"Could not resolve host, %@",aHost);
            goto done;
        }
        
        // isalive(address)
        if (isAliveWithTimeout(address, aTimeout)) {
            result = NO;
            goto done;
        }
        
        // So far so good - the host exists and is up; check the port and report
        close (sock);
        sock = socket(AF_INET, SOCK_STREAM, 0);
        if (connect(sock,(struct sockaddr *)&address,sizeof(address)) == 0) {
            //printf("%i is open on %s\n", port, argv[2]);
            result = YES;
        } else {
            //printf("%i is not open on %s\n", port, argv[2]);
            qlinfo(@"%d is not open on %@",aPort,aHost);
        }
        
        close(sock);
    }
    @catch (NSException * e) {
        qlerror(@"%@",[e description]);
    }
    
done:
    return result;
}

- (BOOL)pingURLHostWithPort:(NSString *)aHost port:(int)aPort scheme:(NSString *)aScheme
{
    return [self isServerReachable:aHost port:aPort connection:aScheme];
}         

- (BOOL)pingHostWithPort:(NSString *)aHost port:(int)aPort
{
	/*
	if ([self isHostReachable:aHost] == NO) {
		return NO;
	}
	if ([self isPortReachable:aPort host:aHost] == NO) {
		return NO;
	}
	
	// The only way I got here is if both were true
	return YES;
	*/
	
	BOOL res = NO;
	NSDictionary *d = [[NSDictionary alloc] initWithDictionary:[self mpHostConfig]];
	if ([self isServerReachable:[d objectForKey:@"HTTP_HOST"] port:[[d objectForKey:@"HTTP_HOST_PORT"] intValue] connection:[d objectForKey:@"HTTP_PREFIX"]] == YES) {
		res = YES;
	}
	return res;
}

- (NSDictionary *)mpHostConfig
{
	return [self mpHostConfigUsingFile:AGENT_PREFS_PLIST];
}

- (NSDictionary *)mpHostConfig:(NSDictionary *)aDefaults
{
	BOOL mpHostIsReachable = NO;
	NSString *aHOST = @"127.0.0.1";
	NSString *aPORT = @"2600";
	NSString *HTTP_PREFIX = @"http";
	
	NSMutableDictionary *_res = [NSMutableDictionary dictionary];
	[_res setObject:HTTP_PREFIX forKey:@"HTTP_PREFIX" defaultObject:@"http"];
	[_res setObject:aHOST forKey:@"HTTP_HOST" defaultObject:@"127.0.0.1"];
	[_res setObject:aPORT forKey:@"HTTP_HOST_PORT" defaultObject:@"2600"];	
	[_res setObject:aPORT forKey:@"HTTP_HOST_REACHABLE" defaultObject:[NSNumber numberWithBool:mpHostIsReachable]];
	[_res setObject:[NSString stringWithFormat:@"%@://%@:%@%@",HTTP_PREFIX,aHOST,aPORT,WS_CLIENT_FILE] forKey:@"MP_JSON_URL"];
	[_res setObject:[NSString stringWithFormat:@"%@://%@:%@",HTTP_PREFIX,aHOST,aPORT] forKey:@"MP_JSON_URL_PLAIN"];
	
	if (!aDefaults) {
		qlerror(@"Defaults dictionary was nil. No config can be checked.");
		return (NSDictionary *)_res;
	}
	
	// Create the WebService URL Path
	if ([aDefaults hasKey:@"MPServerSSL"]) {
		if ([[aDefaults objectForKey:@"MPServerSSL"] isEqualToString:@"1"] == TRUE) {
			HTTP_PREFIX = @"https";	
		}
	}
	[_res setObject:HTTP_PREFIX forKey:@"HTTP_PREFIX" defaultObject:@"http"];
	
	
	if ([aDefaults hasKey:@"MPServerAddress"]) {
		aHOST = [NSString stringWithString:[aDefaults objectForKey:@"MPServerAddress"]];
	}
	if ([aDefaults hasKey:@"MPServerPort"]) {
		aPORT = [NSString stringWithString:[aDefaults objectForKey:@"MPServerPort"]];
	}
	
	if ([self isServerReachable:aHOST port:[aPORT intValue] connection:HTTP_PREFIX] == NO)
	{
		qlinfo(@"%@ is unreachable. Attempting to use proxy.",aHOST);
		if ([aDefaults objectForKey:@"MPProxyEnabled"] || [aDefaults objectForKey:@"MPProxyIsEnabled"]) {
			if ([[aDefaults objectForKey:@"MPProxyEnabled"] isEqual:@"1"] || [[aDefaults objectForKey:@"MPProxyIsEnabled"] isEqual:@"1"]) {
				qlinfo(@"Proxy is enabled, testing if reachable.");
				// Define the server
				if ([aDefaults objectForKey:@"MPProxyServerAddress"]) {
					aHOST = [aDefaults objectForKey:@"MPProxyServerAddress"];
					qlinfo(@"Setting server to %@.", aHOST);
				} else {
					qlinfo(@"Proxy server is not configured, defaulting port to MPServerAddress.");
				}
				// Define the port
				if ([aDefaults objectForKey:@"MPProxyServerPort"]) {
					aPORT = [aDefaults objectForKey:@"MPProxyServerPort"];
					qlinfo(@"Setting server port to %@.", aPORT);
				} else if ([aDefaults objectForKey:@"MPProxyPort"]) {
					aPORT = [aDefaults objectForKey:@"MPProxyPort"];
					qlinfo(@"Setting server port to %@.", aPORT);
				} else {
					qlinfo(@"Proxy port is not configured, defaulting port to MPServerPort.");
					qlinfo(@"Setting server port to %@.", aPORT);
				}
				
                // Re-Test Connection
				if ([self isServerReachable:aHOST port:[aPORT intValue] connection:HTTP_PREFIX] == NO) {
					mpHostIsReachable = NO;
				} else {
					mpHostIsReachable = YES;
				}
				
			} else {
				qlinfo(@"MPProxy is configured, but not enabled.");
			}	
		} else {
			qlinfo(@"MPProxy is not enabled.");
		}
	} else {
		mpHostIsReachable = YES;
	}
	[_res setObject:HTTP_PREFIX forKey:@"HTTP_PREFIX" defaultObject:@"http"];
	[_res setObject:aHOST forKey:@"HTTP_HOST" defaultObject:@"127.0.0.1"];
	[_res setObject:aPORT forKey:@"HTTP_HOST_PORT" defaultObject:@"2600"];	
	[_res setObject:aPORT forKey:@"HTTP_HOST_REACHABLE" defaultObject:[NSNumber numberWithBool:mpHostIsReachable]];
	[_res setObject:[NSString stringWithFormat:@"%@://%@:%@%@",HTTP_PREFIX,aHOST,aPORT,WS_CLIENT_FILE] forKey:@"MP_JSON_URL"];
	[_res setObject:[NSString stringWithFormat:@"%@://%@:%@",HTTP_PREFIX,aHOST,aPORT] forKey:@"MP_JSON_URL_PLAIN"];
	NSDictionary *result = [NSDictionary dictionaryWithDictionary:_res];
	qldebug(@"mpHostConfig=%@",result);
	return result;	
}

- (NSDictionary *)mpHostConfigUsingFile:(NSString *)aDefaultsFile;
{
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:aDefaultsFile]) {
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:aDefaultsFile];	
		return [self mpHostConfig:d];
	}
	
	return nil;
}

@end
