SYSROOT = $(THEOS)/sdks/iPhoneOS11.2.sdk
ARCHS = armv7s arm64 arm64e
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = weatherdateprefs
weatherdateprefs_FILES = WLPRootListController.m
weatherdateprefs_INSTALL_PATH = /Library/PreferenceBundles
weatherdateprefs_FRAMEWORKS = UIKit
weatherdateprefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/weatherdateprefs.plist$(ECHO_END)
