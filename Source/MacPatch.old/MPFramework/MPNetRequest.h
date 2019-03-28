//
//  MPNetRequest.h
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

#import <Foundation/Foundation.h>
@class MPNetServer;


@protocol MPNetRequestController

@optional

- (void)appendDownloadProgress:(double)aNumber;
- (void)appendDownloadProgressPercent:(NSString *)aPercent;
- (void)downloadStarted;
- (void)downloadFinished;
- (void)downloadError;

@end

@interface MPNetRequest : NSObject <NSURLConnectionDataDelegate, NSURLConnectionDelegate>
{
    id				<MPNetRequestController>controller;
    BOOL            useController;

    MPNetServer     *mpServer;
    NSArray         *mpServerArray;
    NSString        *httpMethod;
    NSString        *method;
    NSString        *apiURI;
    NSDictionary    *apiArgs;


    // User Auth 
    NSString        *userName;
    NSString        *userPass;

    // TLS Auth
    NSString        *tlsCert;
    NSString        *tlsCertPass;

    // Misc
    NSNumber        *dlSize;
    NSNumber        *dlRecievedData;
    NSMutableData   *receivedData;
	BOOL			isRunning;
    int             errorCode;
}

@property (nonatomic, assign) double urlTimeout;
@property (nonatomic, assign, readonly) BOOL useController;
@property (nonatomic, assign, readonly) int errorCode;

@property (nonatomic, strong) MPNetServer *mpServer;
@property (nonatomic, strong) NSArray *mpServerArray;
@property (nonatomic, strong) NSString *httpMethod;
@property (nonatomic, strong) NSString *method;
@property (nonatomic, strong) NSString *apiURI;
@property (nonatomic, strong) NSDictionary *apiArgs;
@property (nonatomic, strong) NSMutableData *receiveData;
@property (nonatomic, assign) BOOL internetActive;
@property (nonatomic, assign, readonly) BOOL isFileDownload;

@property (nonatomic, strong, readonly) NSString *dlFilePath;
@property (nonatomic, strong, readonly) NSString *dlURL;

// User Auth
@property (nonatomic, strong) NSString *userName;
@property (nonatomic, strong) NSString *userPass;
// TLS Auth
@property (nonatomic, strong) NSString *tlsCert;
@property (nonatomic, strong) NSString *tlsCertPass;
// Signatures
@property (nonatomic, strong) NSString *clientKey;

- (id)initWithMPServer:(MPNetServer *)aServer;
- (id)initWithMPServerArray:(NSArray *)aServerArray;
- (id)initWithMPServerAndController:(id <MPNetRequestController>)cont server:(MPNetServer *)aServer;
- (id)initWithMPServerArrayAndController:(id <MPNetRequestController>)controller servers:(NSArray *)aServerArray;

- (NSURLRequest *)buildRequestForWebServiceMethod:(NSString *)wsMethodName formData:(NSDictionary *)paramDict error:(NSError **)error;
- (NSURLRequest *)buildPostRequestForWebServiceMethod:(NSString *)wsMethodName formData:(NSDictionary *)paramDict error:(NSError **)error;
- (NSURLRequest *)buildGetRequestForWebServiceMethod:(NSString *)wsMethodName formData:(NSDictionary *)paramDict error:(NSError **)error;

- (NSURLRequest *)buildDownloadRequest:(NSString *)url;
- (NSURLRequest *)buildDownloadRequest:(NSString *)url error:(NSError **)error;

// REST
// New for Python Web Services
- (NSURLRequest *)buildJSONGETRequest:(NSString *)aURI error:(NSError **)error;
- (NSURLRequest *)buildJSONPOSTRequest:(NSString *)aURI body:(NSDictionary *)aBody error:(NSError **)error;
- (NSURLRequest *)buildJSONRequest:(NSString *)httpMethod uri:(NSString *)aURI body:(NSDictionary *)aBody error:(NSError **)error;
- (NSURLRequest *)buildJSONRequestString:(NSString *)httpMethod uri:(NSString *)aURI body:(NSString *)aBody error:(NSError **)error;

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error;
- (NSString *)downloadFileRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error;

// For use with AFNetworking
- (NSURLRequest *)buildAFDownloadRequest:(NSString *)aURI server:(MPNetServer *)aServer error:(NSError **)error;
@end
