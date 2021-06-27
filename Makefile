ARCHS = armv7s arm64 arm64e
GO_EASY_ON_ME = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeatherDate
WeatherDate_FILES = Tweak.xm
WeatherDate_FRAMEWORKS = IOKit CoreLocation
WeatherDate_PRIVATE_FRAMEWORKS = SpringBoardFoundation SpringBoardUIServices Weather WeatherFoundation UserNotificationsUIKit
WeatherDate_CFLAGS = -fvisibility=hidden

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

SUBPROJECTS += weatherdateprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
