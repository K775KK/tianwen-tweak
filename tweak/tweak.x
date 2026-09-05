/**
 * tweak.x — Tianwen1 + Tianwen2 popup blocker + floating ball creator
 *
 * v3.0 - Precision hooks only, NO UIViewController global hook
 *
 * Hooked methods (all business-level, no UIKit interference):
 *   天问1:
 *     showVerifyAlertIfNeeded                    → RET (block verify popup)
 *     refreshConfigAndShowVerifyAlertIfNeeded      → RET (block refresh popup)
 *     networkErrorMessage:                        → RET + LOG (block network error)
 *   天问2:
 *     showErrorAlert:                             → RET + LOG (block error popup)
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>

#define LOG(fmt, ...) NSLog(@"[TianwenTweak] " fmt, ##__VA_ARGS__)

// --- Hook handlers: all return immediately, no side effects ---

static void hook_showVerifyAlert(id self, SEL _cmd) {
    LOG("[BLOCKED] showVerifyAlertIfNeeded");
}

static void hook_refreshConfig(id self, SEL _cmd) {
    LOG("[BLOCKED] refreshConfigAndShowVerifyAlertIfNeeded");
}

static void hook_networkErrorMessage(id self, SEL _cmd, id message) {
    LOG("[BLOCKED] networkErrorMessage: %@", message);
}

static void hook_showErrorAlert(id self, SEL _cmd, id arg) {
    LOG("[BLOCKED] showErrorAlert: %@", arg);
}

// --- Patch Tianwen1: scan for KamiNetworkVerifyManager, hook 3 methods ---

static BOOL patchTianwen1(void) {
    LOG("Scanning for KamiNetworkVerifyManager...");
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    BOOL found = NO;

    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        if (!strstr(name, "KamiNetworkVerifyManager")) continue;

        LOG("Found class: %s", name);

        // Hook 1: showVerifyAlertIfNeeded
        SEL s1 = NSSelectorFromString(@"showVerifyAlertIfNeeded");
        Method m1 = class_getInstanceMethod(classes[i], s1);
        if (m1) {
            method_setImplementation(m1, (IMP)hook_showVerifyAlert);
            LOG("  V hook showVerifyAlertIfNeeded");
            found = YES;
        }

        // Hook 2: refreshConfigAndShowVerifyAlertIfNeeded
        SEL s2 = NSSelectorFromString(@"refreshConfigAndShowVerifyAlertIfNeeded");
        Method m2 = class_getInstanceMethod(classes[i], s2);
        if (m2) {
            method_setImplementation(m2, (IMP)hook_refreshConfig);
            LOG("  V hook refreshConfigAndShowVerifyAlertIfNeeded");
            found = YES;
        }

        // Hook 3: networkErrorMessage: — blocks the "网络异常" popup
        SEL s3 = NSSelectorFromString(@"networkErrorMessage:");
        Method m3 = class_getInstanceMethod(classes[i], s3);
        if (m3) {
            method_setImplementation(m3, (IMP)hook_networkErrorMessage);
            LOG("  V hook networkErrorMessage:");
            found = YES;
        } else {
            // networkErrorMessage: might be on a superclass or protocol
            // Try hooking it on all classes that respond to it
            LOG("  networkErrorMessage: not on this class, scanning all classes...");
            for (unsigned int j = 0; j < classCount; j++) {
                Method mj = class_getInstanceMethod(classes[j], s3);
                if (!mj) continue;
                const char *jn = class_getName(classes[j]);
                NSString *jns = [NSString stringWithUTF8String:jn];
                // Skip Apple system classes
                if ([jns hasPrefix:@"UI"] || [jns hasPrefix:@"NS"] ||
                    [jns hasPrefix:@"_UI"] || [jns hasPrefix:@"__"] ||
                    [jns hasPrefix:@"OS_"]) continue;
                // Check if this method's IMP lives in our dylib
                Dl_info info;
                IMP imp = method_getImplementation(mj);
                if (dladdr((void *)imp, &info) && info.dli_fname) {
                    NSString *lib = [NSString stringWithUTF8String:info.dli_fname];
                    if ([lib containsString:@"天问1"] || [lib containsString:@"tianwen1"]) {
                        method_setImplementation(mj, (IMP)hook_networkErrorMessage);
                        LOG("  V hook networkErrorMessage: on %s", jn);
                        found = YES;
                        break;
                    }
                }
            }
        }

        break;  // Only need first match
    }
    free(classes);
    return found;
}

// --- Patch Tianwen2: scan for activatedSlot1 property, hook showErrorAlert: ---

static BOOL patchTianwen2(void) {
    LOG("Scanning for Tianwen2 manager...");
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    BOOL found = NO;

    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        NSString *cn = [NSString stringWithUTF8String:name];
        // Skip system classes
        if ([cn hasPrefix:@"UI"] || [cn hasPrefix:@"NS"] ||
            [cn hasPrefix:@"_UI"] || [cn hasPrefix:@"__"]) continue;

        // Look for activatedSlot1 property (Tianwen2 signature)
        objc_property_t prop = class_getProperty(classes[i], "activatedSlot1");
        if (!prop) prop = class_getProperty(classes[i], "_activatedSlot1");
        if (!prop) continue;

        LOG("Found Tianwen2 manager: %s", name);

        // Hook showErrorAlert:
        SEL sErr = @selector(showErrorAlert:);
        Method mErr = class_getInstanceMethod(classes[i], sErr);
        if (mErr) {
            method_setImplementation(mErr, (IMP)hook_showErrorAlert);
            LOG("  V hook showErrorAlert:");
            found = YES;
        }

        // Try to set activated slots via sharedInstance
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([classes[i] respondsToSelector:sharedSel]) {
            id shared = [classes[i] performSelector:sharedSel];
            if (shared) {
                LOG("  Setting activation slots...");
                SEL sets[] = {
                    NSSelectorFromString(@"setActivatedSlot1:"),
                    NSSelectorFromString(@"setActivatedSlot2:"),
                    NSSelectorFromString(@"setActivatedSlot3:")
                };
                for (int s = 0; s < 3; s++) {
                    if ([shared respondsToSelector:sets[s]])
                        [shared performSelector:sets[s] withObject:@YES];
                }
            }
        }
        break;
    }
    free(classes);
    return found;
}

// --- Also hook showErrorAlert: on any Tianwen-derived class as fallback ---

static void hookAllTianwenShowErrorAlert(void) {
    LOG("Fallback: scanning all classes for showErrorAlert: from Tianwen libs...");
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    int count = 0;

    SEL sErr = @selector(showErrorAlert:);
    for (unsigned int i = 0; i < classCount; i++) {
        Method m = class_getInstanceMethod(classes[i], sErr);
        if (!m) continue;
        if (method_getImplementation(m) == (IMP)hook_showErrorAlert) continue;

        NSString *cn = [NSString stringWithUTF8String:class_getName(classes[i])];
        if ([cn hasPrefix:@"UI"] || [cn hasPrefix:@"NS"] ||
            [cn hasPrefix:@"_UI"] || [cn hasPrefix:@"__"]) continue;

        Dl_info info;
        IMP imp = method_getImplementation(m);
        if (dladdr((void *)imp, &info) && info.dli_fname) {
            NSString *lib = [NSString stringWithUTF8String:info.dli_fname];
            if ([lib containsString:@"天问1"] || [lib containsString:@"天问2"] ||
                [lib containsString:@"tianwen"] || [lib containsString:@"Vacm"] ||
                [lib containsString:@"VCam"]) {
                method_setImplementation(m, (IMP)hook_showErrorAlert);
                count++;
                LOG("  V hook %s showErrorAlert:", class_getName(classes[i]));
            }
        }
    }
    free(classes);
    LOG("Fallback hooked %d classes", count);
}

// --- Post notification to create floating ball ---

static void postVerifiedNotification(void) {
    LOG("Posting KAMIPluginVerifiedNotification...");
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"KAMIPluginVerifiedNotification" object:nil];
    LOG("Notification posted");
}

// --- Entry point ---

__attribute__((constructor))
static void tweak_init(void) {
    LOG("=== TianwenTweak v3.0 loaded ===");
    LOG("Strategy: precision business hooks ONLY, no UIKit interference");

    // Phase 1: Hook Tianwen1 (0.5s delay for class registration)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL ok = patchTianwen1();
        if (ok) LOG("Tianwen1: patched OK");
        else LOG("Tianwen1: class not found");
    });

    // Phase 2: Hook Tianwen2 + fallback (1.5s delay)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL ok = patchTianwen2();
        if (!ok) {
            LOG("Tianwen2: class not found, running fallback");
            hookAllTianwenShowErrorAlert();
        }
    });

    // Phase 3: Post notification to create floating ball (3s delay)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        postVerifiedNotification();
        LOG("========================================");
        LOG("  v3.0 ready: popups blocked, ball up");
        LOG("========================================");
    });
}
