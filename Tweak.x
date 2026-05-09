#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h> 

// --- 配置区域 ---
static NSString *const kAmapAPIKey = @"903a801c62a78e15251674446544dd7b"; 
static NSString *const kFishApiKey = @"6fc80f0fdc034e48b950ae3431440486";
static NSString *const kNailuVoiceId = @"0e8b746ea1a8489084d4e9fe2dfe802f";

// 全局组件
static UILabel *overlayLabel = nil;
static UIView *overlayContainer = nil;
static AVAudioPlayer *nailuPlayer = nil;
static CLLocationManager *locationManager = nil;

/**
 * 🛠 语音播报逻辑
 */
static void speakText(NSString *text) {
    if (!text || text.length == 0) return;
    NSURL *url = [NSURL URLWithString:@"https://api.fish.audio/v1/tts"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", kFishApiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"text": text,
        @"reference_id": kNailuVoiceId,
        @"format": @"mp3",
        @"latency": @"normal"
    };
    [request setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (nailuPlayer && [nailuPlayer isPlaying]) [nailuPlayer stop];
                nailuPlayer = [[AVAudioPlayer alloc] initWithData:data error:nil];
                if (nailuPlayer) {
                    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
                    [[AVAudioSession sharedInstance] setActive:YES error:nil];
                    [nailuPlayer play];
                }
            });
        }
    }] resume];
}

/**
 * 🛠 获取当前窗口
 */
static UIWindow* getKeyWindow() {
    UIWindow *foundWindow = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) { foundWindow = window; break; }
            }
        }
        if (foundWindow) break;
    }
    return foundWindow;
}

/**
 * 🎨 UI 初始化 (三行展示：接人、订单、高速费)
 */
static void ensureOverlayUI() {
    if (overlayContainer) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getKeyWindow();
        if (!keyWindow) return;
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        overlayContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 65, screenWidth - 40, 68)];
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.frame = overlayContainer.bounds;
        blur.layer.cornerRadius = 16;
        blur.layer.masksToBounds = YES;
        [overlayContainer addSubview:blur];
        
        overlayLabel = [[UILabel alloc] initWithFrame:overlayContainer.bounds];
        overlayLabel.textColor = [UIColor whiteColor];
        overlayLabel.textAlignment = NSTextAlignmentCenter;
        overlayLabel.numberOfLines = 3;
        overlayLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        [overlayContainer addSubview:overlayLabel];
        overlayContainer.alpha = 0;
        [keyWindow addSubview:overlayContainer];
    });
}

/**
 * 🚀 核心逻辑：获取双段数据，并提取高速费
 */
static void fetchCombinedMetrics(NSString *pickupCoord, NSString *dropoffCoord, NSInteger tripCount) {
    if (!locationManager) {
        locationManager = [[CLLocationManager alloc] init];
        [locationManager requestWhenInUseAuthorization];
    }
    CLLocation *myLoc = locationManager.location;
    if (!myLoc) return;
    
    NSString *myCoord = [NSString stringWithFormat:@"%.6f,%.6f", myLoc.coordinate.longitude, myLoc.coordinate.latitude];
    
    // API 请求：必须带 extensions=base 或 all 以获取 tolls
    NSString *url1 = [NSString stringWithFormat:@"https://restapi.amap.com/v3/direction/driving?origin=%@&destination=%@&key=%@", myCoord, pickupCoord, kAmapAPIKey];
    NSString *url2 = [NSString stringWithFormat:@"https://restapi.amap.com/v3/direction/driving?origin=%@&destination=%@&key=%@", pickupCoord, dropoffCoord, kAmapAPIKey];

    __block NSString *pickupInfo = @"";
    __block NSString *orderInfo = @"";
    __block float estimatedTolls = 0;
    __block NSString *speechOrderPart = @"";

    dispatch_group_t group = dispatch_group_create();

    // 任务 A: 接人路线
    dispatch_group_enter(group);
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url1] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *path = [json[@"route"][@"paths"] firstObject];
            if (path) {
                float distKm = [path[@"distance"] floatValue] / 1000.0;
                int mins = [path[@"duration"] intValue] / 60;
                pickupInfo = [NSString stringWithFormat:@"接人: %.1fkm / %d分", distKm, mins];
            }
        }
        dispatch_group_leave(group);
    }] resume];

    // 任务 B: 订单路线 (含高速费)
    dispatch_group_enter(group);
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url2] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *path = [json[@"route"][@"paths"] firstObject];
            if (path) {
                float distKm = [path[@"distance"] floatValue] / 1000.0;
                estimatedTolls = [path[@"tolls"] floatValue]; // 提取高速费
                orderInfo = [NSString stringWithFormat:@"订单: %.1fkm / 高速费: %.0f元", distKm, estimatedTolls];
                speechOrderPart = [NSString stringWithFormat:@"订单全程%.1f公里，高速费预估%.0f块。", distKm, estimatedTolls];
            }
        }
        dispatch_group_leave(group);
    }] resume];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        ensureOverlayUI();
        
        NSString *passengerInfo = [NSString stringWithFormat:@"👤 乘客出行: %ld 次", (long)tripCount];
        overlayLabel.text = [NSString stringWithFormat:@"%@\n%@\n%@", passengerInfo, pickupInfo, orderInfo];
        
        // 动态调整高速费文字颜色：如果有高速费显示橙色，否则显示绿色
        if (estimatedTolls > 0) {
            overlayLabel.textColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0];
        } else {
            overlayLabel.textColor = [UIColor greenColor];
        }

        NSString *finalSpeech = [NSString stringWithFormat:@"老板，接人信息已更新。%@ 出行次数%ld次。", speechOrderPart, (long)tripCount];
        speakText(finalSpeech); 
        
        [UIView animateWithDuration:0.5 animations:^{ overlayContainer.alpha = 1.0; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:1.0 animations:^{ overlayContainer.alpha = 0.0; }];
        });
    });
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;
    if (result && [result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)result;
        @try {
            NSDictionary *dataField = dict[@"data"];
            if (dataField && [dataField isKindOfClass:[NSDictionary class]]) {
                NSDictionary *start = dataField[@"startPosition"];
                NSDictionary *end = dataField[@"endPosition"];
                
                NSInteger tripCount = 0;
                // 解析出行次数 (优先从常用字段和客情字典中找)
                if (dataField[@"tripCount"]) tripCount = [dataField[@"tripCount"] integerValue];
                else if (dataField[@"passengerInfo"][@"tripCount"]) tripCount = [dataField[@"passengerInfo"][@"tripCount"] integerValue];
                
                if (start && end) {
                    NSString *pickupCoord = [NSString stringWithFormat:@"%@,%@", start[@"lon"], start[@"lat"]];
                    NSString *dropoffCoord = [NSString stringWithFormat:@"%@,%@", end[@"lon"], end[@"lat"]];
                    fetchCombinedMetrics(pickupCoord, dropoffCoord, tripCount);
                }
            }
        } @catch (NSException *e) {}
    }
    return result;
}

// =================================================================================
// 🚀 纯手机端发包诱捕器 v2.0：追加模式，防止并发包互相覆盖！
// =================================================================================
+ (NSData *)dataWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error {
    // 调用原方法，保证 APP 正常运行
    NSData *result = %orig;
    
    if (obj && [obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)obj;
        
        @try {
            if (dict[@"action"]) {
                NSString *actionName = dict[@"action"];
                
                // 🎯 只要包名包含这些关键词，立刻触发！
                if ([actionName containsString:@"pickOrder"] || 
                    [actionName containsString:@"publish"] || 
                    [actionName containsString:@"route"] ||
                    [actionName containsString:@"trip"] ||
                    [actionName containsString:@"add"]) {
                    
                    // 把字典转成文本
                    NSString *dictString = dict.description; 
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // 1. 读取当前剪贴板里的旧内容
                        NSString *oldString = [UIPasteboard generalPasteboard].string;
                        if (!oldString) oldString = @"";
                        
                        // 2. 把新抓到的包拼接到最下面，用华丽的分割线隔开
                        NSString *newString = [NSString stringWithFormat:@"%@\n\n========== 🎯 新抓到的包: %@ ==========\n%@", oldString, actionName, dictString];
                        
                        // 3. 塞回剪贴板
                        [UIPasteboard generalPasteboard].string = newString;
                        
                        // 4. UI 弹窗提示
                        ensureOverlayUI();
                        overlayLabel.textColor = [UIColor greenColor];
                        overlayLabel.text = [NSString stringWithFormat:@"🎯 连击！抓到包了！\n[%@] \n已追加到剪贴板！", actionName];
                        overlayContainer.alpha = 1.0;
                        
                        // 显示 5 秒后消失
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [UIView animateWithDuration:1.0 animations:^{ overlayContainer.alpha = 0.0; }];
                        });
                    });
                }
            }
        } @catch (NSException *e) {}
    }
    
    return result;
}


%end
