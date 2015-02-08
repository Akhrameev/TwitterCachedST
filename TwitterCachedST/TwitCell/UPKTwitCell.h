//
//  UPKTwitCell.h
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 06.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import <UIKit/UIKit.h>

extern const NSString *GotImageDataNotificationIdentifier;

@interface UPKTwitCell : UITableViewCell

- (void)prepareViewWithUserScreenName:(NSString *)screenName andText:(NSString *)text andImgUrlString:(NSString *)imgUrlString;

@end
