THEOS_PACKAGE_SCHEME=rootless
# PACKAGE_BUILDNAME := rootless

TARGET = ::9.0
ARCHS = arm64 arm64e
TARGET_CC = xcrun -sdk iphoneos clang -stdlib=libc++
TARGET_CXX = xcrun -sdk iphoneos clang++ -stdlib=libc++
TARGET_LD = xcrun -sdk iphoneos clang++
ADDITIONAL_OBJCFLAGS = -fobjc-arc -Wno-error
# LDFLAGS=-lz

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GCDWebServer

$(TWEAK_NAME)_FILES = \
../GCDWebUploader/loader.m \
../GCDWebUploader/WebServer.m \
../GCDWebUploader/GCDWebServer/Core/GCDWebServerResponse.m \
../GCDWebUploader/GCDWebServer/Core/GCDWebServerRequest.m \
../GCDWebUploader/GCDWebServer/Core/GCDWebServerFunctions.m \
../GCDWebUploader/GCDWebServer/Core/GCDWebServer.m \
../GCDWebUploader/GCDWebServer/Core/GCDWebServerConnection.m \
../GCDWebUploader/GCDWebServer/Responses/GCDWebServerErrorResponse.m \
../GCDWebUploader/GCDWebServer/Responses/GCDWebServerFileResponse.m \
../GCDWebUploader/GCDWebServer/Responses/GCDWebServerDataResponse.m \
../GCDWebUploader/GCDWebServer/Responses/GCDWebServerStreamedResponse.m \
../GCDWebUploader/GCDWebServer/Requests/GCDWebServerURLEncodedFormRequest.m \
../GCDWebUploader/GCDWebServer/Requests/GCDWebServerMultiPartFormRequest.m \
../GCDWebUploader/GCDWebServer/Requests/GCDWebServerDataRequest.m \
../GCDWebUploader/GCDWebServer/Requests/GCDWebServerFileRequest.m \
../GCDWebUploader/GCDWebUploader/GCDWebUploader_bundle.m \
../GCDWebUploader/GCDWebUploader/GCDWebUploader.m

$(TWEAK_NAME)_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
