//
//  UPKTwitCell.m
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 06.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "UPKTwitCell.h"
#import "UPKPreferences.h"
#import "UPKDAO.h"

const NSString *GotImageDataNotificationIdentifier  = @"GotImageDataNotificationIdentifier";

@interface UPKTwitCell ()
@property (weak, nonatomic) IBOutlet UIImageView *twitImgView;
@property (weak, nonatomic) IBOutlet UILabel *twitUserScreenName;
@property (weak, nonatomic) IBOutlet UILabel *twitText;
@property (nonatomic, strong) NSString *imgUrlString;
@end

@implementation UPKTwitCell

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gotImageData:) name:[GotImageDataNotificationIdentifier copy] object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.contentView layoutIfNeeded];
    self.twitText.preferredMaxLayoutWidth = CGRectGetWidth(self.twitText.frame);
}

- (void)prepareForReuse {
    self.imgUrlString = nil;
    [self setNeedsUpdateConstraints];
    [self.layer removeAllAnimations];
}

- (void)prepareViewWithUserScreenName:(NSString *)screenName andText:(NSString *)text andImgUrlString:(NSString *)imgUrlString {
    self.twitUserScreenName.text = screenName;
    self.twitText.text = text;
    if (imgUrlString) { //для ячейки, при помощи которой я рассчитываю высоту, imgUrlString == nil
        if ([[UPKPreferences sharedPreferences] avatarsEnabled]) {
            //загрузка данных на самом деле асинхронна - когда данные новые прийдут, прийдет оповещение и я вызову обновление нужных ячеек таблицы
            NSData *imgData = [[UPKDAO sharedDAO] dataForUrlString:imgUrlString andNotification:[GotImageDataNotificationIdentifier copy]];
            //если же данные есть в кеше - то разу их помещу на экран
            if (imgData) {
                self.twitImgView.image = [[UIImage alloc] initWithData:imgData];
            } else {
                self.twitImgView.image = [self.class placeholderImage];
                self.imgUrlString = imgUrlString;
            }
        }
    } else {
        self.twitImgView.image = [self.class placeholderImage];
    }
}

+ (UIImage *)placeholderImage {
    static UIImage *__img = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __img = [UIImage imageNamed:@"avatar_placeholder"];
    });
    return __img;
}

#pragma mark  got img data

- (void)gotImageData:(NSNotification *)note {
    //пришли данные картинки
    if (![[UPKPreferences sharedPreferences] avatarsEnabled]) {
        return;
    }
    NSString *urlString = note.object;
    if ([self.imgUrlString isEqualToString:urlString]) {
        NSData *imgData = [[UPKDAO sharedDAO] dataForUrlString:urlString andNotification:[GotImageDataNotificationIdentifier copy]];
        //если же данные есть в кеше - то разу их помещу на экран
        if (imgData) {
            self.twitImgView.image = [[UIImage alloc] initWithData:imgData];
        } else {
            NSAssert(NO, @"Какая-то странная ситуация: данные были, да всплыли (в кеше не появились)");
        }
    }
}

@end
