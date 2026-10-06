export ARCHS = armv7 arm64
export TARGET = iphone:clang:10.3:7.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Lumen
Lumen_FILES = Tweak.xm LMNWallpaperView.m
Lumen_FRAMEWORKS = UIKit QuartzCore AVFoundation CoreMedia
Lumen_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += lumenprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
