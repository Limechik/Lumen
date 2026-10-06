include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LumenPrefs
LumenPrefs_FILES = LMNRootListController.m
LumenPrefs_INSTALL_PATH = /Library/PreferenceBundles
LumenPrefs_FRAMEWORKS = UIKit
# в iPhoneOS10.3.sdk нет PrivateFrameworks/Preferences - резолвим символы в рантайме (Настройки сами грузят Preferences.framework)
LumenPrefs_LDFLAGS = -undefined dynamic_lookup
LumenPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/LumenPrefs.plist$(ECHO_END)
