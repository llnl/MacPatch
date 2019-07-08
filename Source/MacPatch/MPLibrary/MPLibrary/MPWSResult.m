//
//  CHWSResult.m
//  MPAgent
//
//  Created by Charles Heizer on 9/15/17.
//  Copyright © 2017 LLNL. All rights reserved.
//

#import "MPWSResult.h"

NSString *const kCHWSResultStatuscode = @"statuscode";
NSString *const kCHWSResultErrormsg = @"errormsg";
NSString *const kCHWSResultErrorno = @"errorno";
NSString *const kCHWSResultResult = @"result";

@interface MPWSResult ()
@end

@implementation MPWSResult

/**
 * Instantiate the instance using the passed dictionary values to set the properties values
 */

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    self = [super init];
    
    if(![dictionary[kCHWSResultErrormsg] isKindOfClass:[NSNull class]]){
        self.errormsg = dictionary[kCHWSResultErrormsg];
    }
    
    if(![dictionary[kCHWSResultErrorno] isKindOfClass:[NSNull class]]){
        self.errorno = [dictionary[kCHWSResultErrorno] integerValue];
    }
    
    if(![dictionary[kCHWSResultResult] isKindOfClass:[NSNull class]]){
        //self.result = [[WSResult alloc] initWithDictionary:dictionary[kCHWSResultResult]];
        self.result = dictionary[kCHWSResultResult];
    }
    
    self.statusCode = 0;
    return self;
}

- (instancetype)initWithJSONData:(NSData *)data
{
    NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:NULL];
    return [self initWithDictionary:dictionary];
}


/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
- (NSDictionary *)toDictionary
{
    NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
    
    if(self.errormsg != nil){
        dictionary[kCHWSResultErrormsg] = self.errormsg;
    }
    dictionary[kCHWSResultErrorno] = @(self.errorno);
    if(self.result != nil){
        //dictionary[kCHWSResultResult] = [self.result toDictionary];
        dictionary[kCHWSResultResult] = self.result;
    }
    dictionary[kCHWSResultStatuscode] = @(self.statusCode);
    return dictionary;
}

/**
 * Implementation of NSCoding encoding method
 */
/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if(self.errormsg != nil) {
        [aCoder encodeObject:self.errormsg forKey:kCHWSResultErrormsg];
    }

    if(self.result != nil) {
        [aCoder encodeObject:self.result forKey:kCHWSResultResult];
    }
    
    [aCoder encodeObject:@(self.errorno) forKey:kCHWSResultErrorno];
    [aCoder encodeObject:@(self.statusCode) forKey:kCHWSResultStatuscode];
}

/**
 * Implementation of NSCoding initWithCoder: method
 */
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    self.statusCode = [[aDecoder decodeObjectForKey:kCHWSResultStatuscode] integerValue];
    self.errormsg   = [aDecoder decodeObjectForKey:kCHWSResultErrormsg];
    self.errorno    = [[aDecoder decodeObjectForKey:kCHWSResultErrorno] integerValue];
    self.result     = [aDecoder decodeObjectForKey:kCHWSResultResult];
    return self;
}

/**
 * Implementation of NSCopying copyWithZone: method
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
    MPWSResult *copy = [MPWSResult new];
    
    copy.statusCode = self.statusCode;
    copy.errormsg = [self.errormsg copy];
    copy.errorno = self.errorno;
    copy.result = [self.result copy];
    
    return copy;
}
@end
