//
//  UPKDAO.m
//  TwitterCachedST
//
//  Created by Pavel Akhrameev on 02.02.15.
//  Copyright (c) 2015 Pavel Akhrameev. All rights reserved.
//

#import "UPKDAO.h"
#import "UPKClient.h"
#import "FMDB.h"
#import "UPKTwit.h"
#import "UPKUser.h"

NSString* const UPKDataFromDB = @"UPKDataFromDB";

@interface UPKDAO ()
@property (nonatomic, strong) FMDatabaseQueue *fmdbQueue;
@property (nonatomic, strong) NSMutableDictionary *dataDictionary;
@end

@implementation UPKDAO
+ (instancetype)sharedDAO {
    static UPKDAO *__dao = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __dao = [[self alloc] init];
        __dao->_dataDictionary = [NSMutableDictionary dictionary];
    });
    return __dao;
}

#pragma mark - DataForUrlStirng

- (NSData *)dataForUrlString:(NSString *)urlString andNotification:(NSString *)notification {
    NSData *data = [self.dataDictionary objectForKey:urlString];
    if (!data.length) {
        if (data) {
            //запрос в процессе - ничего не делаем
        } else {
            //сделаю запрос к серверу
            UPKClient *client = [UPKClient sharedClient];
            [client dataForUrlString:urlString andNotification:notification];
            //поищу данные в БД
            FMDatabaseQueue *queue = self.fmdbQueue;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [queue inDatabase:^(FMDatabase *db) {
                    //пока простейшая реализация - вернуть все, что было в БД
                    FMResultSet *rs =[db executeQuery:@"select * from data where urlString in (?)", urlString];
                    while ([rs next]) {
                        NSData *data = [rs dataForColumn:@"data"];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self setData:data forUrlString:urlString];
                            [[NSNotificationCenter defaultCenter] postNotificationName:notification object:urlString userInfo:@{UPKDataFromDB:@(YES)}];
                        });
                        break;
                    }
                }];
            });
        }
    } else {
        return data;
    }
    return nil;
}

- (void)setData:(NSData *)data forUrlString:(NSString *)urlString {
    [self.dataDictionary setObject:data forKey:urlString];
    //чтобы не было повторных запросов
}

- (void)finishedLoadingUrlString:(NSString *)urlString withData:(NSData *)data andNotification:(NSString *)notification {
    if (data && urlString) {
        [self.dataDictionary setObject:data forKey:urlString];
        FMDatabaseQueue *queue = self.fmdbQueue;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
                BOOL success = [db executeQuery:@"delete from 'data' where urlString=(?)", urlString];
                if (success) {
                    success = [db executeUpdate:@"insert into 'data' (urlString,data) values (?,?)", urlString, data];
                }
                if (!success) {
                    *rollback = YES;
                    return;
                }
            }];
        });
        [[NSNotificationCenter defaultCenter] postNotificationName:notification object:urlString];
    }
}

#pragma mark - Twits

- (void)twitListForUserScreenName:(NSString *)screenName withMaxId:(NSString *)maxTwitId andCount:(NSUInteger)count andNotification:(NSString *)notification {
    UPKClient *client = [UPKClient sharedClient];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:notification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processTwits:) name:notification object:nil];
    [client twitListForUserScreenName:screenName withMaxId:maxTwitId andCount:count andNotification:notification];
    
    //теперь пока данные грузятся получу локальные данные, удовлетворяющие этому же запросу
    __block NSMutableArray *twitsAndUsers = [NSMutableArray arrayWithCapacity:count];
    FMDatabaseQueue *queue = self.fmdbQueue;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [queue inDatabase:^(FMDatabase *db) {
            //пока простейшая реализация - вернуть все, что было в БД
            FMResultSet *rs =[db executeQuery:@"select * from twits"];
            NSMutableSet *userIdsInUse = [NSMutableSet set];
            while ([rs next]) {
                UPKTwit *twit = [UPKTwit new];
                twit.idString = [rs stringForColumn:@"idString"];
                twit.userIdString = [rs stringForColumn:@"userIdString"];
                twit.text = [rs stringForColumn:@"text"];
                [twitsAndUsers addObject:twit];
                [userIdsInUse addObject:twit.userIdString];
            }
            if (userIdsInUse.count) {
                rs = [db executeQuery:@"select * from users where idString in (?)", [userIdsInUse.allObjects componentsJoinedByString:@","]];
                while ([rs next]) {
                    UPKUser *user = [UPKUser new];
                    user.idString = [rs stringForColumn:@"idString"];
                    user.screenName = [rs stringForColumn:@"screenName"];
                    user.profileImgUrl = [rs stringForColumn:@"profileImgUrl"];
                    [twitsAndUsers addObject:user];
                }
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:notification object:twitsAndUsers userInfo:@{UPKDataFromDB:@(YES)}];
        });
    });
}

- (void)processTwits:(NSNotification *)note {
    if ([[note.userInfo objectForKey:UPKDataFromDB] boolValue]) {
        return;//это сообщение отправлял сам DAO
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:note.name object:nil];
    //полученные здесь twits нужно будет сохранить (или обновить существующие данные)
    //простейший вариант - прибить те, что были и сохранить новые
    NSArray *twitsAndUsers = note.object;
    FMDatabaseQueue *queue = self.fmdbQueue;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
            BOOL success = [db executeStatements:@"delete from 'users'; delete from 'twits'"];
            if (!success) {
                *rollback = YES;
                return;
            }
            for (id twitOrUser in twitsAndUsers) {
                if ([twitOrUser isKindOfClass:[UPKTwit class]]) {
                    UPKTwit *twit = twitOrUser;
                    success = [db executeUpdate:@"insert into 'twits' (idString, userIdString, text) values (?, ?, ?)", twit.idString, twit.userIdString, twit.text];
                } else if ([twitOrUser isKindOfClass:[UPKUser class]]) {
                    UPKUser *user = twitOrUser;
                    success = [db executeUpdate:@"insert into 'users' (idString, screenName, profileImgUrl) values (?,?,?)", user.idString, user.screenName, user.profileImgUrl];
                }
                if (!success) {
                    *rollback = YES;
                    return;
                }
            }
        }];
    });
}

#pragma mark - DB methods

- (FMDatabaseQueue *)fmdbQueue {
    if (!_fmdbQueue) {
        _fmdbQueue = [FMDatabaseQueue databaseQueueWithPath:self.dbPath];
    }
    return _fmdbQueue;
}

- (BOOL)dbCreateAndCheck {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL success = [fileManager fileExistsAtPath:self.dbPath];
    if(success) {
       return YES;
    }
    NSString *databasePathFromApp = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"UPKTwitDefault.db"];
    NSError *error = nil;
    [fileManager copyItemAtPath:databasePathFromApp toPath:self.dbPath error:&error];
    if (error) {
        NSLog(@"Не удалось скопировать заранее подготовленную базу данных %@", error);
    }
    return !error;
}

- (NSString *)dbPath {
    static NSString *__dbPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *dbName = @"UPKTwit.db";
        NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentDir = [documentPaths firstObject];
        __dbPath = [documentDir stringByAppendingPathComponent:dbName];
        [self hideFromICloud];  //нам не нужно, чтобы эта БД синхронизировалась между девайсами одного пользователя через iCloud
    });
    return __dbPath;
}

#pragma mark - Hide from iCloud

- (void)hideFromICloud {
    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *tempPath = NSTemporaryDirectory();
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:3];
    if (libraryPath) {
        [paths addObject:libraryPath];
    }
    if (documentsPath) {
        [paths addObject:documentsPath];
    }
    if (tempPath) {
        [paths addObject:tempPath];
    }
    for (NSString *dir in paths) {
        NSURL *fileURL = [NSURL fileURLWithPath:dir];
        [self addSkipBackupAttributeToItemAtURL:fileURL];
    }
}

- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL {
    if (![[NSFileManager defaultManager] fileExistsAtPath: [URL path]]) {
        static BOOL repeatIt = YES;
        if (repeatIt) {
            [self performSelector:@selector(hideFromICloud) withObject:nil afterDelay:1];
            //пробуем снова через секунду
            repeatIt = NO;
        }
        return NO;
    }
    NSError *error = nil;
    BOOL success = [URL setResourceValue: [NSNumber numberWithBool: YES]
                                  forKey: NSURLIsExcludedFromBackupKey error: &error];
    if(!success){
        NSLog(@"Error excluding %@ from backup %@", [URL lastPathComponent], error);
    }
    return success;
}


@end
