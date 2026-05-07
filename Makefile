TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = HelloBike

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HelloTimeCalc
# 在你的 Tweak 名称下面添加库链接
HelloTimeCalc_FRAMEWORKS = UIKit AVFoundation Foundation

HelloTimeCalc_FILES = Tweak.x
HelloTimeCalc_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk