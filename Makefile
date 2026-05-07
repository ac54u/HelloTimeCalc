TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = HelloBike

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HelloTimeCalc

HelloTimeCalc_FILES = Tweak.x
HelloTimeCalc_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk