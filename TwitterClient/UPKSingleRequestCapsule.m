//
//  UPKSingleRequestCapsule.m
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 04.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "UPKSingleRequestCapsule.h"

NSString* const UPKSingleRequestCapsuleFinishedWorking  = @"UPKSingleRequestCapsuleFinishedWorking";
NSString* const UPKSingleRequestCapsule_ResponseData    = @"UPKSingleRequestCapsule_ResponseData";
NSString* const UPKSingleRequestCapsule_Error           = @"UPKSingleRequestCapsule_Error";
NSString* const UPKSingleRequestCapsule_Entity          = @"UPKSingleRequestCapsule_Entity";

@implementation UPKSingleRequestCapsule

- (instancetype) initWithUrlString:(NSString *)urlString timeoutInterval:(NSTimeInterval)timeoutInterval requestParams:(NSDictionary *)requestParams notifyOnResponse:(NSString *)notification {
    NSAssert(urlString.length && notification && timeoutInterval, @"параметры должны быть ненулевыми!");
    self = [super init];
    if (self) {
        _notification = notification;
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:timeoutInterval];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        [_connection scheduleInRunLoop:[NSRunLoop mainRunLoop]
                               forMode:NSDefaultRunLoopMode];
        [_connection start];
    }
    return self;
}

- (NSData *)responseData {
    if (!_finished) {
        return nil;
    }
    return [_responseData copy];
}

- (NSString *)urlString {
    return [_connection.originalRequest.URL absoluteString];
}

- (NSError *)error {
    if (!_finished) {
        return nil;
    }
    return [_error copy];
}

- (void)cancel {
    [_connection cancel];
    _responseData = nil;
    _error = nil;
    _notification = nil;
}

#pragma mark NSURLConnection Delegate Methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // A response has been received, this is where we initialize the instance var you created
    // so that we can append data to it in the didReceiveData method
    // Furthermore, this method is called each time there is a redirect so reinitializing it
    // also serves to clear it
    _responseData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // Append the new data to the instance variable you declared
    [_responseData appendData:data];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse*)cachedResponse {
    // Return nil to indicate not necessary to store a cached response for this connection
    return nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // The request is complete and data has been received
    // You can parse the stuff in your instance variable now
    _finished = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:UPKSingleRequestCapsuleFinishedWorking object:self];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // The request has failed for some reason!
    // Check the error var
    _finished = YES;
    _error = error;
    [[NSNotificationCenter defaultCenter] postNotificationName:UPKSingleRequestCapsuleFinishedWorking object:self];
}

@end
