#import "AgentData.h"
#import "CocoaSecurity.h"
#import "UAObfuscatedString.h"

@interface AgentData ()

@property (nonatomic, strong, readwrite) NSDictionary  *dataDict;

@property (nonatomic, strong, readwrite) NSData    *serverPublicKey;
@property (nonatomic, strong, readwrite) NSData    *agentPublicKey;
@property (nonatomic, strong, readwrite) NSData    *agentPrivateKey;
@property (nonatomic, strong, readwrite) NSString  *clientKey;
@property (nonatomic, strong, readwrite) NSString  *schlussel;

- (id)readDataForKey:(NSString *)aKey;
- (void)writeDataForKey:(id)data key:(NSString *)aKey;

@end

@implementation AgentData

@synthesize schlussel;
@synthesize dataDict;
@synthesize clientKey;
@synthesize serverPublicKey;
@synthesize agentPublicKey;
@synthesize agentPrivateKey;

- (id)init
{
	self = [super init];
	if (self)
	{
		schlussel = @"SimpleSecretKey"; //This should be changed
		dataDict = @{@"clientKey":[NSString string],
					 @"agentPublicKey":[NSData data],
					 @"agentPrivateKey":[NSData data],
					 @"serverPublicKey":[NSData data]};
	}
	return self;
}

//===========================================================
//  Getters
//===========================================================
- (NSString *)getClientKey
{
	return [self readDataForKey:@"clientKey"];
}

- (NSData *)getServerPublicKey
{
	return [self readDataForKey:@"serverPublicKey"];
}

- (NSData *)getAgentPublicKey
{
	return [self readDataForKey:@"agentPublicKey"];
}

- (NSData *)getAgentPrivateKey
{
	return [self readDataForKey:@"agentPrivateKey"];
}

//===========================================================
//  Setters
//===========================================================
- (void)setClientKey:(NSString *)aKey
{
	if (clientKey != aKey) {
		clientKey = aKey;
		[self writeDataForKey:aKey key:@"clientKey"];
	}
}

- (void)setServerPublicKey:(NSData *)aKey
{
	if (serverPublicKey != aKey) {
		serverPublicKey = aKey;
		[self writeDataForKey:aKey key:@"serverPublicKey"];
	}
}

- (void)setAgentPublicKey:(NSData *)aKey
{
	if (agentPublicKey != aKey) {
		agentPublicKey = aKey;
		[self writeDataForKey:aKey key:@"agentPublicKey"];
	}
}

- (void)setAgentPrivateKey:(NSData *)aKey
{
	if (agentPrivateKey != aKey) {
		agentPrivateKey = aKey;
		[self writeDataForKey:aKey key:@"agentPrivateKey"];
	}
}


- (BOOL)generateAgentData
{
	return YES;
}

- (id)readDataForKey:(NSString *)aKey
{
	NSDictionary *k = [NSKeyedUnarchiver unarchiveObjectWithFile:AGENT_REG_FILE];
	
	CocoaSecurityResult *sha = [CocoaSecurity sha384:schlussel];
	NSData *aesKey = [sha.data subdataWithRange:NSMakeRange(0, 32)];
	NSData *aesIv = [sha.data subdataWithRange:NSMakeRange(32, 16)];
	CocoaSecurityResult *result = [CocoaSecurity aesDecryptWithBase64:[k objectForKey:aKey] key:aesKey iv:aesIv];
	if ([aKey isEqualToString:@"clientKey"]) {
		return result.utf8String;
	} else {
		return result.data;
	}
}

- (void)writeDataForKey:(id)data key:(NSString *)aKey
{
	NSMutableDictionary *d;
	NSDictionary *k = [NSKeyedUnarchiver unarchiveObjectWithFile:AGENT_REG_FILE];
	d = [NSMutableDictionary dictionaryWithDictionary:k];
	
	CocoaSecurityResult *sha = [CocoaSecurity sha384:schlussel];
	NSData *aesKey = [sha.data subdataWithRange:NSMakeRange(0, 32)];
	NSData *aesIv = [sha.data subdataWithRange:NSMakeRange(32, 16)];
	CocoaSecurityResult *result;
	if([data isKindOfClass:[NSData class]]) {
		result = [CocoaSecurity aesEncryptWithData:data key:aesKey iv:aesIv];
	} else if ([data isKindOfClass:[NSString class]]) {
		result = [CocoaSecurity aesEncrypt:data key:aesKey iv:aesIv];
	}
	[d setObject:result.base64 forKey:aKey];
	[NSKeyedArchiver archiveRootObject:d toFile:AGENT_REG_FILE];
}

@end


