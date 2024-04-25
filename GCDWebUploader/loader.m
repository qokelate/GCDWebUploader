//
//  WebServer.m
//  MAME4iOS
//
//  Created by Yoshi Sugawara on 1/15/19.
//  Copyright © 2019 Seleuco. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "WebServer.h"

static __attribute__((constructor)) void loader(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WebServer sharedInstance] startUploader];
    });
}
