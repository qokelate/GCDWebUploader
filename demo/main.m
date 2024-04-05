//
//  main.m
//  demo
//
//  Created by sma11case on 2024/4/5.
//

#import <UIKit/UIKit.h>

//#import "../GCDWebUploader/GCDWebServer/Core/GCDWebServer.m"
//#import "../GCDWebUploader/GCDWebServer/Core/GCDWebServerConnection.m"
//#import "../GCDWebUploader/GCDWebServer/Core/GCDWebServerFunctions.m"
//#import "../GCDWebUploader/GCDWebServer/Core/GCDWebServerRequest.m"
//#import "../GCDWebUploader/GCDWebServer/Core/GCDWebServerResponse.m"
//#import "../GCDWebUploader/GCDWebServer/Requests/GCDWebServerDataRequest.m"
//#import "../GCDWebUploader/GCDWebServer/Requests/GCDWebServerFileRequest.m"
//#import "../GCDWebUploader/GCDWebServer/Requests/GCDWebServerMultiPartFormRequest.m"
//#import "../GCDWebUploader/GCDWebServer/Requests/GCDWebServerURLEncodedFormRequest.m"
//#import "../GCDWebUploader/GCDWebServer/Responses/GCDWebServerDataResponse.m"
//#import "../GCDWebUploader/GCDWebServer/Responses/GCDWebServerErrorResponse.m"
//#import "../GCDWebUploader/GCDWebServer/Responses/GCDWebServerFileResponse.m"
//#import "../GCDWebUploader/GCDWebServer/Responses/GCDWebServerStreamedResponse.m"
//#import "../GCDWebUploader/GCDWebUploader/GCDWebUploader.m"
//#import "../GCDWebUploader/GCDWebUploader/GCDWebUploader_bundle.m"
//#import "../GCDWebUploader/WebServer.m"

#import "AppDelegate.h"
#import "../GCDWebUploader/WebServer.h"

int main(int argc, char * argv[]) {
    
    @autoreleasepool {
        
        [[WebServer sharedInstance] startUploader];
        
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}

