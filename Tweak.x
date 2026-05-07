#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// --- 配置区域 ---
static NSString *const kAmapAPIKey = @"903a801c62a78e15251674446544dd7b"; 
static NSString *const kFishApiKey = @"6fc80f0fdc034e48b950ae3431440486";
static NSString *const kNailuVoiceId = @"0e8b746ea1a8489084d4e9fe2dfe802f"; // 明前奶绿核心 ID

// 全局 UI 组件
static UILabel *overlayLabel = nil;
static UIView *overlayContainer = nil;

// 播放器组件
static AVAudioPlayer *nailuPlayer = nil;

/**
 * 🛠 语音播报逻辑 - 彻底抛弃系统 TTS，改用 Fish Audio 云端奶绿原声
 */
static void speakText(NSString *text) {
    if (!text || text.length == 0) return;

    NSURL *url = [NSURL URLWithString:@"https://api.fish.audio/v1/tts"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", kFishApiKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    // 奶绿专属参数包
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
                NSError *playerError = nil;
                // 停止旧播报
                if (nailuPlayer && [nailuPlayer isPlaying]) {
                    [nailuPlayer stop];
                }
                
                nailuPlayer = [[AVAudioPlayer alloc] initWithData:data error:&playerError];
                if (!playerError) {
                    // 确保在 15 Pro Max 上不论是否静音都能响
                    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
                    [[AVAudioSession sharedInstance] setActive:YES error:nil];
                    
                    [nailuPlayer prepareToPlay];
                    [nailuPlayer play];
                }
            });
        }
    }] resume];
}

/**
 * 🛠 获取当前活跃窗口
 */
static UIWindow* getKeyWindow() {
    UIWindow *foundWindow = nil;
    NSArray *scenes = [[UIApplication sharedApplication] connectedScenes].allObjects;
    for (id scene in scenes) {
        if ([scene isKindOfClass:NSClassFromString(@"UIWindowScene")] && [scene activationState] == UISceneActivationStateForegroundActive) {
            NSArray *windows = ((UIWindowScene *)scene).windows;
            for (UIWindow *window in windows) {
                if (window.isKeyWindow) {
                    foundWindow = window;
                    break;
                }
            }
        }
        if (foundWindow) break;
    }
    if (!foundWindow && scenes.count > 0) {
        id firstScene = scenes.firstObject;
        if ([firstScene isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
            foundWindow = ((UIWindowScene *)firstScene).windows.firstObject;
        }
    }
    return foundWindow;
}

/**
 * 🎨 UI 初始化
 */
static void ensureOverlayUI() {
    if (overlayContainer) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getKeyWindow();
        if (!keyWindow) return;

        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        UIVisualEffectView *visualEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        
        overlayContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 65, screenWidth - 40, 42)];
        visualEffectView.frame = overlayContainer.bounds;
        visualEffectView.layer.cornerRadius = 14;
        visualEffectView.layer.masksToBounds = YES;
        
        [overlayContainer addSubview:visualEffectView];
        overlayLabel = [[UILabel alloc] initWithFrame:overlayContainer.bounds];
        overlayLabel.textColor = [UIColor whiteColor];
        overlayLabel.textAlignment = NSTextAlignmentCenter;
        overlayLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        overlayLabel.text = @"等待订单接入...";
        
        [overlayContainer addSubview:overlayLabel];
        overlayContainer.alpha = 0; 
        overlayContainer.userInteractionEnabled = NO; 
        [keyWindow addSubview:overlayContainer];
    });
}

/**
 * 🚀 获取耗时并展示（调用奶绿）
 */
static void fetchTimeAndShow(NSString *origin, NSString *destination) {
    NSString *urlStr = [NSString stringWithFormat:@"https://restapi.amap.com/v3/direction/driving?origin=%@&destination=%@&key=%@&extensions=base", origin, destination, kAmapAPIKey];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json[@"status"] isEqualToString:@"1"]) {
                NSArray *paths = json[@"route"][@"paths"];
                if (paths.count > 0) {
                    int duration = [paths[0][@"duration"] intValue];
                    int totalMins = duration / 60;
                    int h = totalMins / 60;
                    int m = totalMins % 60;
                    
                    NSString *displayTime;
                    NSString *speechTime;
                    
                    if (h > 0) {
                        displayTime = [NSString stringWithFormat:@"%d小时%d分钟", h, m];
                        speechTime = [NSString stringWithFormat:@"老板老板~ 这单预计全程用时%d小时%d分钟", h, m];
                    } else {
                        displayTime = [NSString stringWithFormat:@"%d分钟", m];
                        speechTime = [NSString stringWithFormat:@"老板~ 这单预计全程用时%d分钟", m];
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ensureOverlayUI();
                        overlayLabel.text = [NSString stringWithFormat:@"预计全程用时 %@", displayTime];
                        speakText(speechTime); // 这里会通过 Fish Audio 发声
                        
                        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            overlayContainer.alpha = 1.0;
                            overlayContainer.transform = CGAffineTransformMakeTranslation(0, 5);
                        } completion:nil];
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [UIView animateWithDuration:1.0 animations:^{ overlayContainer.alpha = 0.2; }];
                        });
                    });
                }
            }
        }
    }] resume];
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
                if (start && end) {
                    NSString *origin = [NSString stringWithFormat:@"%@,%@", start[@"lon"], start[@"lat"]];
                    NSString *destination = [NSString stringWithFormat:@"%@,%@", end[@"lon"], end[@"lat"]];
                    fetchTimeAndShow(origin, destination);
                }
            }
        } @catch (NSException *e) {}
    }
    return result;
}
%end