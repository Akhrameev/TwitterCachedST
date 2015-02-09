//
//  UPKClient.h
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 03.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "UPKTwitAsyncProvider.h"

extern NSString* const UPKRequestUrlString;

@interface UPKClient : NSObject <UPKTwitAsyncProvider>

+(instancetype)sharedClient;

@end
