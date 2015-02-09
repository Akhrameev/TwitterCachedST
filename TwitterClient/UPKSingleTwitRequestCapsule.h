//
//  UPKSingleTwitRequestCapsule.h
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 05.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "UPKSingleRequestCapsule.h"

#ifndef UPK_TWITTER_OAUTH_PARAMS
    #define UPK_TWITTER_OAUTH_PARAMS
    #define UPK_TWITTER_OAUTH_CONSUMER_KEY  @""
    #define UPK_TWITTER_OAUTH_TOKEN         @""
    #define UPK_HMAC_SECRET @""     //[Consumer Secret (API Secret)] & [Access Token Secret]
#endif

@interface UPKSingleTwitRequestCapsule : UPKSingleRequestCapsule

@end
