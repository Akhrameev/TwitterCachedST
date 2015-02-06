//
//  UPKSingleTwitRequestCapsule.m
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 05.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "UPKSingleTwitRequestCapsule.h"

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

#define UPK_HMAC_SECRET @"H513sLaD52ck9cfylUq3Puw1VjoRgz25EcYg8CaUChhNxnqfvi&7rTc5J9BSCoYbEdjEfba1o260inXLa3yJBL2oVbMN4hbR"

@implementation UPKSingleTwitRequestCapsule

- (instancetype) initWithUrlString:(NSString *)urlString timeoutInterval:(NSTimeInterval)timeoutInterval requestParams:(NSDictionary *)requestParams notifyOnResponse:(NSString *)notification {
    NSAssert(urlString.length && notification && timeoutInterval, @"параметры должны быть ненулевыми!");
    self = [super init];
    if (self) {
        _notification = notification;
        
        NSString *oauth_nonce = [self oauth_nonce];
        NSString *oauth_timestamp = [@([@([[NSDate date] timeIntervalSince1970]) integerValue]) stringValue];
        NSString *oauth_consumer_key = UPK_TWITTER_OAUTH_CONSUMER_KEY;
        
        NSMutableDictionary *oauthDictionary = [NSMutableDictionary dictionary];
        [oauthDictionary setObject:oauth_consumer_key forKey:@"oauth_consumer_key"];
        [oauthDictionary setObject:oauth_timestamp forKey:@"oauth_timestamp"];
        [oauthDictionary setObject:@"HMAC-SHA1" forKey:@"oauth_signature_method"];
        [oauthDictionary setObject:UPK_TWITTER_OAUTH_TOKEN forKey:@"oauth_token"];
        [oauthDictionary setObject:@"1.0" forKey:@"oauth_version"];
        [oauthDictionary setObject:oauth_nonce forKey:@"oauth_nonce"];
        
        NSMutableDictionary *fullDictionary = [oauthDictionary mutableCopy];
        [fullDictionary setValuesForKeysWithDictionary:requestParams];
        
        NSArray *allKeys = [[fullDictionary allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        
        NSMutableString *stringForHashing = [@"GET&" mutableCopy];
        [stringForHashing appendString:[self URLEncodedString_ch:urlString]];
        [stringForHashing appendString:@"&"];
        BOOL first = YES;
        for (NSString *key in allKeys) {
            NSString *value = [fullDictionary objectForKey:key];
            NSString *appendPart = [NSString stringWithFormat:@"%@=%@", key, value];
            if (!first) {
                appendPart = [@"&" stringByAppendingString:appendPart];
            }
            [stringForHashing appendString:[self URLEncodedString_ch:appendPart]];
            first = NO;
        }
        
        NSString *signature = [self signatureForString:stringForHashing];
        [oauthDictionary setObject:signature forKey:@"oauth_signature"];
        
        NSArray *allOauthKeys = [[oauthDictionary allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSMutableString *oauthString = [@"OAuth " mutableCopy];
        first = YES;
        for (NSString *key in allOauthKeys) {
            NSString *value = [oauthDictionary objectForKey:key];
            NSString *appendPart = [NSString stringWithFormat:@"%@=\"%@\"", key, value];
            if (!first) {
                appendPart = [@", " stringByAppendingString:appendPart];
            }
            [oauthString appendString:appendPart];
            first = NO;
        }
        
        NSString *encodedResponseParams = [self encodeResponseParams:requestParams];
        if (encodedResponseParams.length) {
            urlString = [NSString stringWithFormat:@"%@?%@", urlString, encodedResponseParams];
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:timeoutInterval];
        
        [request addValue:oauthString forHTTPHeaderField:@"Authorization"];
        [request addValue:@"application/x-www-form-urlencoded; charset=utf-8"forHTTPHeaderField:@"Content-Type"];
        [request addValue:@"0" forHTTPHeaderField:@"Content-Length"];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        [_connection scheduleInRunLoop:[NSRunLoop mainRunLoop]
                               forMode:NSDefaultRunLoopMode];
        [_connection start];
    }
    return self;
}

- (NSString *) URLEncodedString_ch:(NSString *)string {
    NSMutableString * output = [NSMutableString string];
    const unsigned char * source = (const unsigned char *)[string UTF8String];
    int sourceLen = strlen((const char *)source);
    for (int i = 0; i < sourceLen; ++i) {
        const unsigned char thisChar = source[i];
        /*if (thisChar == ' '){
            [output appendString:@"+"];
        } else */if (thisChar == '.' || thisChar == '-' || thisChar == '_' || /*thisChar == '~' ||*/
                   (thisChar >= 'a' && thisChar <= 'z') ||
                   (thisChar >= 'A' && thisChar <= 'Z') ||
                   (thisChar >= '0' && thisChar <= '9')) {
            [output appendFormat:@"%c", thisChar];
        } else {
            [output appendFormat:@"%%%02X", thisChar];
        }
    }
    return output;
}

- (NSString *)oauth_nonce {
    NSUInteger length = 32;
    static NSString *alphaNumerics = @"abcdefjhijklmnopqrstuvwABCDEFJHIJKLMNOPQRSTUVW0123456789";
    static NSUInteger anLength = 0;
    if (!anLength) {
        anLength = alphaNumerics.length;
    }
    NSMutableString *mstr = [NSMutableString string];
    for (NSUInteger i = 0; i < length; ++i) {
        u_int32_t randomBits = arc4random();
        NSUInteger index = randomBits % anLength;
        NSString *characteFromString = [alphaNumerics substringWithRange:NSMakeRange(index, 1)];
        [mstr appendString:characteFromString];
    }
    return [mstr copy];
}

-(NSData*)createRandomBytes:(NSUInteger)length {
    NSMutableData* theData = [NSMutableData dataWithCapacity:length];
    for( unsigned int i = 0 ; i < length/4 ; ++i ) {
        u_int32_t randomBits = arc4random();
        [theData appendBytes:(void*)&randomBits length:4];
    }
    return theData;
}

- (NSString *)encodeResponseParams:(NSDictionary*)dictionary {
    NSMutableArray *parts = [[NSMutableArray alloc] init];
    NSArray *allKeys = [dictionary.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in allKeys) {
        NSString *encodedValue = [self URLEncodedString_ch:[dictionary objectForKey:key]];
        NSString *encodedKey = [self URLEncodedString_ch:key];
        NSString *part = [NSString stringWithFormat: @"%@=%@", encodedKey, encodedValue];
        [parts addObject:part];
    }
    NSString *encodedResponseParams = [parts componentsJoinedByString:@"&"];
    return encodedResponseParams;
}

#pragma mark - HMAC-SHA1

- (NSString *)signatureForString:(NSString *)string {
    NSString *signature =[self hmacsha1:string secret:UPK_HMAC_SECRET];
    return [self URLEncodedString_ch:signature];
}

- (NSString *)hmacsha1:(NSString *)data secret:(NSString *)key {
    //form http://stackoverflow.com/questions/756492/objective-c-sample-code-for-hmac-sha1
    const char *cKey  = [key cStringUsingEncoding:NSASCIIStringEncoding];
    const char *cData = [data cStringUsingEncoding:NSASCIIStringEncoding];
    unsigned char cHMAC[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
    NSData *HMAC = [[NSData alloc] initWithBytes:cHMAC length:sizeof(cHMAC)];
    NSString *hash = [HMAC base64EncodedStringWithOptions:0];
    return hash;
}

@end
