#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// --- 配置区域 ---
static NSString *const kAmapAPIKey = @"903a801c62a78e15251674446544dd7b"; 

// 全局 UI 组件
static UILabel *overlayLabel = nil;
static UIView *overlayContainer = nil;

/**
 * 🛠 获取当前活跃窗口的兼容方案 (解决 iOS 13+ 弃用问题)
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
    // 兜底方案：如果找不到活跃场景，尝试取第一个场景的第一个窗口
    if (!foundWindow && scenes.count > 0) {
        id firstScene = scenes.firstObject;
        if ([firstScene isKindOfClass:NSClassFromString(@"UIWindowScene")]) {
            foundWindow = ((UIWindowScene *)firstScene).windows.firstObject;
        }
    }
    return foundWindow;
}

/**
 * 🎨 UI 初始化：创建一个精致的毛玻璃悬浮条
 */
static void ensureOverlayUI() {
    if (overlayContainer) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getKeyWindow(); // 使用新函数获取窗口
        if (!keyWindow) return;

        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        
        // 创建容器：带毛玻璃效果
        UIVisualEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        
        // 定位在屏幕顶部 (适配 iPhone 15 Pro Max 岛下位置)
        overlayContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 65, screenWidth - 40, 42)];
        visualEffectView.frame = overlayContainer.bounds;
        visualEffectView.layer.cornerRadius = 14;
        visualEffectView.layer.masksToBounds = YES;
        
        [overlayContainer addSubview:visualEffectView];
        
        // 创建文字 Label
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
 * 🚀 核心逻辑：获取耗时并展示
 */
static void fetchTimeAndShow(NSString *origin, NSString *destination) {
    NSString *urlStr = [NSString stringWithFormat:@"https://restapi.amap.com/v3/direction/driving?origin=%@&destination=%@&key=%@&extensions=base", origin, destination, kAmapAPIKey];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json[@"status"] isEqualToString:@"1"]) {
                NSArray *paths = json[@"route"][@"paths"];
                if (paths.count > 0) {
                    int duration = [paths[0][@"duration"] intValue]; // 秒
                    int totalMins = duration / 60; // 总分钟
                    
                    // --- 换算逻辑 ---
                    int hours = totalMins / 60;
                    int remainingMins = totalMins % 60;
                    
                    NSString *displayTime;
                    if (hours > 0) {
                        displayTime = [NSString stringWithFormat:@"%d小时%d分钟", hours, remainingMins];
                    } else {
                        displayTime = [NSString stringWithFormat:@"%d分钟", remainingMins];
                    }
                    // ----------------
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ensureOverlayUI();
                        overlayLabel.text = [NSString stringWithFormat:@"⏱ 哈啰增强：预计全程 %@", displayTime];
                        
                        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            overlayContainer.alpha = 1.0;
                            overlayContainer.transform = CGAffineTransformMakeTranslation(0, 5);
                        } completion:nil];
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [UIView animateWithDuration:1.0 animations:^{
                                overlayContainer.alpha = 0.2; 
                            }];
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