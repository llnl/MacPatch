//
//  MPResult.m
//  MPLibrary
//
//  Created by Charles Heizer on 5/20/16.
//
//

#import "MPResult.h"

#undef  ql_component
#define ql_component lcl_cMPResult

@interface MPResult()

- (BOOL)isValidResult:(NSDictionary *)aResult;


@end


@implementation MPResult

@synthesize resultData = _resultData;

- (id)initWithResultData:(NSData *)aResultObj
{
    self = [super init];
    if (self) {
        _resultData = aResultObj;
    }
    return self;
}

/**
 *  Returns REST WebService Response it will also translate the result type.
 *  The result type is a string or json encoded string. If result is of type
 *  json, the method will deserialize the JSON string and the result attribute
 *  will be returned at a dictinary.
 *  
 *  A valid REST response will have the following keys 
 *  @"errorno", @"errormsg", @"result", @"resulttype"
 *
 *  @param aType  result attribute type (String or JSON)
 *  @param aError parsing error, use NSError
 *
 *  @return NSDictionary
 */

- (NSDictionary *)returnResultUsingType:(NSString *)aType error:(NSError **)aError
{
    NSError *err = nil;
    NSMutableDictionary *errInfo = [NSMutableDictionary new];
    NSMutableDictionary *resultDict;
    
    id result = [NSJSONSerialization JSONObjectWithData:_resultData options:kNilOptions error:&err];
    qldebug(@"returnResult: %@",result);
    
    // Is valid JSON data
    if (err) {
        if (aError != NULL) *aError = err;
        qlerror(@"%@",err.localizedDescription);
        return nil;
    }
    // Is valid MP result response
    if (![self isValidResult:result]) {
        [errInfo setValue:@"Not a valid result object, missing key(s)." forKey:NSLocalizedDescriptionKey];
        if (aError != NULL) *aError = [NSError errorWithDomain:NSOSStatusErrorDomain code:1001 userInfo:errInfo];
        qlerror(@"Not a valid result object, missing key(s).");
        return nil;
    }
    
    resultDict = [NSMutableDictionary dictionaryWithDictionary:result];
    
    // Has errorno object, and return was not 0
    if ([[result objectForKey:@"errorno"] integerValue] != 0) {
        if (aError != NULL) {
            [errInfo setValue:[result objectForKey:@"errormsg"] forKey:NSLocalizedDescriptionKey];
            *aError = [NSError errorWithDomain:NSOSStatusErrorDomain code:1001 userInfo:errInfo];
        } else {
            qlerror(@"Error [1001]: ErrorNo = %@, %@",[result objectForKey:@"errorno"],[result objectForKey:@"errormsg"]);
        }
        return nil;
    }
    
    if ([[result objectForKey:@"resulttype"] isEqualToString:[@"json" lowercaseString]]) {
        err = nil;
        NSData *resData = [[result objectForKey:@"result"] dataUsingEncoding:NSUTF8StringEncoding];
        id resDecoded = [NSJSONSerialization JSONObjectWithData:resData options:kNilOptions error:&err];
        if (aError != NULL) {
            *aError = err;
            qlerror(@"Error[%d]: %@",(int)err.code,err.localizedDescription);
            return nil;
        }
        [resultDict setObject:resDecoded forKey:@"result"];
    }
    
    return (NSDictionary *)resultDict;
}

#pragma mark - Private

- (BOOL)isValidResult:(NSDictionary *)aResult
{
    NSArray *resKeys = @[@"errorno", @"errormsg", @"result", @"resulttype"];
    int found = 0;
    for (NSString *k in resKeys) {
        for (NSString *r in aResult.allKeys) {
            if ([r isEqualToString:k]) {
                found++;
                break;
            }
        }
    }
    if (found == resKeys.count) {
        return YES;
    } else {
        return NO;
    }
}

@end
