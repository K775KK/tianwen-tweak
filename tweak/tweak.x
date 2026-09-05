/**
 * tweak.x — 天问1 + 天问2 弹窗阻断 + 悬浮球创建补丁
 *
 * v2.0 - 增加 UIAlertController 全局拦截
 *
 * 编译方法：
 *   macOS: export THEOS=~/theos && cd tweak && make package FINALPACKAGE=1
 *   Windows: 用 GitHub Actions 自动编译（见 .github/workflows/build.yml）
 *
 * 注入方式：
 *   通过巨魔注入器把编译好的 dylib 注入到抖音
 *   与天问1.dylib、天问2.dylib 共存
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>

// =====================================================================
// 日志
// =====================================================================
#define LOG(fmt, ...) NSLog(@"[TianwenTweak] " fmt, ##__VA_ARGS__)

// =====================================================================
// 天问1 Hook
// =====================================================================
static IMP orig_showVerifyAlert_IMP = NULL;
static IMP orig_refreshConfig_IMP   = NULL;

// =====================================================================
// 天问2 Hook
// =====================================================================
static IMP orig_showErrorAlert_IMP = NULL;

// =====================================================================
// UIAlertController 拦截
// =====================================================================
static IMP orig_alertControllerWithAlertStyle_IMP = NULL;
static IMP orig_presentViewController_IMP = NULL;

// =====================================================================
// 需要拦截的关键词
// =====================================================================
static NSArray<NSString *> *kBlockedKeywords = nil;

// =====================================================================
// 发送验证成功通知（创建悬浮球）
// =====================================================================
static void postVerifiedNotification(void) {
    LOG("发送 KAMIPluginVerifiedNotification 创建悬浮球...");

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"KAMIPluginVerifiedNotification"
                      object:nil];

    LOG("通知已发送");
}

// =====================================================================
// Hook 实现：showVerifyAlertIfNeeded（天问1）
// =====================================================================
static void hooked_showVerifyAlert(id self, SEL _cmd) {
    LOG("showVerifyAlertIfNeeded 被调用 -> 已阻止");
    // 直接不调用原函数 = 阻止弹窗
}

// =====================================================================
// Hook 实现：refreshConfigAndShowVerifyAlertIfNeeded（天问1）
// =====================================================================
static void hooked_refreshConfig(id self, SEL _cmd) {
    LOG("refreshConfigAndShowVerifyAlertIfNeeded 被调用 -> 已阻止");
    // 直接不调用原函数 = 阻止弹窗
}

// =====================================================================
// Hook 实现：showErrorAlert:（天问2 兜底）
// =====================================================================
static void hooked_showErrorAlert(id self, SEL _cmd, id arg) {
    LOG("天问2 showErrorAlert: 被调用 -> 已阻止");
    // 直接不调用原函数 = 阻止弹窗
}

// =====================================================================
// Hook 实现：UIAlertController alertControllerWithTitle:
//   拦截所有创建的 alert，过滤验证相关消息
// =====================================================================
static id hooked_alertControllerWithTitle(id self, SEL _cmd, 
                                           NSString *title, 
                                           NSString *message, 
                                           NSInteger preferredStyle) {
    // 检查标题和消息是否包含被拦截的关键词
    NSString *textToCheck = [NSString stringWithFormat:@"%@ %@", 
                             title ?: @"", message ?: @""];
    
    for (NSString *keyword in kBlockedKeywords) {
        if ([textToCheck containsString:keyword]) {
            LOG("UIAlertController 被拦截: title='%@' message='%@' (包含 '%@')", 
                title, message, keyword);
            // 返回一个空的 alert controller，或者返回 nil
            // 返回 nil 可能导致崩溃，所以我们返回一个空的
            UIAlertController *fake = [UIAlertController 
                alertControllerWithTitle:nil 
                message:nil 
                preferredStyle:UIAlertControllerStyleActionSheet];
            return fake;
        }
    }
    
    // 不是验证相关的 alert，正常创建
    return [[self class] alertControllerWithTitle:title 
                                         message:message 
                                  preferredStyle:preferredStyle];
}

// =====================================================================
// Hook 实现：UIViewController presentViewController:
//   拦截所有显示的 alert，过滤验证相关消息
// =====================================================================
static void hooked_presentViewController(id self, SEL _cmd, 
                                          UIViewController *viewController,
                                          BOOL animated, 
                                          void (^completion)(void)) {
    // 检查是否是 UIAlertController
    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewController;
        NSString *textToCheck = [NSString stringWithFormat:@"%@ %@", 
                                 alert.title ?: @"", alert.message ?: @""];
        
        for (NSString *keyword in kBlockedKeywords) {
            if ([textToCheck containsString:keyword]) {
                LOG("UIViewController present 被拦截: title='%@' message='%@' (包含 '%@')", 
                    alert.title, alert.message, keyword);
                return; // 不显示
            }
        }
    }
    
    // 不是验证相关的 alert，正常显示
    if (completion) {
        [self presentViewController:viewController animated:animated completion:completion];
    } else {
        [self presentViewController:viewController animated:animated completion:nil];
    }
}

// =====================================================================
// 扫描并 Hook 天问1 的弹窗函数
// =====================================================================
static BOOL patchTianwen1(void) {
    LOG("扫描天问1 验证管理器...");

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    BOOL found = NO;

    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);

        // 找到 KamiNetworkVerifyManager
        if (strstr(name, "KamiNetworkVerifyManager")) {
            LOG("找到 %s", name);

            // Hook showVerifyAlertIfNeeded
            SEL sel1 = NSSelectorFromString(@"showVerifyAlertIfNeeded");
            Method m1 = class_getInstanceMethod(classes[i], sel1);
            if (m1) {
                orig_showVerifyAlert_IMP = method_getImplementation(m1);
                method_setImplementation(m1, (IMP)hooked_showVerifyAlert);
                LOG("V Hook showVerifyAlertIfNeeded");
                found = YES;
            }

            // Hook refreshConfigAndShowVerifyAlertIfNeeded
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

// =====================================================================
// 扫描并 Hook 天问2 的验证管理器
// =====================================================================
static BOOL patchTianwen2(void) {
    LOG("扫描天问2 验证管理器...");

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    BOOL found = NO;

    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        NSString *className = [NSString stringWithUTF8String:name];

        // 跳过系统类
        if ([className hasPrefix:@"UI"] ||
            [className hasPrefix:@"NS"] ||
            [className hasPrefix:@"_UI"] ||
            [className hasPrefix:@"__"]) {
            continue;
        }

        // 查找含 activatedSlot1 属性的类
        objc_property_t prop = class_getProperty(classes[i], "activatedSlot1");
        if (prop == NULL) {
            prop = class_getProperty(classes[i], "_activatedSlot1");
        }

        if (prop != NULL) {
            LOG("找到天问2 验证管理器: %s", name);

            // Hook showErrorAlert:
            SEL sel = @selector(showErrorAlert:);
            Method method = class_getInstanceMethod(classes[i], sel);
            if (method) {
                orig_showErrorAlert_IMP = method_getImplementation(method);
                method_setImplementation(method, (IMP)hooked_showErrorAlert);
                LOG("V Hook %s showErrorAlert:", name);
                found = YES;
            }

            // 尝试设置验证状态
            id shared = nil;
            SEL sharedSel = NSSelectorFromString(@"sharedInstance");
            if ([classes[i] respondsToSelector:sharedSel]) {
                shared = [classes[i] performSelector:sharedSel];
            }

            if (shared) {
                LOG("找到 sharedInstance，设置激活状态...");

                // 设置 activatedSlot1/2/3 = YES
                SEL setSel1 = NSSelectorFromString(@"setActivatedSlot1:");
                if ([shared respondsToSelector:setSel1]) {
                    [shared performSelector:setSel1 withObject:@YES];
                    LOG("  activatedSlot1 = YES");
                }

                SEL setSel2 = NSSelectorFromString(@"setActivatedSlot2:");
                if ([shared respondsToSelector:setSel2]) {
                    [shared performSelector:setSel2 withObject:@YES];
                    LOG("  activatedSlot2 = YES");
                }

                SEL setSel3 = NSSelectorFromString(@"setActivatedSlot3:");
                if ([shared respondsToSelector:setSel3]) {
                    [shared performSelector:setSel3 withObject:@YES];
                    LOG("  activatedSlot3 = YES");
                }
            }

            break;
        }
    }

    free(classes);
    return found;
}

// =====================================================================
// 全局 showErrorAlert: Hook（兜底，捕获所有未知的弹窗类）
// =====================================================================
static void hookAllShowErrorAlert(void) {
    LOG("全局扫描 showErrorAlert: 方法（兜底）...");

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    int hookedCount = 0;

    for (unsigned int i = 0; i < classCount; i++) {
        SEL sel = @selector(showErrorAlert:);
        Method method = class_getInstanceMethod(classes[i], sel);
        if (method) {
            const char *name = class_getName(classes[i]);
            IMP imp = method_getImplementation(method);

            // 跳过系统类和已经 hook 过的
            NSString *className = [NSString stringWithUTF8String:name];
            if ([className hasPrefix:@"UI"] ||
                [className hasPrefix:@"NS"] ||
                [className hasPrefix:@"_UI"] ||
                [className hasPrefix:@"__"]) {
                continue;
            }

            // 跳过已经是我们的 hook 的
            if (imp == (IMP)hooked_showErrorAlert) {
                continue;
            }

            // 只 hook 来自天问 dylib 的类
            // 通过检查实现地址是否在天问 dylib 的内存范围内
            Dl_info info;
            if (dladdr((void *)imp, &info)) {
                NSString *libPath = info.dli_fname ? @(info.dli_fname) : @"";
                if ([libPath containsString:@"天问1"] ||
                    [libPath containsString:@"天问2"] ||
                    [libPath containsString:@"tianwen"] ||
                    [libPath containsString:@"Vacm"]) {
                    method_setImplementation(method, (IMP)hooked_showErrorAlert);
                    hookedCount++;
                    LOG("  V Hook %s showErrorAlert: (来自 %s)", name, info.dli_fname);
                }
            }
        }
    }

    free(classes);
    LOG("共 Hook %d 个 showErrorAlert:", hookedCount);
}

// =====================================================================
// Hook UIAlertController（全局拦截验证相关弹窗）
// =====================================================================
static void hookUIAlertController(void) {
    LOG("Hook UIAlertController 全局拦截...");
    
    // Hook alertControllerWithTitle:message:preferredStyle:
    Method m1 = class_getClassMethod([UIAlertController class], 
        @selector(alertControllerWithTitle:message:preferredStyle:));
    if (m1) {
        orig_alertControllerWithAlertStyle_IMP = method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hooked_alertControllerWithTitle);
        LOG("V Hook alertControllerWithTitle:message:preferredStyle:");
    }
    
    // Hook presentViewController:animated:completion:
    Method m2 = class_getInstanceMethod([UIViewController class], 
        @selector(presentViewController:animated:completion:));
    if (m2) {
        orig_presentViewController_IMP = method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hooked_presentViewController);
        LOG("V Hook presentViewController:animated:completion:");
    }
}

// =====================================================================
// 延迟初始化（等天问1 和天问2 都加载完）
// =====================================================================
static void delayedInit(void) {
    LOG("延迟初始化开始...");

    // 扫描天问2
    BOOL t2patched = patchTianwen2();
    if (!t2patched) {
        LOG("天问2 未找到，尝试全局兜底...");
        hookAllShowErrorAlert();
    }

    // 延迟 3 秒后发送通知（等所有初始化完成）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        postVerifiedNotification();
        LOG("========================================");
        LOG("  全部完成！弹窗已阻止，悬浮球已创建");
        LOG("========================================");
    });
}

// =====================================================================
// +load 入口（dylib 加载时自动执行）
// =====================================================================
__attribute__((constructor))
static void tweak_init(void) {
    LOG("补丁 dylib 已加载");
    LOG("目标: 阻止天问1+天问2 弹窗，创建悬浮球");
    
    // 初始化关键词列表
    kBlockedKeywords = @[
        @"网络异常",
        @"请检查网络",
        @"验证",
        @"卡密",
        @"card_no",
        @"CardVerify",
        @"KamiNetwork",
        @"VacmNetwork"
    ];
    LOG("拦截关键词: %@", kBlockedKeywords);

    // 立即 Hook UIAlertController（全局拦截）
    hookUIAlertController();

    // 延迟 0.5 秒后 Hook 天问1（等 dylib 加载）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL t1patched = patchTianwen1();
        if (t1patched) {
            LOG("天问1 Hook 成功");
        } else {
            LOG("警告: 天问1 验证管理器未找到");
        }
    });

    // 启动延迟初始化（处理天问2 + 发送通知）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        delayedInit();
    });
}
