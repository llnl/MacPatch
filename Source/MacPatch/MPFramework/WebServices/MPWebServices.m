//
//  MPWebServices.m
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

#import "MPWebServices.h"
#import "MPFailedRequests.h"
#import "MPSettings.h"

@interface MPWebServices ()
{
    MPSettings *settings;
}

- (void)writePatchGroupCacheFileData:(NSString *)aData;

- (NSData *)requestWithMethodAndParams:(NSString *)aMethod params:(NSDictionary *)aParams error:(NSError **)err;
- (NSData *)requestWithURIAndMethodAndParams:(NSString *)aURI method:(NSString *)aMethod params:(NSDictionary *)aParams error:(NSError **)err;
- (NSData *)postRequestWithMethodAndParams:(NSString *)aMethod params:(NSDictionary *)aParams error:(NSError **)err;

@end

#undef  ql_component
#define ql_component lcl_cMPWEBServices

@implementation MPWebServices

@synthesize clientKey;

-(id)init
{
	self = [super init];
	if (self)
    {
        settings = [MPSettings sharedInstance];
        [self setClientKey:@"NA"];
	}
    return self;
}

#pragma mark requests

- (NSData *)requestWithMethodAndParams:(NSString *)aMethod params:(NSDictionary *)aParams error:(NSError **)err
{
    return [self requestWithURIAndMethodAndParams:WS_CLIENT_FILE method:aMethod params:aParams error:err];
}

- (NSData *)requestWithURIAndMethodAndParams:(NSString *)aURI method:(NSString *)aMethod params:(NSDictionary *)aParams error:(NSError **)err
{
    MPNetConfig *mpNetConfig = [[MPNetConfig alloc] init];
    
    NSError *error = nil;
    NSURLResponse *response;
    
    MPNetRequest *req;
    NSURLRequest *urlReq;
    NSData *res = nil;
    NSArray *servers = [mpNetConfig servers];
    for (MPNetServer *srv in servers)
    {
        qlinfo(@"Trying Server %@",srv.host);
        req = [[MPNetRequest alloc] initWithMPServer:srv];
        req.clientKey = self.clientKey;
        [req setApiURI:aURI];
        error = nil;
        urlReq = [req buildGetRequestForWebServiceMethod:aMethod formData:aParams error:&error];
        if (error) {
            if (err != NULL) {
                *err = error;
            }
            qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
            continue;
        }
        error = nil;
        if (urlReq)
        {
            res = nil;
            res = [req sendSynchronousRequest:urlReq returningResponse:&response error:&error];
            if (error) {
                if (err != NULL) {
                    *err = error;
                }
                qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
                continue;
            }
            // Make any previouse error pointers nil, now that we have a valid host/connection
            if (err != NULL) {
                *err = nil;
            }
            break;
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"NSURLRequest was nil." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1001 userInfo:userInfo];
            qlerror(@"%@",error.localizedDescription);
            if (err != NULL) {
                *err = error;
            }
            continue;
        }
    }
    
    return res;
}

- (NSData *)postRequestWithMethodAndParams:(NSString *)aMethod params:(NSDictionary *)aParams error:(NSError **)err
{
    MPNetConfig *mpNetConfig = [[MPNetConfig alloc] init];

    NSError *error = nil;
    NSURLResponse *response;

    MPNetRequest *req;
    NSURLRequest *urlReq;
    NSData *res = nil;
    NSArray *servers = [mpNetConfig servers];
    for (MPNetServer *srv in servers)
    {
        qlinfo(@"Trying Server %@",srv.host);
        req = [[MPNetRequest alloc] initWithMPServer:srv];
        req.clientKey = self.clientKey;
        [req setApiURI:WS_CLIENT_FILE];
        error = nil;
        urlReq = [req buildRequestForWebServiceMethod:aMethod formData:aParams error:&error];
        if (error) {
            if (err != NULL) {
                *err = error;
            }
            qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
            continue;
        }
        error = nil;
        if (urlReq)
        {
            res = nil;
            res = [req sendSynchronousRequest:urlReq returningResponse:&response error:&error];
            if (error) {
                if (err != NULL) {
                    *err = error;
                }
                qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
                continue;
            }
            // Make any previouse error pointers nil, now that we have a valid host/connection
            if (err != NULL) {
                *err = nil;
            }
            break;
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"NSURLRequest was nil." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1001 userInfo:userInfo];
            qlerror(@"%@",error.localizedDescription);
            if (err != NULL) {
                *err = error;
            }
            continue;
        }
    }

    return res;
}

#pragma mark REST
// New for Python REST Web Services
- (NSData *)getRequestWithURIforREST:(NSString *)aURI error:(NSError **)err
{
    MPNetConfig *mpNetConfig = [[MPNetConfig alloc] init];
    
    NSError *error = nil;
    NSURLResponse *response;
    
    MPNetRequest *req;
    NSURLRequest *urlReq;
    NSData *res = nil;
    NSArray *servers = [mpNetConfig servers];
    for (MPNetServer *srv in servers)
    {
        qlinfo(@"Trying Server %@",srv.host);
        req = [[MPNetRequest alloc] initWithMPServer:srv];
        req.clientKey = self.clientKey;
        error = nil;
        urlReq =  [req buildJSONGETRequest:aURI error:&error];
        if (error) {
            if (err != NULL) {
                *err = error;
            }
            qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
            continue;
        }
        error = nil;
        if (urlReq)
        {
            res = nil;
            res = [req sendSynchronousRequest:urlReq returningResponse:&response error:&error];
            if (error) {
                if (err != NULL) {
                    *err = error;
                }
                qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
                continue;
            }
            // Make any previouse error pointers nil, now that we have a valid host/connection
            if (err != NULL) {
                *err = nil;
            }
            break;
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"NSURLRequest was nil." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1001 userInfo:userInfo];
            qlerror(@"%@",error.localizedDescription);
            if (err != NULL) {
                *err = error;
            }
            continue;
        }
    }

    return res;
}

- (NSData *)postRequestWithURIforREST:(NSString *)aURI body:(id)aBody error:(NSError **)err
{
    MPNetConfig *mpNetConfig = [[MPNetConfig alloc] init];
    
    NSError *error = nil;
    NSURLResponse *response;
    
    MPNetRequest *req;
    NSURLRequest *urlReq;
    NSData *res = nil;
    NSArray *servers = [mpNetConfig servers];
    for (MPNetServer *srv in servers)
    {
        qlinfo(@"Trying Server %@",srv.host);
        req = [[MPNetRequest alloc] initWithMPServer:srv];
        req.clientKey = self.clientKey;
        error = nil;
        if ([aBody isKindOfClass:[NSDictionary class]]) {
            urlReq =  [req buildJSONPOSTRequest:aURI body:aBody error:&error];
        } else if ([aBody isKindOfClass:[NSString class]]) {
            urlReq =  [req buildJSONRequestString:@"POST" uri:aURI body:aBody error:&error];
        } else {
            urlReq =  [req buildJSONRequestString:@"POST" uri:aURI body:nil error:&error];
        }
        
        if (error) {
            if (err != NULL) {
                *err = error;
            }
            qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
            continue;
        }
        error = nil;
        if (urlReq)
        {
            res = nil;
            res = [req sendSynchronousRequest:urlReq returningResponse:&response error:&error];
            if (error) {
                if (err != NULL) {
                    *err = error;
                }
                qlerror(@"[%@][%d](%@ %d): %@",srv.host,(int)srv.port,error.domain,(int)error.code,error.localizedDescription);
                continue;
            }
            // Make any previouse error pointers nil, now that we have a valid host/connection
            if (err != NULL) {
                *err = nil;
            }
            return res;
            break;
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"NSURLRequest was nil." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-1001 userInfo:userInfo];
            qlerror(@"%@",error.localizedDescription);
            if (err != NULL) {
                *err = error;
            }
            continue;
        }
    }
    
    return res;
}

// Parses Request Result using know reponse result type (json, string)
- (id)returnRequestWithType:(NSData *)requestData resultType:(NSString *)resultType error:(NSError **)err
{
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:requestData];
    NSError *error = nil;
    id result;
    
    if ([resultType isEqualToString:@"json"]) {
        result = [jres returnJsonResult:&error];
        qldebug(@"JSON Result: %@",result);
    } else {
        result = [jres returnResult:&error];
    }

    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return nil;
    }
    
    return result;
}

#pragma mark main methods

- (BOOL)getIsClientAgentRegistered:(NSError **)err
{
    return NO;
}

- (NSDictionary *)getServerPubKey:(NSError **)err
{
    return nil;
}

- (BOOL)getIsValidPubKeyHash:(NSString *)aHash error:(NSError **)err
{
    return NO;
}

- (NSDictionary *)getRegisterAgent:(NSString *)aRegKey hostName:(NSString *)hostName clientKey:(NSString *)clientKey error:(NSError **)err
{
    return nil;
}

- (NSDictionary *)registerAgentUsingPayload:(NSDictionary *)regPayload regKey:(NSString *)aRegKey error:(NSError **)err
{
    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:aRegKey forKey:@"registrationKey"];
    [params setObject:[regPayload objectForKey:@"cKey"] forKey:@"clientKey"];
    [params setObject:[regPayload objectForKey:@"CPubKeyPem"] forKey:@"clientPubKeyPem"];
    [params setObject:[regPayload objectForKey:@"CPubKeyDer"] forKey:@"clientPubKeyDer"];
    [params setObject:[regPayload objectForKey:@"ClientHash"] forKey:@"clientPubKeyHash"];
    
    NSData *res = [self requestWithURIAndMethodAndParams:WS_CLIENT_REG method:@"registerClient" params:(NSDictionary *)params error:&error];
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return nil;
    }
    
    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return nil;
    }
    
    return result;
    
    return nil;
}

- (void)writePatchGroupCacheFileData:(NSString *)jData
{
    /*
     PatchGroup Cache File Layout
     NSDictionary:
     PatchGroupName: Default
     rev: xxxx
     data: { }
     PatchGroupName: QA
     rev: xxxx
     data: { }
     */
    
    NSMutableDictionary *patchGroupInfo = [NSMutableDictionary dictionary];
    NSMutableDictionary *patchGroupCacheFileData = [NSMutableDictionary dictionary];
    NSString *patchGroupCacheFile = @"/Library/MacPatch/Client/Data/.gov.llnl.mp.patchgroup.data.plist";
    
    [[NSFileManager defaultManager] removeFileIfExistsAtPath:PATCH_GROUP_PATCHES_PLIST];
    
    NSData *jsonData = [jData dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jError = nil;
    NSString *_rev = @"-1";
    NSMutableDictionary *jDict = (NSMutableDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&jError];
    if (jError) {
        qlerror(@"%@",jError.localizedDescription);
    } else {
        _rev = [jDict objectForKey:@"rev"];
        [patchGroupInfo setObject:_rev forKey:@"rev"];
        [jDict removeObjectForKey:@"rev"];
        [patchGroupInfo setObject:jDict forKey:@"data"];
    }
    
    qlinfo(@"Write patch group hash and data to filesystem.");
    
    [patchGroupCacheFileData setObject:patchGroupInfo forKey:settings.agent.patchGroup];
    [patchGroupCacheFileData writeToFile:patchGroupCacheFile atomically:YES];

#if !__has_feature(objc_arc)
    [mpc release];
#endif

}

#define appleScanResults    0
#define customScanResults   1

/*
- (BOOL)postClientAVData:(NSDictionary *)aDict error:(NSError **)err
{
    MPJsonResult *jres = [[MPJsonResult alloc] init];

    // Request
    NSError *error = nil;
    NSString *jSrlData = [jres serializeJSONDataAsString:aDict error:&error];
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }

    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:_cuuid, @"clientID", @"SAV", @"avAgent",jSrlData, @"jsonData", nil];
    NSData *res = [self requestWithMethodAndParams:@"PostClientAVData" params:params error:&error];
    if (error)
    {
        NSMutableDictionary *errDict = [[NSMutableDictionary alloc] init];
        [errDict setObject:aDict forKey:@"aDict"];
        MPFailedRequests *mpf = [[MPFailedRequests alloc] init];
        [mpf addFailedRequest:@"PostClientAVData" params:errDict errorNo:error.code errorMsg:error.localizedDescription];
        mpf = nil;

		if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }

    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        qlerror(@"SAV Client Data was not posted to webservice.");
        return NO;
    }

    qlinfo(@"SAV Client Data was posted to webservice.");
    return YES;
}
*/
- (NSString *)getLatestAVDefsDate:(NSError **)err
{
    // Get Host Arch Type
    NSString *_theArch = @"x86";
	if ([[MPSystemInfo hostArchitectureType] isEqualToString:@"ppc"]) {
		_theArch = @"ppc";
	}

    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:@"SAV" forKey:@"avAgent"];
    [params setObject:_theArch forKey:@"theArch"];
    NSData *res = [self requestWithMethodAndParams:@"GetAVDefsDate" params:(NSDictionary *)params error:&error];
    if (error)
    {
		if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return @"";
    }

    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return @"NA";
    }

    return result;
}

- (NSString *)getAvUpdateURL:(NSError **)err
{
    // Get Host Arch Type
    NSString *_theArch = @"x86";
	if ([[MPSystemInfo hostArchitectureType] isEqualToString:@"ppc"]) {
		_theArch = @"ppc";
	}

    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:@"SAV" forKey:@"avAgent"];
    [params setObject:_theArch forKey:@"theArch"];
    NSData *res = [self requestWithMethodAndParams:@"GetAVDefsFile" params:(NSDictionary *)params error:&error];
    if (error)
    {
		if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return @"NA";
    }

    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnJsonResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return @"NA";
    }

    return [result objectForKey:@"result"];
}

- (BOOL)postSAVDefsDataXML:(NSString *)aAVXML encoded:(BOOL)aEncoded error:(NSError **)err
{
    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:aAVXML forKey:@"xml"];
    [params setObject:(aEncoded ? @"true" : @"false") forKey:@"encoded"];
    NSData *res = [self requestWithMethodAndParams:@"PostSavAVDefs" params:(NSDictionary *)params error:&error];
    if (error)
    {
        NSMutableDictionary *errDict = [[NSMutableDictionary alloc] init];
        [errDict setObject:aAVXML forKey:@"aAVXML"];
        [errDict setObject:[NSNumber numberWithBool:aEncoded] forKey:@"aEncoded"];
        MPFailedRequests *mpf = [[MPFailedRequests alloc] init];
        [mpf addFailedRequest:@"postSAVDefsDataXML" params:errDict errorNo:error.code errorMsg:error.localizedDescription];
        mpf = nil;

		if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }

    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnJsonResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }

    qlinfo(@"Data was successfully posted.");
    return YES;
}

- (BOOL)postJSONDataForMethod:(NSString *)aMethod data:(NSDictionary *)aData error:(NSError **)err
{
    MPJsonResult        *jres           = [[MPJsonResult alloc] init];
	NSMutableArray		*resultsData	= [[NSMutableArray alloc] init];
	NSMutableDictionary *resultDict		= [[NSMutableDictionary alloc] init];
	// Get Data As Array
	[resultsData addObject:[aData allValues]];

	// Create final Dictionary to gen JSON data for...
	[resultDict setObject:[aData allKeys] forKey:@"COLUMNS"];
	[resultDict setObject:resultsData forKey:@"DATA"];

	// Create the JSON String
    NSError *l_err = nil;
    NSString *jData = [jres serializeJSONDataAsString:resultDict error:&l_err];
	if (l_err) {
		qlerror(@"%@",[l_err localizedDescription]);
		return NO;
	}

    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:@"json" forKey:@"type"];
    [params setObject:jData forKey:@"data"];
    [params setObject:@"NA" forKey:@"signature"];
    NSData *res = [self requestWithMethodAndParams:aMethod params:(NSDictionary *)params error:&error];
    if (error)
    {
        NSMutableDictionary *errDict = [[NSMutableDictionary alloc] init];
        [errDict setObject:aMethod forKey:@"aMethod"];
        [errDict setObject:aData forKey:@"aData"];
        MPFailedRequests *mpf = [[MPFailedRequests alloc] init];
        [mpf addFailedRequest:@"postJSONDataForMethod" params:errDict errorNo:error.code errorMsg:error.localizedDescription];
        mpf = nil;

		if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }
    if (!res) {
        return NO;
    }

    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }

    qlinfo(@"Data was successfully posted.");
    return YES;
}

#pragma mark - OS Migration

- (NSString *)postOSMigrationStatus:(NSString *)aStatus label:(NSString *)Label migrationID:(NSString *)migrationID error:(NSError **)err
{
    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:aStatus forKey:@"action"];
    [params setObject:[[MPSystemInfo osVersionInfo] objectForKey:@"ProductUserVisibleVersion"] forKey:@"os"];
    [params setObject:Label forKey:@"label"];
    [params setObject:migrationID forKey:@"migrationID"];
    NSData *res = [self requestWithMethodAndParams:@"PostOSMigration" params:(NSDictionary *)params error:&error];
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return nil;
    }
    
    // MPJsonResult does all of the error checking on the result
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return nil;
    }
    
    return result;
}

- (int)postOSMigrationStatusNew:(NSString *)aStatus label:(NSString *)Label migrationID:(NSString *)migrationID error:(NSError **)err
{
    NSError *error = nil;
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    // Request, convert params to json
    NSDictionary *params = @{@"clientID":settings.ccuid, @"action":aStatus,@"os": [[MPSystemInfo osVersionInfo] objectForKey:@"ProductUserVisibleVersion"],
                             @"label":Label, @"migrationID":migrationID};

    NSString *jData = [jres serializeJSONDataAsString:params error:&error];
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return 1;
    }
    
    NSString *uri = [NSString stringWithFormat:@"/api/v1/provisioning/migration/%@",settings.ccuid];
    id res = [self restPostRequestforURI:uri body:jData resultType:@"string" error:&error];
    qldebug(@"[postOSMigrationStatusNew] %@",res);
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return 1;
    }
    
    return 0;
}


#pragma mark - Helper Methods for REST WS

- (id)restGetRequestforURI:(NSString *)aURI resultType:(NSString *)resType error:(NSError **)err
{
    NSError *wsErr = nil;
    NSData *reqData;
    id result;
    
    @try
    {
        reqData = [self getRequestWithURIforREST:aURI error:&wsErr];
        if (wsErr) {
            if (err != NULL) *err = wsErr;
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
            return nil;
        } else {
            // Parse JSON result, if error code is not 0
            wsErr = nil;
            result = [self returnRequestWithType:reqData resultType:resType error:&wsErr];
            if (wsErr) {
                if (err != NULL) *err = wsErr;
                logit(lcl_vError,@"%@",wsErr.localizedDescription);
                return nil;
            }
            logit(lcl_vDebug,@"%@",result);
            return result;
        }
        
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
    }
    // Should not get here
    return nil;
}

- (id)restPostRequestforURI:(NSString *)aURI body:(NSString *)aBody resultType:(NSString *)resType error:(NSError **)err
{
    NSError *wsErr = nil;
    NSData *reqData;
    id result;
    
    @try
    {
        logit(lcl_vDebug,@"JSON Data to post: %@",aBody);
        wsErr = nil;
        reqData = [self postRequestWithURIforREST:aURI body:aBody error:&wsErr];
        if (wsErr) {
            if (err != NULL) *err = wsErr;
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
            return nil;
        } else {
            // Parse JSON result, if error code is not 0
            wsErr = nil;
            result = [self returnRequestWithType:reqData resultType:resType error:&wsErr];
            if (wsErr) {
                if (err != NULL) *err = wsErr;
                logit(lcl_vError,@"%@",wsErr.localizedDescription);
                return nil;
            }
            
            // Error Code is 0 and result is empty then we are done.
            if ([self isOfNSStringType:result]) {
                return @"";
            }
            
            logit(lcl_vDebug,@"[restPostRequestforURI] result: %@",result);
            return result;
        }
        
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
    }
    // Should not get here
    return nil;
}

- (BOOL)isOfNSStringType:(id)obj
{
    if ([[obj className] isMemberOfClass: [NSString class]]) {
        return YES;
    }
    if ([[obj class] isKindOfClass: [NSString class]]) {
        return YES;
    }
    if ([[obj classForCoder] isSubclassOfClass: [NSString class]]) {
        return YES;
    }
    
    return NO;
}


#pragma mark Convience methods

/*
- (void)runCheckIn
{
    NSDictionary *agentData = [self agentData];
    if (!agentData)
    {
        logit(lcl_vError,@"Agent data is nil, can not post client checkin data.");
        return;
    }
    
    MPWSResult *result;
    MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
    NSString *urlPath = [@"/api/v1/client/checkin" stringByAppendingPathComponent:[si g_cuuid]];
    result = [req runSyncPOST:urlPath body:agentData];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vInfo,@"Running client base checkin, returned true.");
        // Process Setting Revisions
        [self updateGroupSettings:result.result];
    } else {
        logit(lcl_vError,@"Running client base checkin, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
    }
    
    logit(lcl_vInfo,@"Running client check in completed.");
    
    return;
}
*/

- (NSString *)patchGroupContentUrlPath
{
    NSString *urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/group/%@",settings.ccuid];
    return urlPath;
}

- (NSDictionary *)getPatchGroupContentCLI:(NSError **)err
{
    MPWSResult *result;
    MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
    NSString *urlPath = [self patchGroupContentUrlPath];
    result = [req runSyncGET:urlPath];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        // Process Results
        logit(lcl_vDebug,@"Patch Group Patches: %@",result.result);
        return result.result;
    } else {
        logit(lcl_vError,@"Running client base checkin, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
    }
    
    logit(lcl_vInfo,@"Running client check in completed.");
    
    return nil;
}

- (NSDictionary *)getPatchGroupContent:(NSError **)err
{
    /*
    NSError *wsErr = nil;
    NSString *uri;
    NSData *reqData;
    id result;
    
    @try
    {
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/group/%@/%@",[_defaults objectForKey:@"PatchGroup"],settings.ccuid];
        reqData = [self getRequestWithURIforREST:uri error:&wsErr];
        if (wsErr) {
            if (err != NULL) *err = wsErr;
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
            return nil;
        } else {
            // Parse JSON result, if error code is not 0
            wsErr = nil;
            result = [self returnRequestWithType:reqData resultType:@"json" error:&wsErr];
            if (wsErr) {
                if (err != NULL) *err = wsErr;
                logit(lcl_vError,@"%@",wsErr.localizedDescription);
                return nil;
            }
            logit(lcl_vDebug,@"%@",result);
            
            wsErr = nil;
            MPJsonResult *jres = [[MPJsonResult alloc] init];
            NSString *jstr = [jres serializeJSONDataAsString:(NSDictionary *)result error:NULL];
            [self writePatchGroupCacheFileData:jstr];
            if (wsErr) {
                if (err != NULL) {
                    *err = wsErr;
                } else {
                    qlerror(@"%@",wsErr.localizedDescription);
                }
                return nil;
            }
            
            return result;
        }
        
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
    }
    // Should not get here
    return nil;
     */
}

- (NSString *)getPatchGroupContentRev:(NSError **)err
{
    NSError *wsErr = nil;
    NSString *uri;
    NSData *reqData;
    id result;
    
    @try
    {
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/group/rev/%@/%@", settings.agent.patchGroup, settings.ccuid];
        reqData = [self getRequestWithURIforREST:uri error:&wsErr];
        if (wsErr) {
            if (err != NULL) *err = wsErr;
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
            return nil;
        } else {
            // Parse JSON result, if error code is not 0
            wsErr = nil;
            result = [self returnRequestWithType:reqData resultType:@"string" error:&wsErr];
            if (wsErr) {
                if (err != NULL) *err = wsErr;
                logit(lcl_vError,@"%@",wsErr.localizedDescription);
                return nil;
            }
            
            qldebug(@"result: %@",result);
            return result;
        }
        
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
    }
    // Should not get here
    return nil;
}

- (NSDictionary *)getCriticalPatchGroupContent:(NSError **)err
{
    NSError *wsErr = nil;
    NSString *uri;
    NSData *reqData;
    id result;
    
    @try
    {
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/group/critical/%@",settings.ccuid];
        reqData = [self getRequestWithURIforREST:uri error:&wsErr];
        if (wsErr) {
            if (err != NULL) *err = wsErr;
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
            return nil;
        } else {
            // Parse JSON result, if error code is not 0
            wsErr = nil;
            result = [self returnRequestWithType:reqData resultType:@"json" error:&wsErr];
            if (wsErr) {
                if (err != NULL) *err = wsErr;
                logit(lcl_vError,@"%@",wsErr.localizedDescription);
                return nil;
            }
            
            logit(lcl_vDebug,@"%@",result);
            return result;
        }
        
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
    }
    // Should not get here
    return nil;
}

- (NSDictionary *)getMPServerList:(NSError **)err
{
    NSError *error = nil;
    NSDictionary *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/server/list/%@",settings.ccuid];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (NSDictionary *)getMPServerListVersion:(NSString *)aVersion listid:(NSString *)aListID error:(NSError **)err
{
    NSError *error = nil;
    NSDictionary *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/server/list/version/%@/%@",aListID,settings.ccuid];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (BOOL)postDataMgrData:(NSString *)aDataMgrJSON error:(NSError **)err
{
    NSError *error = nil;
    id result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/client/inventory/%@",settings.ccuid];
    result = [self restPostRequestforURI:aURI body:aDataMgrJSON resultType:@"string" error:&error];
    if (err != NULL) *err = error;
    if (([result isEqualToString:@""] || (result == nil)) && !error) {
        return YES;
    } else {
        return NO;
    }
}

- (NSArray *)getCustomPatchScanList:(NSError **)err
{
    return [self getCustomPatchScanListWithSeverity:nil error:err];
}

- (NSArray *)getCustomPatchScanListWithSeverity:(NSString *)aSeverity error:(NSError **)err
{
    NSString *patchState = @"Production";
    
    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:patchState forKey:@"state"];
    
    NSString *uri;
    if (!aSeverity) {
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/scanlist/%@/%@",settings.ccuid, patchState];
    } else {
        // Set OS Level *, any OS
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/scanlist/%@/%@/*/%@",settings.ccuid, patchState, aSeverity];
    }
    NSDictionary *res = [self restGetRequestforURI:uri resultType:@"json" error:&error];
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return nil;
    }
    NSString *aCMDName1, *aCMDName2;
    if ([res objectForKey:@"patches"] && [[res objectForKey:@"patches"] isKindOfClass:[NSArray class]]) {
        
        if ([[patchState lowercaseString] isEqualToString:@"all"]) {
            aCMDName1 = @"Production";
            aCMDName2 = @"QA";
        } else {
            aCMDName1 = patchState;
            aCMDName2 = patchState;
        }
        
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"patch_state contains[cd] %@ OR patch_state contains[cd] %@",aCMDName1, aCMDName2];
        NSArray *filteredarray = [[res objectForKey:@"patches"] filteredArrayUsingPredicate:pred];
        
        
        return filteredarray;
    } else {
        qlerror(@"patches key in dictionary was not found.");
        return nil;
    }
}

- (BOOL)postClientScanDataWithType:(NSArray *)scanData type:(NSInteger)aType error:(NSError **)err
{
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    
    // Request
    NSError *error = nil;
    NSDictionary *pData = [NSDictionary dictionaryWithObjectsAndKeys:scanData, @"rows", nil];
    NSString *jData = [jres serializeJSONDataAsString:pData error:&error];
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }
    
    NSString *uri;
    // 1 = Apple, 2 = Third
    if (aType == 0) {
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/scan/1/%@",settings.ccuid];
    } else if ( aType == 1 ) {
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/scan/2/%@",settings.ccuid];
    } else {
        //Err
        uri = [NSString stringWithFormat:@"/api/v1/client/patch/scan/3/<string:cuuid>"];
    }
    qldebug(@"[postClientScanDataWithType][uri] %@",uri);
    error = nil;
    
    qldebug(@"[postClientScanDataWithType][body] %@",jData);
    id res = [self restPostRequestforURI:uri body:jData resultType:@"string" error:&error];
    qldebug(@"[postClientScanDataWithType] %@",res);
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return NO;
    }
    
    qlinfo(@"Client Scan Data was posted to webservice.");
    return YES;
}

- (NSDictionary *)getAgentUpdates:(NSString *)curAppVersion build:(NSString *)curBuildVersion error:(NSError **)err
{
    NSError *error = nil;
    NSDictionary *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/agent/update/%@/%@/%@",settings.ccuid, curAppVersion, curBuildVersion];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (NSDictionary *)getAgentUpdaterUpdates:(NSString *)curAppVersion error:(NSError **)err
{
    NSError *error = nil;
    NSDictionary *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/agent/updater/%@/%@",settings.ccuid, curAppVersion];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (NSDictionary *)getSUSServerList:(NSError **)err
{
    NSDictionary *os = [MPSystemInfo osVersionOctets];
    
    NSError *error = nil;
    NSDictionary *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/sus/catalogs/list/%@/%@/%@",[os objectForKey:@"major"],[os objectForKey:@"minor"],settings.ccuid];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (BOOL)clientHasInvDataInDB:(NSError **)err
{
    NSError *error = nil;
    NSString *result = nil;
    id raw_res;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/client/inventory/state/%@",settings.ccuid];
    raw_res = [self restGetRequestforURI:aURI resultType:@"string" error:&error];
    if (err != NULL) *err = error;
    
    if ([raw_res isKindOfClass:[NSNumber class]]) {
        result = [raw_res stringValue];
    } else if ([raw_res isKindOfClass:[NSString class]]) {
        result = raw_res;
    } else {
        qlerror(@"Result is not a supported type.");
        return NO;
    }

    if ([result isEqualToString:@"1"]) {
        return YES;
    } else {
        return NO;
    }
}

- (int)postClientHasInvData:(NSError **)err
{
    // Request
    NSError *error = nil;
    NSString *uri = [NSString stringWithFormat:@"/api/v1/client/inventory/state/%@",settings.ccuid];
    id res = [self restPostRequestforURI:uri body:nil resultType:@"string" error:&error];
    qldebug(@"[postClientHasInvData] %@",res);
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return 1;
    }
    
    return 0;
}

- (BOOL)postPatchInstallResultsToWebService:(NSString *)aPatch patchType:(NSString *)aPatchType error:(NSError **)err
{
    NSError *error = nil;
    id result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/client/patch/install/%@/%@/%@",aPatch,aPatchType,settings.ccuid];
    result = [self restPostRequestforURI:aURI body:nil resultType:@"string" error:&error];
    qldebug(@"[postPatchInstallResultsToWebService][result]: %@",result);
    if (err != NULL) *err = error;
    if ([result isEqualToString:@""] && !error) {
        return YES;
    } else {
        return NO;
    }
}

- (NSArray *)getProfileIDDataForClient:(NSError **)err
{
    NSError *error = nil;
    NSArray *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/client/profiles/%@",settings.ccuid];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (id)getSWDistGroups:(NSError **)err
{
    return [self getSWDistGroupsWithState:@"1" error:err];
}

- (id)getSWDistGroupsWithState:(NSString *)aState error:(NSError **)err
{
    NSError *error = nil;
    id result = nil;
    
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/sw/groups/%@/%@",settings.ccuid, aState];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (id)getSWTasksForGroup:(NSString *)aGroupName error:(NSError **)err
{
    if (!aGroupName) {
        NSError *tErr = [NSError errorWithDomain:NSCocoaErrorDomain code:-1000 userInfo:@{NSLocalizedDescriptionKey: @"No Group Name Found"}];
        if (err != NULL) *err = tErr;
        return nil;
    }
    
    NSError *error = nil;
    id result = nil;
    
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/sw/tasks/%@/%@",settings.ccuid, aGroupName];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (int)postSWInstallResults:(NSDictionary *)aParams error:(NSError **)err
{
    NSError *error = nil;
    NSString *bodyStr;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:aParams options:0 error:&error];
    if (error) {
        if (err != NULL) *err = error;
        qlerror(@"%@",error.localizedDescription);
        return 1;
    } else {
        bodyStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        qldebug(@"Install data as JSON: %@", bodyStr);
    }
    
    
    id result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/sw/installed/%@",settings.ccuid];
    result = [self restPostRequestforURI:aURI body:bodyStr resultType:@"string" error:&error];
    if (err != NULL) *err = error;
    if ([result isEqualToString:@""] && !error) {
        qlinfo(@"Data was successfully posted.");
        return 0;
    } else {
        qlinfo(@"Install data failed to post.");
        qldebug(@"Install data: %@",aParams);
        return 1;
    }
}

- (id)getSWTaskForID:(NSString *)aTaskID error:(NSError **)err
{
    if (!aTaskID) {
        NSError *tErr = [NSError errorWithDomain:NSCocoaErrorDomain code:-1000 userInfo:@{NSLocalizedDescriptionKey: @"No TaskID Found"}];
        if (err != NULL) *err = tErr;
        return nil;
    }
    
    
    NSError *error = nil;
    id result = nil;
    
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/sw/task/%@/%@",settings.ccuid, aTaskID];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    qldebug(@"result: %@",result);
    if (err != NULL) *err = error;
    return result;
}

- (NSString *)getHashForPluginName:(NSString *)pName pluginBunleID:(NSString *)bundleID pluginVersion:(NSString *)pVer error:(NSError **)err
{
    NSError *error = nil;
    NSString *result = nil;
    
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/agent/plugin/hash/%@/%@/%@/%@",settings.ccuid, pName, bundleID, pVer];
    result = [self restGetRequestforURI:aURI resultType:@"string" error:&error];
    qldebug(@"result: %@",result);
    if (err != NULL) *err = error;
    return result;
}

// Client Status
- (id)GetClientPatchStatusCount:(NSError **)err
{
    NSError *error = nil;
    NSDictionary *result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/client/patch/status/%@",settings.ccuid];
    result = [self restGetRequestforURI:aURI resultType:@"json" error:&error];
    if (err != NULL) *err = error;
    return result;
}

- (BOOL)postClientAVData:(NSDictionary *)aDict error:(NSError **)err
{
    NSError *error = nil;
    NSString *bodyStr;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:aDict options:0 error:&error];
    if (error) {
        if (err != NULL) *err = error;
        qlerror(@"%@",error.localizedDescription);
        return NO;
    } else {
        bodyStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        qldebug(@"Install data as JSON: %@", bodyStr);
    }
    
    
    id result = nil;
    NSString *aURI = [NSString stringWithFormat:@"/api/v1/client/av/%@",settings.ccuid];
    result = [self restPostRequestforURI:aURI body:bodyStr resultType:@"string" error:&error];
    if (err != NULL) *err = error;
    if ([result isEqualToString:@""] && !error) {
        qlinfo(@"Data was successfully posted.");
        return YES;
    } else {
        qlinfo(@"Install data failed to post.");
        qldebug(@"Install data: %@",aDict);
        return NO;
    }
}

- (NSString *)getLatestAVDefsDate:(NSString *)avType error:(NSError **)err
{
    // Get Host Arch Type
    NSString *_theArch = @"x86";
    if ([[MPSystemInfo hostArchitectureType] isEqualToString:@"ppc"]) {
        _theArch = @"ppc";
    }
    
    // Request
    NSError *error = nil;
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:settings.ccuid forKey:@"clientID"];
    [params setObject:@"SAV" forKey:@"avAgent"];
    [params setObject:_theArch forKey:@"theArch"];
    NSData *res = [self requestWithMethodAndParams:@"GetAVDefsDate" params:(NSDictionary *)params error:&error];
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return @"";
    }
    
    // Parse Main JSON Result
    // MPJsonResult does all of the error checking on the result
    MPJsonResult *jres = [[MPJsonResult alloc] init];
    [jres setJsonData:res];
    error = nil;
    id result = [jres returnResult:&error];
    qldebug(@"JSON Result: %@",result);
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
        return @"NA";
    }
    
    return result;
}

- (BOOL)postAgentReister:(NSDictionary *)aDict regKey:(NSString *)aRegKey error:(NSError **)err
{
    NSError *error = nil;
    NSString *bodyStr;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:aDict options:0 error:&error];
    if (error) {
        if (err != NULL) *err = error;
        qlerror(@"%@",error.localizedDescription);
        return NO;
    } else {
        bodyStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        qldebug(@"Install data as JSON: %@", bodyStr);
    }
    
    id result = nil;
    NSString *aURI;
    if (!aRegKey) {
        aURI = [NSString stringWithFormat:@"/api/v1/client/register/%@",settings.ccuid];
    } else {
        aURI = [NSString stringWithFormat:@"/api/v1/client/register/%@/%@",settings.ccuid,aRegKey];
    }
    qldebug(@"aURI: %@",aURI);
    
    result = [self restPostRequestforURI:aURI body:bodyStr resultType:@"string" error:&error];
    if (err != NULL) *err = error;
    if ([result isEqualToString:@""] && !error) {
        qlinfo(@"Data was successfully posted.");
        return YES;
    } else {
        qlinfo(@"Data failed to post.");
        qldebug(@"Data: %@",aDict);
        return NO;
    }
    
    // Should not get here
    return NO;
}

- (BOOL)getAgentRegStatusWithKeyHash:(NSString *)keyHash error:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
    NSString *aURI;
    if (!keyHash) {
        aURI = [NSString stringWithFormat:@"/api/v1/client/register/status/%@",settings.ccuid];
    } else {
        aURI = [NSString stringWithFormat:@"/api/v1/client/register/status/%@/%@",settings.ccuid,keyHash];
    }
    
    qldebug(@"aURI: %@",aURI);
    result = [self restGetRequestforURI:aURI resultType:@"string" error:&error];
    if (err != NULL) *err = error;
    
    return result;
}

@end
