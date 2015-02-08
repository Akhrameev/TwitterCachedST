//
//  UPKTwitCell.m
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 06.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "UPKTwitCell.h"
#import "UPKPreferences.h"

@interface UPKTwitCell ()
@property (weak, nonatomic) IBOutlet UIImageView *twitImgView;
@property (weak, nonatomic) IBOutlet UILabel *twitUserScreenName;
@property (weak, nonatomic) IBOutlet UILabel *twitText;
@end

@implementation UPKTwitCell

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.contentView layoutIfNeeded];
    self.twitText.preferredMaxLayoutWidth = CGRectGetWidth(self.twitText.frame);
}

- (void)prepareForReuse {
    [self setNeedsUpdateConstraints];
    [self.layer removeAllAnimations];
}

- (void)prepareViewWithUserScreenName:(NSString *)screenName andText:(NSString *)text andImgData:(NSData *)imgData {
    if (imgData) {
        self.twitImgView.image = [UIImage imageWithData:imgData];
    }
    [self layoutIfNeeded];
    self.twitUserScreenName.text = screenName;
    self.twitText.text = text;
}

@end
