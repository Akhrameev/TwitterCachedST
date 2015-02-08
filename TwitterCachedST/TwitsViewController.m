//
//  FirstViewController.m
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 02.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "TwitsViewController.h"
#import "UPKDAO.h"
#import "UPKTwit.h"
#import "UPKUser.h"
#import "UPKTwitsAndUsersContainer.h"
#import "UPKTwitCell.h"
#import "UPKPreferences.h"

#define UPK_SHOW_DATE_STRING 0
#define UPK_AUTOUPDATE 1

const NSString *UpdateTwitsNotificationIdentifier   = @"UpdateTwitsNotificationIdentifier";
const NSString *GotImageDataNotificationIdentifier  = @"GotImageDataNotificationIdentifier";

@interface TwitsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic, strong) UPKTwitsAndUsersContainer *container;
@property (weak, nonatomic) IBOutlet UILabel *timerIndicator;
@property (nonatomic, strong) NSTimer *reloadTimer;
@property (nonatomic, assign) NSUInteger numberOfTicks;
@property (weak, nonatomic) IBOutlet UITextField *screenNameTextField;

//в этом словарехранятся ячейки-прототипы для динамического расчета высоты ячейки на iOS 7 и 8 (8-ка бы и сама справилась, но 7-ка-то нет)
@property (nonatomic, strong) NSMutableDictionary *prototypeCellsDic;
@end

@implementation TwitsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.prototypeCellsDic = [NSMutableDictionary dictionary];
    // Do any additional setup after loading the view, typically from a nib.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTwits:) name:[UpdateTwitsNotificationIdentifier copy] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gotImageData:) name:[GotImageDataNotificationIdentifier copy] object:nil];
    [self.tableView setTableFooterView:[UIView new]];
    //чтобы не было некрасивых линий внизу таблицы
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
    [self loadIt:nil];
}

- (void)tap:(UIGestureRecognizer *)tapGestre {
    //для того, чтобы на айфоне можно было скрыть клавиатуру
    //обычно использую TPKeyboardAvoidingView - но здесь я поместил поле ввода в верх экрана, хватит просто рекогнайзера
    [self.view endEditing:YES];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self.view setNeedsUpdateConstraints];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTimerIndicatorValue];
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - loading initiators

- (IBAction)loadIt:(id)sender {
#if (UPK_AUTOUPDATE)
    if (!self.reloadTimer) {
        self.reloadTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/[self ticksPerSecond] target:self selector:@selector(reloadTimerTick:) userInfo:nil repeats:YES];
    }
#endif
    NSString *screenName = [self screenNameForGatheringMoreData:NO];
    [[UPKDAO sharedDAO] twitListForUserScreenName:screenName withMaxId:nil orSinceId:nil andCount:20 andNotification:[UpdateTwitsNotificationIdentifier copy]];
}

- (void)loadFreshTwits:(id)sender {
    NSString *screenName = [self screenNameForGatheringMoreData:YES];
    //узнаю, какой твит сейчас верхний (мне нужен его idString)
    UPKTwit *firstTwit = [self.container.twits firstObject];
    NSString *firstTwitIdString = firstTwit.idString;
    [[UPKDAO sharedDAO] twitListForUserScreenName:screenName withMaxId:nil orSinceId:firstTwitIdString andCount:20 andNotification:[UpdateTwitsNotificationIdentifier copy]];
}

- (void)loadOldTwits:(id)sender {
    NSString *screenName = [self screenNameForGatheringMoreData:YES];
    //узнаю, какой твит сейчас верхний (мне нужен его idString)
    UPKTwit *lastTwit = [self.container.twits lastObject];
    NSString *lastTwitIdString = lastTwit.idString;
    [[UPKDAO sharedDAO] twitListForUserScreenName:screenName withMaxId:lastTwitIdString orSinceId:nil andCount:20 andNotification:[UpdateTwitsNotificationIdentifier copy]];
}

- (NSString *)screenNameForGatheringMoreData:(BOOL)gatherMoreData {
    NSString *screenNameToReturn = nil;
    if (!gatherMoreData) {
        //если мы хотим грузить кого-то нового, то мы можем начать грузить того, чей ник введен
        NSString *screenNameTextFieldText = [self.screenNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        screenNameToReturn = screenNameTextFieldText;
    }
    if (!screenNameToReturn.length) {
        //если мы хотим еще данных по этому пользователю - то стоит искать имя пользователя в текущем словаре пользователей
        UPKUser *user = [self.container.users.allValues firstObject];
        screenNameToReturn = user.screenName;
    }
    if (!screenNameToReturn.length) {
        screenNameToReturn = @"ksenks";     //значение по умолчанию для загрузки хоть кого-нибудь
    }
    return screenNameToReturn;
}

#pragma mark - loading twits finished method

- (void)updateTwits:(NSNotification *)note {
    //пришли данные - пора их локально сохранить и обновить табличку
    UPKTwitsAndUsersContainer *container = note.object;
    self.container = self.container ? [self.container containerMergedWithContainer:container] : container;
    [self.tableView reloadData];
}

#pragma mark - timing methods

- (NSUInteger)maxNumberOfTicks {
    //костанта перед умножением на ticksPerSecond - количество секунд
#if (DEBUG)
    return 20 * [self ticksPerSecond];
#endif
    return 60 * [self ticksPerSecond];
}

- (NSUInteger)ticksPerSecond {
    //сколько раз в секунду стоит срабатывать таймеру, чтобы мы наиболее точно отсчитывали время
    return 2;
}

- (void)updateTimerIndicatorValue {
    self.timerIndicator.text = self.numberOfTicks ? [@(self.numberOfTicks/[self ticksPerSecond]) stringValue] : @"";
}

- (void)reloadTimerTick:(NSTimer *)timer {
    //такая реализация та   мера мне больше всего нравится. Из-за скролла таблицы может отложить немного обновление данных - но мне кажется, что это не большая проблема.
    //зато такой подход устойчив к смене времени на девайсе
    //правда, твиттер и сам проследит, чтобы timestamp не сильно отставал от текущего времени
    if (!self.numberOfTicks) {
        self.numberOfTicks = [self maxNumberOfTicks];
    } else {
        --self.numberOfTicks;
    }
    if (!self.numberOfTicks) {
        [self loadIt:nil];
        self.numberOfTicks = [self maxNumberOfTicks];
    }
    [self updateTimerIndicatorValue];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.container.twits.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView cellForRowAtIndexPath:indexPath requestImg:YES];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath requestImg:(BOOL)requestImg {
    NSString *userScreenName = nil;
    NSString *twitText = nil;
    NSData *imgData = nil;
    [self tableView:tableView dataForRowAtIndexPath:indexPath placeHereImgData:&imgData placeHereUserScreenName:&userScreenName placeHereTwitText:&twitText];
    NSString *cellIdentifier = [self cellIdentifierForCellWithImgData:(imgData != nil)];
    UPKTwitCell *cell = (UPKTwitCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    [cell prepareViewWithUserScreenName:userScreenName andText:twitText andImgData:imgData];
    return cell;
}

#pragma mark - UITableViewCell data helper

- (NSString *)cellIdentifierForCellWithImgData:(BOOL)hasImgData {
    static NSString *cellIdentifier = @"twitCell";
    static NSString *cellImageIdentifier = @"twitImgCell";
    return hasImgData ? cellImageIdentifier : cellIdentifier;
}

- (void)tableView:(UITableView *)tableView dataForRowAtIndexPath:(NSIndexPath *)indexPath placeHereImgData:(NSData **)imgData placeHereUserScreenName:(NSString **)userScreenName placeHereTwitText:(NSString **)twitText {
    UPKTwit *twit = [self.container.twits objectAtIndex:indexPath.row];
    UPKUser *user = [self.container.users objectForKey:twit.userIdString];
    NSString * userScreenNameLocal = user.screenName;
    NSData *imgDataLocal = nil;
    if ([[UPKPreferences sharedPreferences] avatarsEnabled]) {
        //загрузка данных на самом деле асинхронна - когда данные новые прийдут, прийдет оповещение и я вызову обновление нужных ячеек таблицы
        imgDataLocal = [[UPKDAO sharedDAO] dataForUrlString:user.profileImgUrl andNotification:[GotImageDataNotificationIdentifier copy]];
        //если же данные есть в кеше - то разу их помещу на экран
    }
#if (UPK_SHOW_DATE_STRING)
    NSString *dateString = twit.dateString;
    if (dateString) {
        userScreenNameLocal = [NSString stringWithFormat:@"%@ %@", userScreenName, dateString];
    }
#endif
    if (twitText) {
        *twitText = twit.text;
    }
    if (userScreenName) {
        *userScreenName = userScreenNameLocal;
    }
    if (imgData && imgDataLocal) {
        *imgData = imgDataLocal;
    }
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *userScreenName = nil;
    NSString *twitText = nil;
    [self tableView:tableView dataForRowAtIndexPath:indexPath placeHereImgData:nil placeHereUserScreenName:&userScreenName placeHereTwitText:&twitText];
    NSString *cellIdentifier = [self cellIdentifierForCellWithImgData:[[UPKPreferences sharedPreferences] avatarsEnabled]]; //высота при включенных картинках будет "с запасом"((
    UPKTwitCell *cell = [self.prototypeCellsDic objectForKey:cellIdentifier];
    if (!cell) {
        cell = (UPKTwitCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        [self.prototypeCellsDic setObject:cell forKey:cellIdentifier];
    }
    
    // The cell's width must be set to the same size it will end up at once it is in the table view.
    // This is important so that we'll get the correct height for different table view widths, since our cell's
    // height depends on its width due to the multi-line UILabel word wrapping. Don't need to do this above in
    // -[tableView:cellForRowAtIndexPath:] because it happens automatically when the cell is used in the table view.
    cell.bounds = CGRectMake(0.0f, 0.0f, CGRectGetWidth(tableView.bounds), CGRectGetHeight(cell.bounds));
    // NOTE: if you are displaying a section index (e.g. alphabet along the right side of the table view), or
    // if you are using a grouped table view style where cells have insets to the edges of the table view,
    // you'll need to adjust the cell.bounds.size.width to be smaller than the full width of the table view we just
    // set it to above. See http://stackoverflow.com/questions/3647242 for discussion on the section index width.
    
    [cell prepareViewWithUserScreenName:userScreenName andText:twitText andImgData:nil];
    
    // Do the layout pass on the cell, which will calculate the frames for all the views based on the constraints
    // (Note that the preferredMaxLayoutWidth is set on multi-line UILabels inside the -[layoutSubviews] method
    // in the UITableViewCell subclass
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    
    // Get the actual height required for the cell
    CGFloat height = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    
    // Add an extra point to the height to account for the cell separator, which is added between the bottom
    // of the cell's contentView and the bottom of the table view cell.
    height += 1;
    
    return height;
}

#pragma mark - gotImageData notification

- (void)gotImageData:(NSNotification *)note {
    //пришли данные картинки
    if (![[UPKPreferences sharedPreferences] avatarsEnabled]) {
        return;
    }
    NSString *urlString = note.object;
    UPKTwitsAndUsersContainer *currentContainer = [self.container copy];
    NSMutableSet *userIds = [NSMutableSet set];
    for (NSString *idString in currentContainer.users) {
        UPKUser *user = [currentContainer.users objectForKey:idString];
        if ([user.profileImgUrl isEqualToString:urlString]) {
            [userIds addObject:idString];
        }
    }
    NSArray *twitsTouchedByThisImg = [currentContainer.twits filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"userIdString in %@", userIds]];
    NSMutableArray *rowsToReload = [NSMutableArray array];
    for (UPKTwit *twit in twitsTouchedByThisImg) {
        NSUInteger index = [currentContainer.twits indexOfObject:twit];
        if (index != NSNotFound) {
            [rowsToReload addObject:[NSIndexPath indexPathForRow:index inSection:0]];
        }
    }
    if (rowsToReload.count) {
        //эти ячейки связаны с этой картинкой - их пора обновить
        [self.tableView reloadRowsAtIndexPaths:rowsToReload withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end
