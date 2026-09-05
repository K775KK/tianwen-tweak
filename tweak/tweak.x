/**
 * tweak.x — 天问1 + 天问2 弹窗阻断 + 悬浮球创建补丁
 *
 * v2.1 - Fix crash: use original IMP to avoid recursion
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>

#define LOG(fmt, ...) NSLog(@"[TianwenTweak] " fmt, ##__VA_ARGS__)

static IMP orig_showVerifyAlert_IMP = NULL;
static IMP orig_refreshConfig_IMP   = NULL;
static IMP orig_showErrorAlert_IMP  = NULL;
static IMP orig_presentViewController_IMP = NULL;

static NSArray<NSString *> *kBlockedKeywords = nil;

static void postVerifiedNotification(void) {
    LOG("发送 KAMIPluginVerifiedNotification 创建悬浮球...");
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"KAMIPluginVerifiedNotification" object:nil];
    LOG("通知已发送");
}

static void hooked_showVerifyAlert(id self, SEL _cmd) {
    LOG("showVerifyAlertIfNeeded -> blocked");
}

static void hooked_refreshConfig(id self, SEL _cmd) {
    LOG("refreshConfigAndShowVerifyAlertIfNeeded -> blocked");
}

static void hooked_showErrorAlert(id self, SEL _cmd, id arg) {
    LOG("showErrorAlert: -> blocked");
}

static void hooked_presentViewController(id self, SEL _cmd,
                                          UIViewController *viewController,
                                          BOOL animated,
                                          void (^completion)(void)) {
    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewController;
        NSString *text = [NSString stringWithFormat:@"%@ %@",
                          alert.title ?: @"", alert.message ?: @""];
        for (NSString *keyword in kBlockedKeywords) {
            if ([text containsString:keyword]) {
                LOG("alert blocked: '%@' '%@' (keyword: '%@')",
                    alert.title, alert.message, keyword);
                return;
            }
        }
    }
    // Call original IMP directly to avoid recursion
    if (orig_presentViewController_IMP) {
        ((void(*)(id, SEL, UIViewController*, BOOL, void(^)(void)))
            orig_presentViewController_IMP)(self, _cmd, viewController, animated, completion);
    }
}

static BOOL patchTianwen1(void) {
    LOG("扫描天问1 验证管理器...");
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    BOOL found = NO;
    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        if (strstr(name, "KamiNetworkVerifyManager")) {
            LOG("找到 %s", name);
            SEL sel1 = NSSelectorFromString(@"showVerifyAlertIfNeeded");
            Method m1 = class_getInstanceMethod(classes[i], sel1);
            if (m1) {
                orig_showVerifyAlert_IMP = method_getImplementation(m1);
                method_setImplementation(m1, (IMP)hooked_showVerifyAlert);
                LOG("V Hook showVerifyAlertIfNeeded");
                found = YES;
            }
            SEL sel2 = NSSelectorFromString(@"refreshConfigAndShowVerifyAlertIfNeeded");
            Method m2 = class_getInstanceMethod(classes[i], sel2);
            if (m2) {
                orig_refreshConfig_IMP = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)hooked_refreshConfig);
                LOG("V Hook refreshConfigAndShowVerifyAlertIfNeeded");
                found = YES;
            }
            break;
        }
    }
    free(classes);
    return found;
}

static BOOL patchTianwen2(void) {
    LOG("扫描天问2 验证管理器...");
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    BOOL found = NO;
    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        NSString *className = [NSString stringWithUTF8String:name];
        if ([className hasPrefix:@"UI"] || [className hasPrefix:@"NS"] ||
            [className hasPrefix:@"_UI"] || [className hasPrefix:@"__"])
            continue;
        objc_property_t prop = class_getProperty(classes[i], "activatedSlot1");
        if (prop == NULL) prop = class_getProperty(classes[i], "_activatedSlot1");
        if (prop != NULL) {
            LOG("找到天问2 验证管理器: %s", name);
            SEL sel = @selector(showErrorAlert:);
            Method method = class_getInstanceMethod(classes[i], sel);
            if (method) {
                orig_showErrorAlert_IMP = method_getImplementation(method);
                method_setImplementation(method, (IMP)hooked_showErrorAlert);
                LOG("V Hook %s showErrorAlert:", name);
                found = YES;
            }
            id shared = nil;
            SEL sharedSel = NSSelectorFromString(@"sharedInstance");
            if ([classes[i] respondsToSelector:sharedSel])
                shared = [classes[i] performSelector:sharedSel];
            if (shared) {
                LOG("设置激活状态...");
                SEL s1 = NSSelectorFromString(@"setActivatedSlot1:");
                if ([shared respondsToSelector:s1]) [shared performSelector:s1 withObject:@YES];
                SEL s2 = NSSelectorFromString(@"setActivatedSlot2:");
                if ([shared respondsToSelector:s2]) [shared performSelector:s2 withObject:@YES];
                SEL s3 = NSSelectorFromString(@"setActivatedSlot3:");
                if ([shared respondsToSelector:s3]) [shared performSelector:s3 withObject:@YES];
            }
            break;
        }
    }
    free(classes);
    return found;
}

static void hookAllShowErrorAlert(void) {
    LOG("全局扫描 showErrorAlert:（兜底）...");
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    int hookedCount = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        SEL sel = @selector(showErrorAlert:);
        Method method = class_getInstanceMethod(classes[i], sel);
        if (!method) continue;
        const char *name = class_getName(classes[i]);
        IMP imp = method_getImplementation(method);
        NSString *cn = [NSString stringWithUTF8String:name];
        if ([cn hasPrefix:@"UI"] || [cn hasPrefix:@"NS"] ||
            [cn hasPrefix:@"_UI"] || [cn hasPrefix:@"__"]) continue;
        if (imp == (IMP)hooked_showErrorAlert) continue;
        Dl_info info;
        if (dladdr((void *)imp, &info)) {
            NSString *lib = info.dli_fname ? @(info.dli_fname) : @"";
            if ([lib containsString:@"天问1"] || [lib containsString:@"天问2"] ||
                [lib containsString:@"tianwen"] || [lib containsString:@"Vacm"]) {
                method_setImplementation(method, (IMP)hooked_showErrorAlert);
                hookedCount++;
                LOG("  V Hook %s showErrorAlert:", name);
            }
        }
    }
    free(classes);
    LOG("共 Hook %d 个 showErrorAlert:", hookedCount);
}

static void delayedInit(void) {
    LOG("延迟初始化...");
    BOOL t2 = patchTianwen2();
    if (!t2) { LOG("天问2 未找到，全局兜底"); hookAllShowErrorAlert(); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        postVerifiedNotification();
        LOG("========================================");
        LOG("  完成！弹窗已阻止，悬浮球已创建");
        LOG("========================================");
    });
}

__attribute__((constructor))
static void tweak_init(void) {
    LOG("v2.1 loaded");

    kBlockedKeywords = @[@"网络异常", @"请检查网络", @"验证", @"卡密",
                         @"card_no", @"CardVerify", @"KamiNetwork", @"VacmNetwork"];

    // Hook UIViewController presentViewController to filter alerts
    Method m2 = class_getInstanceMethod([UIViewController class],
        @selector(presentViewController:animated:completion:));
    if (m2) {
        orig_presentViewController_IMP = method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hooked_presentViewController);
        LOG("V Hook presentViewController:animated:completion:");
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL t1 = patchTianwen1();
        LOG(t1 ? "天问1 OK" : "天问1 未找到");
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ delayedInit(); });
}
