//
//  MPCrypto.h
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

#import <Cocoa/Cocoa.h>

@interface MPCrypto : NSObject

/*! Get the Hash of a file
 * \param file The file to hash
 * \param type The hash type (MD5 or SHA1)
 * \returns Digest hash
 */
- (NSString *)getHashForFileForType:(NSString *)aFile type:(NSString *)aType;

/*! Get the Hash of a string
 * \param string The string to hash
 * \param type The hash type (MD5 or SHA1)
 * \returns Digest hash
 */
- (NSString *)getHashFromStringForType:(NSString *)inputStr type:(NSString *)aType;

/*! Get MD5 Hash of a file (Convienience Method)
 * \param file The file to hash
 * \returns Digest hash
 */
- (NSString *)md5HashForFile:(NSString *)aFilePath;

/*! Get SHA1 Hash of a file (Convienience Method)
 * \param file The file to hash
 * \returns Digest hash
 */
- (NSString *)sha1HashForFile:(NSString *)aFilePath;

- (int)generateRSAKeyPairOfSize:(unsigned)keySize error:(NSError **)error;
- (NSData *)exportPrivateKeyInFormat:(SecExternalFormat)format withPEM:(BOOL)withPEM error:(NSError **)error;
- (NSData *)exportPublicKeyInFormat:(SecExternalFormat)format withPEM:(BOOL)withPEM error:(NSError **)error;

- (SecKeyRef)getKeyRef:(NSData *)aKeyData;
- (SecKeyRef)getKeyRef:(NSData *)aKeyData format:(SecExternalFormat)aFormat;

/*! Strips the RSA Encoded Lines to return DER format key
 * \param key The key to strip the encoding from
 * \param isPublic Is a public key, default is private key
 * \returns A DER encoded key as NSString
 */
- (NSString *)stripAndEncodePEMKey:(NSString *)aKey isPublic:(BOOL)aPublic;

/*! Encrypt a string using a RSA key (Convienience Method)
 * \param stringToEncrypt The string to encrypt
 * \param key The RSA key to use to encrypt the string
 * \returns Encrypted string, Base64 encoded
 */
- (NSString *)encryptStringUsingKey:(NSString *)stringToEncrypt key:(SecKeyRef)aKey error:(NSError **)err;
/*! Encrypt a string using a RSA key
 * \param stringToEncrypt The string to encrypt
 * \param padding Choose SecPadding type
 * \param key The RSA key to use to encrypt the string
 * \returns Encrypted string, Base64 encoded
 */
- (NSString *)secKeyEncrypt:(SecKeyRef)aKey padding:(SecPadding)aSecPadding stringToEncrypt:(NSString *)AstringToEncrypt error:(NSError **)err;

/*! Decrypt a string using a RSA key (Convienience Method)
 * \param stringToDecrypt Base64 Encoded and encrypted string
 * \param key The RSA key to use to decrypt the string
 * \returns Decrypted string
 */
- (NSString *)decryptStringUsingKey:(NSString *)stringToDecrypt key:(SecKeyRef)aKey error:(NSError **)err;
/*! Decrypt a string using a RSA key
 * \param key The RSA key to use to decrypt the string
 * \param padding Choose SecPadding type
 * \param stringToDecrypt Base64 Encoded and encrypted string
 * \returns Decrypted string
 */
- (NSString *)secKeyDecrypt:(SecKeyRef)aKey padding:(SecPadding)aSecPadding stringToDecrypt:(NSString *)AstringToDecrypt error:(NSError **)err;

/*! Creates RSA/PEM Key Pair for client registration
 * \returns NSDictionary with keys
 */
- (NSDictionary *)rsaKeysForRegistration:(NSError **)error;

@end
