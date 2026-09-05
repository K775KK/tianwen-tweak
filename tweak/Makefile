THEOS ?= ~/theos
export THEOS

INSTALL_TARGET_PROCESSES = Aweme
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TianwenTweak

TianwenTweak_FILES = tweak.x
TianwenTweak_CFLAGS = -fobjc-arc
TianwenTweak_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
