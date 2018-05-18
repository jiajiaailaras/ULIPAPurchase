//
//  IPAPurchase.h
//  iOS_Purchase
//
//  Created by zhanfeng on 2017/6/6.
//  Copyright © 2017年 zhanfeng. All rights reserved.
//

#import <Foundation/Foundation.h>


/**
 block

 @param isSuccess 是否支付成功
 @param certificate 支付成功得到的凭证（用于在自己服务器验证）
 @param errorMsg 错误信息
 */
typedef void(^PayResult)(BOOL isSuccess,NSString *certificate,NSString *errorMsg);

@interface IPAPurchase : NSObject
@property (nonatomic, copy)PayResult payResultBlock;

//内购注册相关
@property (nonatomic,copy)NSString * order;//callback 返回的订单号
@property (nonatomic,copy)NSString * order_sn ;//平台订单号
@property (nonatomic,copy)NSString * userid;//游戏用户ID
@property (nonatomic,copy)NSString * money;//充值金额
@property (nonatomic,copy)NSString * money_type;//货币类型
@property (nonatomic,copy)NSString * extend;//平台扩展参数
@property (nonatomic,copy)NSString * pay_type;//支付类型
@property (nonatomic,copy)NSString * server_id;//服务器ID
@property (nonatomic,copy)NSString * role_id;//角色ID
@property (nonatomic,copy)NSString * role_name;//角色名
@property (nonatomic,copy)NSString * role_level;//角色等级
@property (nonatomic,copy)NSString * goods_id;//cp商品ID
@property (nonatomic,copy)NSString * goods_name;//cp商品名称
@property (nonatomic,copy)NSString * third_goods_id;//我们苹果商品ID
@property (nonatomic,copy)NSString * third_goods_name;//苹果商品名称
@property (nonatomic,copy)NSString * cp_trade_sn;//cp订单号
@property (nonatomic,copy)NSString * ext_data;//cp扩展参数
@property (nonatomic,copy)NSString * app_channel;//付费所属渠道
@property (nonatomic,copy)NSString * channel_trade_sn;//channel_trade_sn


@property(nonatomic,copy)NSString * amount_type; //货币类型
@property(nonatomic,copy)NSString * platformAmount; //货币金额

+ (instancetype)manager;

/**
 启动内购工具
 */
-(void)startManager;


-(void)stopManager;
/**
 内购支付
 @param productID 内购商品ID
 @param payResult 结果
 */
-(void)buyProductWithProductID:(NSString *)productID payResult:(PayResult)payResult;


@end
