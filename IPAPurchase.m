//
//  IPAPurchase.m
//  iOS_Purchase
//  Created by zhanfeng on 2017/6/6.
//  Copyright © 2017年 zhanfeng. All rights reserved.

#import "IPAPurchase.h"
#import "ULSDKConfig.h"
#import <StoreKit/StoreKit.h>

static NSString * const receiptKey = @"receipt_key";

dispatch_queue_t iap_queue() {
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

#pragma mark -- 漏单处理
-(void)startManager{
    
    
    dispatch_sync(iap_queue(), ^{

     [[SKPaymentQueue defaultQueue] addTransactionObserver:manager];
      
     });
    
}

#pragma mark -- 移除交易事件
-(void)stopManager{
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
        
    });
    
}


#pragma mark -- 发起购买的方法
-(void)buyProductWithProductID:(NSString *)productID payResult:(PayResult)payResult{
    
    self.payResultBlock = payResult;
    //移除上次未完成的交易订单
    [self removeAllUncompleteTransactionBeforeStartNewTransaction];
    
    [RRHUD showWithContainerView:RR_keyWindow status:NSLocalizedString(@"购买中...", @"")];
    
    self.profductId = productID;
    
    if (!self.profductId.length) {
        
        UIAlertView * alertView = [[UIAlertView alloc]initWithTitle:@"温馨提示" message:@"没有对应的商品" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles: nil];
        
        [alertView show];
    }
    
    if ([SKPaymentQueue canMakePayments]) {
        
        [self requestProductInfo:self.profductId];
        
    }else{
        
        UIAlertView * alertView = [[UIAlertView alloc]initWithTitle:@"温馨提示" message:@"请先开启应用内付费购买功能。" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles: nil];
        
        [alertView show];
        
    }
}

#pragma mark -- 结束上次未完成的交易 防止串单
-(void)removeAllUncompleteTransactionBeforeStartNewTransaction{
    
    NSArray* transactions = [SKPaymentQueue defaultQueue].transactions;
    if (transactions.count > 0) {
        //检测是否有未完成的交易
        SKPaymentTransaction* transaction = [transactions firstObject];
        if (transaction.transactionState == SKPaymentTransactionStatePurchased) {
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            
            return;
        }
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
        [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"没有该商品信息", @"")];
        
        if (self.payResultBlock) {
            self.payResultBlock(NO, nil, @"无法获取产品信息,购买失败");
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
    
    //获取到商品不为空
    if (product) {
        
    SKMutablePayment * payment = [SKMutablePayment paymentWithProduct:product];
    //内购透传参数,与transaction一一对应
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
                
            [RRHUD hide];
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
- (void)completeTransaction:(SKPaymentTransaction *)transaction{
    
    NSLog(@"购买成功,准备验证发货");
    [self getReceipt]; //获取交易成功后的购买凭证
    [self saveReceipt:transaction]; //存储交易凭证
    [self checkIAPFiles:transaction];
}

#pragma mark -- 处理交易失败回调
- (void)failedTransaction:(SKPaymentTransaction *)transaction
{

    [RRHUD hide];
    NSString *error = nil;
    if(transaction.error.code != SKErrorPaymentCancelled) {
        
        [RRHUD showInfoWithContainerView:UL_rootVC.view status:NSLocalizedString(@"购买失败", @"")];
    } else {
        
        [RRHUD showInfoWithContainerView:UL_rootVC.view status:NSLocalizedString(@"取消购买", @"")];
    }
    
    if (self.payResultBlock) {
        self.payResultBlock(NO, nil, error);
    }

    [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
    
}


- (void)restoreTransaction:(SKPaymentTransaction *)transaction{
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    
}

#pragma mark -- 获取购买凭证
-(void)getReceipt{
    
    NSURL * receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData * receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    NSString * base64String = [receiptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
     self.receipt = base64String;
}

#pragma mark -- 存储购买凭证
-(void)saveReceipt:(SKPaymentTransaction *)transaction{
    
    NSString * userId;
    
    if (self.userid) {
        
        userId = self.userid;
        [[NSUserDefaults standardUserDefaults]setObject:userId forKey:@"unlock_iap_userId"];
    }else{
        
        userId = [[NSUserDefaults standardUserDefaults]objectForKey:@"unlock_iap_userId"];
    }
    
    NSString * order = transaction.payment.applicationUsername;
    
    NSString *fileName = [NSString UUID];
    NSString *savedPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper iapReceiptPath], fileName];
    NSMutableDictionary * dic = [[NSMutableDictionary alloc]init];
    [dic setValue: self.receipt forKey:receiptKey];
    [dic setValue: userId forKey:@"user_id"];
    [dic setValue: order forKey:@"order"];
    BOOL ifWriteSuccess  = [dic writeToFile:savedPath atomically:YES];
    
    if (ifWriteSuccess) {
        
        NSLog(@"购买凭据存储成功!");
    }
}

/*
#pragma mark -- 客户端验证购买凭证的方法
-(void)verifyTransactionResult{
    
    [RRHUD hide];
    
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    
    NSData *receipt = [NSData dataWithContentsOfURL:receiptURL];
    
    NSDictionary *requestContents = @{@"receipt-data": [receipt base64EncodedStringWithOptions:0]};
    
    NSError *error;
    
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents options:0 error:&error];
    
     if (!requestData) {
         
         NSLog(@"没有购买凭证信息");
     }
    
    NSString *verifyUrlString = @"https://sandbox.itunes.apple.com/verifyReceipt";

    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:[[NSURL alloc] initWithString:verifyUrlString] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10.0f];
    
    [storeRequest setHTTPMethod:@"POST"];
    
    [storeRequest setHTTPBody:requestData];
    
     NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    
    [NSURLConnection sendAsynchronousRequest:storeRequest queue:queue completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               
                               if (connectionError) {
                                   
                                   NSLog(@"链接失败");
                                   
                               } else {
                                   
                                   NSError *error;
                                   
                                   NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                                   
                                   if (!jsonResponse) {
                                       
                                       NSLog(@"验证失败");
                                   }
 
                                   [self removeReceipt];
   
                }
 
        }];
}
 
*/

#pragma mark -- 验证本地数据
-(void)checkIAPFiles:(SKPaymentTransaction *)transaction{

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper iapReceiptPath] error:&error];
    
    if (error == nil) {
        
        for (NSString *name in cacheFileNameArray) {
            
            if ([name hasSuffix:@".plist"]){ //如果有plist后缀的文件，说明就是存储的购买凭证
                
                NSString *filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper iapReceiptPath], name];
                
                [self sendAppStoreRequestBuyPlist:filePath trans:transaction];
            }
        }
        
    } else {
   
#pragma mark -- 如果获取不到相关存储的数据,
          [RRHUD hide];
    }
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
    [mdic writeToFile:successReceiptPath atomically:YES];
    
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
-(void)sendAppStoreRequestBuyPlist:(NSString *)plistPath trans:(SKPaymentTransaction *)transaction{

    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    NSString * receipt = [dic objectForKey:receiptKey];
    NSString * order = [dic objectForKey:@"order"];
    NSString * userId = [dic objectForKey:@"user_id"];

#pragma mark -- 发送信息去验证是否成功
    [[ULSDKAPI shareAPI] sendVertifyWithReceipt:receipt order:order success:^(ULSDKAPI *api, id responseObject) {
        
        if (RequestSuccess) {
            
            NSLog(@"服务器验证成功!");
            
            [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
            
            [RRHUD hide];
            
            [RRHUD showSuccessWithContainerView:UL_rootVC.view status:NSLocalizedString(@"购买成功", @"")];
    
            [[NSUserDefaults standardUserDefaults]removeObjectForKey:@"unlock_iap_userId"];
            
            NSData * data = [NSData dataWithContentsOfFile:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
            
            NSString *result = [data base64EncodedStringWithOptions:0];
            
            if (self.payResultBlock) {
                self.payResultBlock(YES, result, nil);
            }
            
            //这里将成功但存储起来
            [self SaveIapSuccessReceiptDataWithReceipt:receipt Order:order UserId:userId];
            
            [self successConsumptionOfGoodsWithOrder:order];
            
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
                                        
                                        [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"请求异常", @"")];
                                        
                                    }];
                                });
                            }
#pragma 校验发货失败 3
                        } failure:^(ULSDKAPI *api, NSString *failure) {
                            
                            [RRHUD hide];
                            
                            [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"请求异常", @"")];
                        }];
                        
                    });
                }
                
#pragma 校验发货失败 1
                
            } failure:^(ULSDKAPI *api, NSString *failure) {
                
                [RRHUD hide];
                [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"请求异常", @"")];
                
            }];
        
        }else{
            
#pragma mark -- callBack 回调
            [api sendVertifyWithReceipt:receipt order:order success:^(ULSDKAPI *api, id responseObject) {
                
                if (RequestSuccess) {
                    
                    [[SKPaymentQueue defaultQueue]finishTransaction:transaction];
                
                    NSLog(@"服务器验证成功!");
                    
                    [RRHUD hide];
                    
                    [RRHUD showSuccessWithContainerView:UL_rootVC.view status:NSLocalizedString(@"购买成功", @"")];
                    
                    [[NSUserDefaults standardUserDefaults]removeObjectForKey:@"unlock_iap_userId"];
                    
                    NSData *data = [NSData dataWithContentsOfFile:[[[NSBundle mainBundle] appStoreReceiptURL] path]];
                    
                    NSString *result = [data base64EncodedStringWithOptions:0];
                    
                    if (self.payResultBlock) {
                        self.payResultBlock(YES, result, nil);
                    }
                    
                    //存储成功订单
                    [self SaveIapSuccessReceiptDataWithReceipt:receipt Order:order UserId:userId];
                    
                    [self successConsumptionOfGoodsWithOrder:order];
                    
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
                                                
                                                [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"请求异常", @"")];
                                                
                                            }];
                                        });
                                        
                                    }
                                    
#pragma 校验发货失败 3
                                } failure:^(ULSDKAPI *api, NSString *failure) {
                                    
                                    [RRHUD hide];
                                    
                                    [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"请求异常", @"")];
                                    
                                }];
                                
                            });
                            
                        }
                        
#pragma 校验发货失败 1
                    } failure:^(ULSDKAPI *api, NSString *failure) {
                        
                        [RRHUD hide];
                        [RRHUD showErrorWithContainerView:UL_rootVC.view status:NSLocalizedString(@"请求异常", @"")];
                        
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
-(void)successConsumptionOfGoodsWithOrder:(NSString * )cpOrder{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    if ([fileManager fileExistsAtPath:[SandBoxHelper iapReceiptPath]]) {

        NSArray * cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper iapReceiptPath] error:&error];
        
        if (error == nil) {
            
            for (NSString * name in cacheFileNameArray) {
                
                NSString * filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper iapReceiptPath], name];
                
                [self removeReceiptWithPlistPath:filePath ByCpOrder:cpOrder];
                
            }
        }
    }
}


#pragma mark -- 根据订单号来删除 存储的凭证
-(void)removeReceiptWithPlistPath:(NSString *)plistPath ByCpOrder:(NSString *)cpOrder{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError * error;
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    NSString * order = [dic objectForKey:@"order"];
    
    if ([cpOrder isEqualToString:order]) {
        
        //移除与游戏cp订单号一样的plist 文件
        BOOL ifRemove =  [fileManager removeItemAtPath:plistPath error:&error];
        
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
