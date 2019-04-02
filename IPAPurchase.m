//
//  IPAPurchase.m
//  iOS_Purchase
//  Created by zhanfeng on 2017/6/6.
//  Copyright © 2017年 zhanfeng. All rights reserved.

#import "IPAPurchase.h"
#import "ULSDKConfig.h"
#import <StoreKit/StoreKit.h>
#import <StoreKit/SKPaymentTransaction.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>

static NSString * const receiptKey = @"receipt_key";

dispatch_queue_t iap_queue(){
    static dispatch_queue_t as_iap_queue;
    static dispatch_once_t onceToken_iap_queue;
    dispatch_once(&onceToken_iap_queue, ^{
        as_iap_queue = dispatch_queue_create("com.iap.queue", DISPATCH_QUEUE_CONCURRENT);
    });
    
    return as_iap_queue;
    
}

@interface IPAPurchase()<SKPaymentTransactionObserver,
SKProductsRequestDelegate>
{
    SKProductsRequest *request;
}
//购买凭证
//@property (nonatomic,copy)NSString *receipt;
//存储base64编码的交易凭证

//产品ID
@property (nonnull,copy)NSString * profductId;

@end

static IPAPurchase * manager = nil;

@implementation IPAPurchase
#pragma mark -- 单例方法
+ (instancetype)manager{
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        if (!manager) {
            manager = [[IPAPurchase alloc] init];
        }
        
    });
    
    return manager;
}

#pragma mark -- 添加内购监听者
-(void)startManager{
    
    dispatch_sync(iap_queue(), ^{
    
    [[SKPaymentQueue defaultQueue] addTransactionObserver:manager];

    });

}

#pragma mark -- 移除内购监听者
-(void)stopManager{
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
        
    });
    
}

#pragma mark -- 发起购买的方法
-(void)inAppPurchaseWithProductID:(NSString *)productID iapResult:(InAppPurchaseResult)iapResult{
    
    [self removeAllUncompleteTransactionsBeforeNewPurchase];
    
    self.iapResultBlock = iapResult;
    
    [RRHUD showWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Purchasing...", @"")];
    
    self.profductId = productID;
    
    if (!self.profductId.length) {
    
        UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"Warm prompt" message:@"There is no corresponding product." preferredStyle:UIAlertControllerStyleAlert];
       [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            
        }]];
        
        [UL_rootVC presentViewController:alert animated:YES completion:nil];

        
    }

    
    if ([SKPaymentQueue canMakePayments]) {
        
        [self requestProductInfo:self.profductId];
        
    }else{
        
        UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"Warm prompt" message:@"Please turn on the in-app paid purchase function first." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            
        }]];
        
        [UL_rootVC presentViewController:alert animated:YES completion:nil];
        
    }
    
}

#pragma mark -- 结束上次未完成的交易
-(void)removeAllUncompleteTransactionsBeforeNewPurchase{
    
    NSArray* transactions = [SKPaymentQueue defaultQueue].transactions;
    
    if (transactions.count >= 1) {

        for (NSInteger count = transactions.count; count > 0; count--) {
            
            SKPaymentTransaction* transaction = [transactions objectAtIndex:count-1];
            
            if (transaction.transactionState == SKPaymentTransactionStatePurchased||transaction.transactionState == SKPaymentTransactionStateRestored) {
                
                [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
            }
        }
        
    }else{
        
         NSLog(@"没有历史未消耗订单");
    }

}


#pragma mark -- 发起购买请求
-(void)requestProductInfo:(NSString *)productID{
    
    NSArray * productArray = [[NSArray alloc]initWithObjects:productID,nil];
    
    NSSet * IDSet = [NSSet setWithArray:productArray];
    
    request = [[SKProductsRequest alloc]initWithProductIdentifiers:IDSet];
    
    request.delegate = self;
    
    [request start];
    
}

#pragma mark -- SKProductsRequestDelegate 查询成功后的回调
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    NSArray *myProduct = response.products;
    
    if (myProduct.count == 0) {
        
        [RRHUD hide];
        [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"No Product Info", @"")];
        
        if (self.iapResultBlock) {
            self.iapResultBlock(NO, nil, @"无法获取商品信息，购买失败");
        }
        
        return;
    }
    
    SKProduct * product = nil;
    
    for(SKProduct * pro in myProduct){
        
        NSLog(@"SKProduct 描述信息%@", [pro description]);
        NSLog(@"产品标题 %@" , pro.localizedTitle);
        NSLog(@"产品描述信息: %@" , pro.localizedDescription);
        NSLog(@"价格: %@" , pro.price);
        NSLog(@"Product id: %@" , pro.productIdentifier);
        
        if ([pro.productIdentifier isEqualToString:self.profductId]) {
            
            product = pro;
            
            break;
        }
    }
    
    if (product) {
        
        SKMutablePayment * payment = [SKMutablePayment paymentWithProduct:product];
        //使用苹果提供的属性,将平台订单号复制给这个属性作为透传参数
        payment.applicationUsername = self.order;
        
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        
    }else{
        
        NSLog(@"没有此商品信息");
    }
}

//查询失败后的回调
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    
    if (self.iapResultBlock) {
        self.iapResultBlock(NO, nil, [error localizedDescription]);
    }
}

//如果没有设置监听购买结果将直接跳至反馈结束；
-(void)requestDidFinish:(SKRequest *)request{
    
}

#pragma mark -- 监听结果
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions{
    
    //当用户购买的操作有结果时，就会触发下面的回调函数，
    for (SKPaymentTransaction * transaction in transactions) {
        
        switch (transaction.transactionState) {
                
            case SKPaymentTransactionStatePurchased:{
                
                [self completeTransaction:transaction];
                
            }break;
                
            case SKPaymentTransactionStateFailed:{
                
                [self failedTransaction:transaction];
                
            }break;
                
            case SKPaymentTransactionStateRestored:{//已经购买过该商品
                
                [self restoreTransaction:transaction];
                
            }break;
                
            case SKPaymentTransactionStatePurchasing:{
                
                NSLog(@"正在购买中...");
                
            }break;
                
            case SKPaymentTransactionStateDeferred:{
                
                NSLog(@"最终状态未确定");
                
            }break;
                
            default:
                break;
        }
    }
}


-(BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product{
    
    
    UIAlertController *  alert  = [UIAlertController alertControllerWithTitle:@"提示" message:@"你有一笔来自appStore的优惠订单未使用,请点击使用,以防失效." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"使用" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        //这里去获取游戏的一些参数
        
    }]];
    
    return YES;
}

//完成交易
#pragma mark -- 交易完成的回调
- (void)completeTransaction:(SKPaymentTransaction *)transaction{
#pragma mark -- 根据存储凭证存储Order
    if(self.order) {
        
     [self saveOrderByInAppPurchase:transaction];
        
    }
#pragma mark -- 获取购买凭证并且发送服务器验证
    [self getAndSaveReceipt:transaction]; //获取交易成功后的购买凭证
    
}

#pragma mark -- 处理交易失败回调
- (void)failedTransaction:(SKPaymentTransaction *)transaction{
    
    [RRHUD hide];
    
    NSString * error = nil;

    if(transaction.error.code != SKErrorPaymentCancelled) {
        
        [RRHUD showInfoWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Purchase Failed", @"")];
        error = [NSString stringWithFormat:@"%ld",transaction.error.code];
        
    } else {
        
        [RRHUD showInfoWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Purchase Canceled", @"")];
        error = [NSString stringWithFormat:@"%ld",transaction.error.code];
        
    }
    
    if (self.iapResultBlock) {
        self.iapResultBlock(NO, nil, error);
    }
    
    [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
    
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction{
    
    [RRHUD hide];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

#pragma mark -- 存储订单,防止走漏单流程是获取不到Order 且苹果返回order为nil
-(void)saveOrderByInAppPurchase:(SKPaymentTransaction *)transaction{
    
    NSMutableDictionary * dic = [[NSMutableDictionary alloc]init];
    NSString * order = self.order;
    NSString *savedPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper tempOrderPath], order];
    [dic setValue:order forKey:transaction.transactionIdentifier];
    BOOL ifWriteSuccess = [dic writeToFile:savedPath atomically:YES];
    
    if (ifWriteSuccess) {
        
        NSLog(@"根据事务id存储订单号成功!订单号为:%@  事务id为:%@",order,transaction.transactionIdentifier);
    }
}

#pragma mark -- 根据凭证存储的列表里获取Order
-(NSString *)getOrderWithTransactionId:(NSString *)transId{
    
    NSString * order;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    NSArray * cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper tempOrderPath] error:&error];
    
    for (NSString * name in cacheFileNameArray) {
        
       NSString * filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper tempOrderPath], name];
        NSMutableDictionary *localdic = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
        if ([localdic valueForKey:transId]) {
            order = [localdic valueForKey:transId];
            
        }else{
            continue;
        }
    }
    
    if ([order length]>0) {
        
      return order;
        
    }else{
        
      return @"";
        
    }
}
#pragma mark -- 获取购买凭证
-(void)getAndSaveReceipt:(SKPaymentTransaction *)transaction{
    
    //获取交易凭证
    NSURL * receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData * receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    NSString * base64String = [receiptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    //初始化字典
    NSMutableDictionary * dic = [[NSMutableDictionary alloc]init];
    NSString * order = transaction.payment.applicationUsername;
    NSString * userId;
    
    if (self.userid) {
        
        userId = self.userid;
        
        [[NSUserDefaults standardUserDefaults]setValue:userId forKey:@"unlock_iap_userId"];
        
    }else{
        
        userId = [[NSUserDefaults standardUserDefaults]
                  valueForKey:@"unlock_iap_userId"];
    }
    
    if (userId == nil||[userId length] == 0) {
        
        userId = @"走漏单流程未传入userId";
    }
    
    if (order == nil||[order length] == 0) {
        
        if (self.order) {
            
            order = self.order;
            
        }else{
            
            if ([[self getOrderWithTransactionId:transaction.transactionIdentifier] length] > 0) {
              
                order = [self getOrderWithTransactionId:transaction.transactionIdentifier];
                
            }else{
                
                order = @"苹果返回透传参数为nil";
            }
        }
    }

    NSLog(@"后台订单号为%@",order);
    //如果这时候
    [dic setValue: base64String forKey:receiptKey];
    [dic setValue:transaction.transactionIdentifier forKey:@"unlock_transactionId"];
    [dic setValue: order forKey:@"order"];
    [dic setValue:[self getCurrentZoneTime] forKey:@"time"];
    [dic setValue: userId forKey:@"user_id"];
    
    [[ULSDKAPI shareAPI]sendLineWithPlatformOrder:order Receipt:base64String LineNumber:@"IPAPurchase.m 405"];

    NSString *savedPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper iapReceiptPath], transaction.transactionIdentifier];
    
    //这个存储成功与否其实无关紧要
    BOOL ifWriteSuccess = [dic writeToFile:savedPath atomically:YES];

    if (ifWriteSuccess){

        NSLog(@"购买凭据存储成功!");

    }else{
        
        NSLog(@"购买凭据存储失败");
    }
    
    [self sendAppStoreRequestToPhpWithReceipt:base64String userId:userId paltFormOrder:order trans:transaction];

}

#pragma mark -- 获取平台订单号去后台获取订单先关的订单信息
-(void)getPlatformAmountInfoWithOrder:(NSString *)transOrder{
    
    [[ULSDKAPI shareAPI]getPlatformAmountWithOrder:transOrder success:^(id responseObject) {
        
        if (REQUESTSUCCESS) {
            
            self->_platformAmount = [GETRESPONSEDATA:@"amount"];
            self->_amount_type = [GETRESPONSEDATA:@"amount_type"];
            self->_third_goods_id = [GETRESPONSEDATA:@"third_goods_id"];
        
            [FBSDKAppEvents logEvent:@"pay_in_sdk" valueToSum:[self->_platformAmount doubleValue] parameters:@{@"fb_currency":@"USD",@"amount":_platformAmount,@"amount_type":_amount_type,@"third_goods_id":_third_goods_id}];
        
        }else{
            //如果获取不到qing'qi
            NSLog(@"%@",[responseObject objectForKey:@"message"]);
        }
        
    } failure:^(NSString *failure) {

    }];
    
}

#pragma mark -- 存储成功订单
-(void)SaveIapSuccessReceiptDataWithReceipt:(NSString *)receipt Order:(NSString *)order UserId:(NSString *)userId transId:(NSString *)transactionId{
    
    NSMutableDictionary * mdic = [[NSMutableDictionary alloc]init];
    [mdic setValue:[self getCurrentZoneTime] forKey:@"time"];
    [mdic setValue:order forKey:@"order"];
    [mdic setValue:userId forKey:@"userid"];
    [mdic setValue:receipt forKey:receiptKey];
    NSString * successReceiptPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper SuccessIapPath], transactionId];
    //存储购买成功的凭证
    [self insertReceiptWithReceiptByReceipt:receipt withDic:mdic  inReceiptPath:successReceiptPath];
}

#pragma mark -- 写入购买成功的凭证
-(void)insertReceiptWithReceiptByReceipt:(NSString *)receipt withDic:(NSDictionary *)dic inReceiptPath:(NSString *)receiptfilePath{
    
    BOOL isContain = NO;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error=nil;
    NSArray * cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper SuccessIapPath] error:&error];
    
    if (cacheFileNameArray.count == 0) {
        
      BOOL ifWriteSuccess = [dic writeToFile:receiptfilePath atomically:YES];
        
        if (ifWriteSuccess) {
            
            NSLog(@"写入购买凭据成功");
        }
        
    }else{
       
        if (error == nil) {
         
            for (NSString * name in cacheFileNameArray) {

                NSString * filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper SuccessIapPath], name];
                NSMutableDictionary *localdic = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
                
                if ([localdic.allValues containsObject:receipt]) {
                    
                    isContain = YES;
                    
                }else{
                    
                    continue;
                }
            }
            
        }else{
            
            NSLog(@"读取本文存储凭据失败");
        }
        
    }
    
    if (isContain == NO) {
        
    BOOL results = [dic writeToFile:receiptfilePath atomically:YES];
        
    if (results) {
        
        NSLog(@"写入凭证成功");
        
    }else{
        
        NSLog(@"写入凭证失败");
    }
        
    }else{
        
        NSLog(@"已经存在凭证请勿重复写入");
    }
    
}

#pragma mark -- 获取系统时间的方法
-(NSString *)getCurrentZoneTime{
    
    NSDate * date = [NSDate date];
    NSDateFormatter*formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString*dateTime = [formatter stringFromDate:date];
    return dateTime;
    
}

#pragma mark -- 去服务器验证购买
-(void)sendAppStoreRequestToPhpWithReceipt:(NSString *)receipt userId:(NSString *)userId paltFormOrder:(NSString * )order trans:(SKPaymentTransaction *)transaction{
    
    [[ULSDKAPI shareAPI]sendLineWithPlatformOrder:order Receipt:receipt LineNumber:@"IPAPurchase.m 542"];
    #pragma mark -- 发送信息去验证是否成功
    [[ULSDKAPI shareAPI] sendVertifyWithReceipt:receipt order:order userId:userId  success:^(ULSDKAPI *api, id responseObject) {
        
        if (REQUESTSUCCESS) {
            
            [RRHUD hide];
            [RRHUD showSuccessWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Purchase Succeed", @"")];
            //结束交易方法
            [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
            
            [self getPlatformAmountInfoWithOrder:order];
            
            NSData * data = [NSData dataWithContentsOfFile:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
            NSString *result = [data base64EncodedStringWithOptions:0];
            
            //这里将成功但存储起来
            [self SaveIapSuccessReceiptDataWithReceipt:receipt Order:order UserId:userId transId:transaction.transactionIdentifier];
            [self successConsumptionOfGoodsWithTransId:transaction.transactionIdentifier];
            
            //adjust 上报充值次数打点 
            [self userRechargeTotalEventWithUserId:userId];
            
            //检查是否发货成功
            [api checkIapIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                
                if (REQUESTSUCCESS) {
                    
                    if (self.iapResultBlock) {
                        self.iapResultBlock(YES, result, nil);
                    }
                    
                }else{
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        //验证是否发货通过
                        [api checkIapIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
#pragma 校验发货失败 2
                            if (REQUESTSUCCESS) {
                                
                                if (self.iapResultBlock) {
                                    self.iapResultBlock(YES, result, nil);
                                }
                                
                            }else{
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    
                                    [api checkIapIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                                        
                                        if (REQUESTSUCCESS) {
                                        
                                            if (self.iapResultBlock) {
                                            self.iapResultBlock(YES, result, nil);
                                            }
                                            
                                        }else{
                                            
                                        }
                                        
                                    } failure:^(ULSDKAPI *api, NSString *failure) {
                                        
                                        [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Request Error", @"")];
                                    }];
                                });
                                
                            }
#pragma 校验发货失败 3
                        } failure:^(ULSDKAPI *api, NSString *failure) {
                            
                            [RRHUD hide];
                            
                            [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Request Error", @"")];
                        }];
                        
                    });
                }
#pragma 校验发货失败 1
            } failure:^(ULSDKAPI *api, NSString *failure) {
                
                [RRHUD hide];
                [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Request Error", @"")];
                
            }];
            
        }else{
#pragma mark -- callBack 回调
            [api sendVertifyWithReceipt:receipt order:order userId:userId success:^(ULSDKAPI *api, id responseObject) {
                
                if (REQUESTSUCCESS) {
                    
                    [RRHUD hide];
                    
                    [RRHUD showSuccessWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Purchase Succeed", @"")];
                    
                    [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                    
                    [self getPlatformAmountInfoWithOrder:order];
                    
                    NSData *data = [NSData dataWithContentsOfFile:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
                    
                    NSString *result = [data base64EncodedStringWithOptions:0];
                    
                    //存储成功订单
                    
                    [self SaveIapSuccessReceiptDataWithReceipt:receipt Order:order UserId:userId transId:transaction.transactionIdentifier];
                    //删除已成功订单
                    [self successConsumptionOfGoodsWithTransId:transaction.transactionIdentifier];
                    
                    [self userRechargeTotalEventWithUserId:userId];
                    
                    [api checkIapIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                        
                        if (REQUESTSUCCESS) {
                         
                            if (self.iapResultBlock) {
                                self.iapResultBlock(YES, result, nil);
                            }
                            
                        }else{
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                
                                [api checkIapIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
#pragma 校验发货失败 2
                                    if (REQUESTSUCCESS) {
                                    
                                        if (self.iapResultBlock) {
                                            self.iapResultBlock(YES, result, nil);
                                        }
                                        
                                    }else{
                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                            
                                            [api checkIapIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                                                
                                            if (REQUESTSUCCESS) {
                                                
                                                if (self.iapResultBlock) {
                                                    self.iapResultBlock(YES, result, nil);
                                                }
                                                    
                                                }else{
                                                    
                                                    [api sendFailureReoprtWithReceipt:receipt order:order success:^(ULSDKAPI *api, id responseObject) {
                                                        
                                                    } failure:^(ULSDKAPI *api, NSString *failure) {
                                                        
                                                    }];
                                                    
                                                }
                                                
                                            } failure:^(ULSDKAPI *api, NSString *failure) {
                                                
                                            [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Request Error", @"")];
                                                
                                            }];
                                        });
                                    }
#pragma 校验发货失败 3
                                } failure:^(ULSDKAPI *api, NSString *failure) {
                                    
                                    [RRHUD hide];
                                    
                                    [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Request Error", @"")];
                                    
                                }];
                                
                            });
                        }
#pragma 校验发货失败 1
                    } failure:^(ULSDKAPI *api, NSString *failure) {
                        
                        [RRHUD hide];
                        [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Request Error", @"")];
                        
                    }];
                    
                }else{
                    
                    [RRHUD hide];
#pragma mark --发送错误报告
                    [api sendFailureReoprtWithReceipt:receipt order:order success:^(ULSDKAPI *api, id responseObject) {
                        
                    } failure:^(ULSDKAPI *api, NSString *failure) {
                        
                        [RRHUD hide];
                    }];
                    
                }
                
            } failure:^(ULSDKAPI *api, NSString *failure) {
                
                [RRHUD hide];
            }];
            
        }
        
    } failure:^(ULSDKAPI *api, NSString *failure) {
        
        [RRHUD hide];
        
        [api VertfyFailedRePostWithOrder:order jsonStr:failure];
        
    }];
}



#pragma mark  -- 玩家累计成功充值次数

-(void)userRechargeTotalEventWithUserId:(NSString *)userId{
    
    if ([userId length] == 0) {
        
        userId = UNLOCK_GAME_USERID;
    }
    
    if (![[NSUserDefaults standardUserDefaults]valueForKey:[NSString stringWithFormat:@"%@_AccumulatedThreeTimesSuccessfulPayment",userId]]) {
        
         [[NSUserDefaults standardUserDefaults]setValue:@"1" forKey:[NSString stringWithFormat:@"%@_AccumulatedThreeTimesSuccessfulPayment",userId]];
        
    }else{
        
        NSInteger successPayCount = [[[NSUserDefaults standardUserDefaults]valueForKey:[NSString stringWithFormat:@"%@_AccumulatedThreeTimesSuccessfulPayment",userId]]integerValue];
        
        successPayCount += 1 ;

        //存储充值次数
        [[NSUserDefaults standardUserDefaults]setValue:[NSString stringWithFormat:@"%ld",(long)successPayCount]forKey:[NSString stringWithFormat:@"%@_AccumulatedThreeTimesSuccessfulPayment",userId]];
        
        if (successPayCount >= 10) {
            
            [[ULSDKAPI shareAPI]adjustPayTotalCountReportSuccess:^(ULSDKAPI *api, id responseObject) {
                
                if (REQUESTSUCCESS) {
                    
                NSString * token = [GETRESPONSEDATA:@"AccumulatedTenTimesSuccessfulPayment"];

                NSLog(@"adjust注册上报事件AccumulatedTenTimesSuccessfulPayment --%@",token);
                ADJEvent * event = [[ADJEvent alloc]initWithEventToken:token];
                [Adjust trackEvent:event];
            
                }
                
            } Failure:^(ULSDKAPI *api, NSString *failure) {
                
            }];
            
        }else if (successPayCount >= 3){
            
            [[ULSDKAPI shareAPI]adjustPayTotalCountReportSuccess:^(ULSDKAPI *api, id responseObject) {
                
                if (REQUESTSUCCESS) {
                    
                    NSString * token = [GETRESPONSEDATA:@"AccumulatedThreeTimesSuccessfulPayment"];
                    
                    NSLog(@"adjust注册上报事件AccumulatedThreeTimesSuccessfulPayment --%@",token);
                    ADJEvent * event = [[ADJEvent alloc]initWithEventToken:token];
                    [Adjust trackEvent:event];
                    
                }
                
            } Failure:^(ULSDKAPI *api, NSString *failure) {
                
            }];
            
        }else{
            
            NSLog(@"Go ReCharge,GO!");
        }
    }
}

#pragma mark -- 根据购买拼争来移除本地凭证的方法
-(void)successConsumptionOfGoodsWithTransId:(NSString * )transcationId{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    if ([fileManager fileExistsAtPath:[SandBoxHelper iapReceiptPath]]) {
        
        NSArray * cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper iapReceiptPath] error:&error];
        
        if (error == nil) {
            
            for (NSString * name in cacheFileNameArray) {
                
                NSString * filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper iapReceiptPath], name];
                
                [self removeReceiptWithPlistPath:filePath BytransId:transcationId];
            }
        }
    }
}

#pragma mark -- 根据订单号来删除存储的凭证
-(void)removeReceiptWithPlistPath:(NSString *)plistPath BytransId:(NSString *)transactionId{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    NSString * localTransId = [dic objectForKey:@"unlock_transactionId"];
    //通过凭证进行对比
    if ([transactionId isEqualToString:localTransId]) {
      
        BOOL ifRemove = [fileManager removeItemAtPath:plistPath error:&error];
        
        if (ifRemove) {
            
            NSLog(@"成功订单移除成功");
            
        }else{
            
            NSLog(@"成功订单移除失败");
        }
        
    }else{
        
        NSLog(@"本地无与之匹配的订单");
    }
}

@end
