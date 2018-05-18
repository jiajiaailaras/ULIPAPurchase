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
@property (nonatomic,copy)NSString *receipt;//存储base64编码的交易凭证

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
-(void)buyProductWithProductID:(NSString *)productID payResult:(PayResult)payResult{
    
    [self removeAllUncompleteTransactionsBeforeNewPurchase];
    
    self.payResultBlock = payResult;
    
    [RRHUD showWithContainerView:RR_keyWindow status:NSLocalizedString(@"Buying...", @"")];
    
    self.profductId = productID;
    
    if (!self.profductId.length) {
        
        UIAlertView * alertView = [[UIAlertView alloc]initWithTitle:@"Warm prompt" message:@"There is no corresponding product." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        
        [alertView show];
    }
    
    if ([SKPaymentQueue canMakePayments]) {
        
        [self requestProductInfo:self.profductId];
        
    }else{
        
    UIAlertView * alertView = [[UIAlertView alloc]initWithTitle:@"Warm prompt" message:@"Please turn on the in-app paid purchase function first." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        
    [alertView show];
        
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
        
        if (self.payResultBlock) {
            self.payResultBlock(NO, nil, @"无法获取产品信息，购买失败");
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
    
    if (self.payResultBlock) {
        self.payResultBlock(NO, nil, [error localizedDescription]);
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

//完成交易
#pragma mark -- 交易完成的回调
- (void)completeTransaction:(SKPaymentTransaction *)transaction
{
    
    [self getAndSaveReceipt:transaction]; //获取交易成功后的购买凭证
    
}

#pragma mark -- 处理交易失败回调
- (void)failedTransaction:(SKPaymentTransaction *)transaction{
    
    [RRHUD hide];
    
    NSString * error = nil;

    if(transaction.error.code != SKErrorPaymentCancelled) {
        
        [RRHUD showInfoWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Buy Failed", @"")];
        error = [NSString stringWithFormat:@"%ld",transaction.error.code];
        
    } else {
        
        [RRHUD showInfoWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Buy Canceled", @"")];
        error = [NSString stringWithFormat:@"%ld",transaction.error.code];
        
    }
    
    if (self.payResultBlock) {
        self.payResultBlock(NO, nil, error);
    }
    
    [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
    
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction{
    
    [RRHUD hide];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
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
    
    //如果这个返回为nil
    
    NSLog(@"后台订单号为订单号为%@",order);
    
    [dic setValue: base64String forKey:receiptKey];
    [dic setValue: order forKey:@"order"];
    [dic setValue:[self getCurrentZoneTime] forKey:@"time"];
    NSString * userId;
    
    if (self.userid) {
        
        userId = self.userid;
        [[NSUserDefaults standardUserDefaults]setObject:userId forKey:@"unlock_iap_userId"];
        
    }else{
        
        userId = [[NSUserDefaults standardUserDefaults]
                  objectForKey:@"unlock_iap_userId"];
    }
    
    if (userId == nil||[userId length] == 0) {
        
        userId = @"走漏单流程未传入userId";
    }
    
    if (order == nil||[order length] == 0) {
        
        order = @"苹果返回透传参数为nil";
    }
    
    [[ULSDKAPI shareAPI]sendLineWithPayOrder:order UserId:userId Receipt:base64String LineNumber:@"IPAPurchase.m 337"];

    NSString *fileName = [NSString UUID];
    
    NSString *savedPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper iapReceiptPath], fileName];
    [dic setValue: userId forKey:@"user_id"];

    //这个存储成功与否其实无关紧要
    BOOL ifWriteSuccess = [dic writeToFile:savedPath atomically:YES];

    if (ifWriteSuccess){

        NSLog(@"购买凭据存储成功!");

    }else{
        
        NSLog(@"购买凭据存储失败");
    }
    
    [self sendAppStoreRequestBuyWithReceipt:base64String userId:userId paltFormOrder:order trans:transaction];

}

-(void)getPlatformAmountInfoWithOrder:(NSString *)transOrcer{
    
    [[ULSDKAPI shareAPI]getPlatformAmountWithOrder:transOrcer success:^(id responseObject) {
        
        if (RequestSuccess) {
            
        _platformAmount = [[responseObject objectForKey:@"data"]objectForKey:@"amount"];
        _amount_type = [[responseObject objectForKey:@"data"]objectForKey:@"amount_type"];
        _third_goods_id = [[responseObject objectForKey:@"data"]objectForKey:@"third_goods_id"];
        
        [FBSDKAppEvents logEvent:@"pay_in_sdk" valueToSum:[_platformAmount doubleValue] parameters:@{@"fb_currency":@"USD",@"amount":_platformAmount,@"amount_type":_amount_type,@"third_goods_id":_third_goods_id}];
        
        }else{
            
            NSLog(@"%@",[responseObject objectForKey:@"message"]);
        }
        
    } failure:^(NSString *failure) {

    }];
    
}

#pragma mark -- 存储成功订单
-(void)SaveIapSuccessReceiptDataWithReceipt:(NSString *)receipt Order:(NSString *)order UserId:(NSString *)userId{
    
    NSMutableDictionary * mdic = [[NSMutableDictionary alloc]init];
    [mdic setValue:[self getCurrentZoneTime] forKey:@"time"];
    [mdic setValue: order forKey:@"order"];
    [mdic setValue: userId forKey:@"userid"];
    [mdic setValue: receipt forKey:receiptKey];
    NSString *fileName = [NSString UUID];
    NSString * successReceiptPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper SuccessIapPath], fileName];
    //存储购买成功的凭证
    [self insertReceiptWithReceiptByReceipt:receipt withDic:mdic  inReceiptPath:successReceiptPath];
}



-(void)insertReceiptWithReceiptByReceipt:(NSString *)receipt withDic:(NSDictionary *)dic inReceiptPath:(NSString *)receiptfilePath{
    
    BOOL isContain = NO;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    NSArray * cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper SuccessIapPath] error:&error];
    
    if (cacheFileNameArray.count == 0) {
        
        [dic writeToFile:receiptfilePath atomically:YES];
        
        if ([dic writeToFile:receiptfilePath atomically:YES]) {
            
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
        
    BOOL  results = [dic writeToFile:receiptfilePath atomically:YES];
        
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
-(void)sendAppStoreRequestBuyWithReceipt:(NSString *)receipt userId:(NSString *)userId paltFormOrder:(NSString * )order trans:(SKPaymentTransaction *)transaction{
    
    [[ULSDKAPI shareAPI]sendLineWithPayOrder:order UserId:userId Receipt:receipt LineNumber:@"IPAPurchase.m 474"];
    #pragma mark -- 发送信息去验证是否成功
    [[ULSDKAPI shareAPI] sendVertifyWithReceipt:receipt order:order userId:userId success:^(ULSDKAPI *api, id responseObject) {
        
        if (RequestSuccess) {
            
            [RRHUD hide];
            [RRHUD showSuccessWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Buy Success", @"")];
            //结束交易方法
            [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
            
            [self getPlatformAmountInfoWithOrder:order];
            
            NSData * data = [NSData dataWithContentsOfFile:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
            NSString *result = [data base64EncodedStringWithOptions:0];
            
            if (self.payResultBlock) {
                self.payResultBlock(YES, result, nil);
            }
            
            //这里将成功但存储起来
            [self SaveIapSuccessReceiptDataWithReceipt:receipt Order:order UserId:userId];
            [self successConsumptionOfGoodsWithReceipt:receipt];
            
            //检查是否发货成功
            [api checkBuyIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                
                if (RequestSuccess) {
                    
                }else{
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        //验证是否发货通过
                        [api checkBuyIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
#pragma 校验发货失败 2
                            if (RequestSuccess) {
                                
                            }else{
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    
                                    [api checkBuyIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                                        
                                        if (RequestSuccess) {
                                            
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
                
                if (RequestSuccess) {
                    
                    [RRHUD hide];
                    
                    [RRHUD showSuccessWithContainerView:UL_rootVC.view status:NSLocalizedString(@"Buy Success", @"")];
                    
                    [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                    
                    [self getPlatformAmountInfoWithOrder:order];
                    
                    NSData *data = [NSData dataWithContentsOfFile:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
                    
                    NSString *result = [data base64EncodedStringWithOptions:0];
                    
                    if (self.payResultBlock) {
                        self.payResultBlock(YES, result, nil);
                    }
                    
                    //存储成功订单
                    [self SaveIapSuccessReceiptDataWithReceipt:receipt Order:order UserId:userId];
                    //删除已成功订单
                    [self successConsumptionOfGoodsWithReceipt:receipt];
                    
                    
                    [api checkBuyIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                        
                        if (RequestSuccess) {
                            
                        }else{
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                
                                [api checkBuyIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
#pragma 校验发货失败 2
                                    if (RequestSuccess) {
                                        
                                    }else{
                                        
                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                            
                                            [api checkBuyIfSuccessWithUserid:userId Order:order success:^(ULSDKAPI *api, id responseObject) {
                                                
                                                if (RequestSuccess) {
                                                    
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
        
        [api VertfyFailedRePostWithUserId:userId Order:order jsonStr:failure];
        
    }];
}

#pragma mark -- 根据订单号来移除本地凭证的方法
-(void)successConsumptionOfGoodsWithReceipt:(NSString * )receipt{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    if ([fileManager fileExistsAtPath:[SandBoxHelper iapReceiptPath]]) {
        
        NSArray * cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper iapReceiptPath] error:&error];
        
        if (error == nil) {
            
            for (NSString * name in cacheFileNameArray) {
                
                NSString * filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper iapReceiptPath], name];
                
                [self removeReceiptWithPlistPath:filePath ByReceipt:receipt];
                
            }
        }
    }
}

#pragma mark -- 根据订单号来删除 存储的凭证
-(void)removeReceiptWithPlistPath:(NSString *)plistPath ByReceipt:(NSString *)receipt{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    NSString * localReceipt = [dic objectForKey:@"receipt_key"];
    //通过凭证进行对比
    if ([receipt isEqualToString:localReceipt]) {
      
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
