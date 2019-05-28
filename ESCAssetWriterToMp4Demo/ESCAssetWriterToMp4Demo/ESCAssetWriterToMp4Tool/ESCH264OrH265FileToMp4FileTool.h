//
//  ESCH264FileToMp4FileTool.h
//  ESCH264ToMp4Demo
//
//  Created by xiang on 2018/6/26.
//  Copyright © 2018年 xiang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ESCH264OrH265StreamToMp4FileTool.h"

@interface ESCH264OrH265FileToMp4FileTool : NSObject

+ (void)ESCH264FileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate;

+ (void)ESCH265FileToMp4FileToolWithh265FilePath:(NSString *)h265FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate;

+ (void)ESCH264FileAndPCMFileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath
                                               pcmFilePath:(NSString *)pcmFilePath
                                               mp4FilePath:(NSString *)mp4FilePath
                                                videoWidth:(NSInteger)width
                                               videoHeight:(NSInteger)height
                                                 frameRate:(NSInteger)frameRate
                                           audioSampleRate:(int)audioSampleRate
                                             audioChannels:(int)audioChannels
                                            bitsPerChannel:(int)bitsPerChannel;

+ (void)ESCH265FileAndPCMFileToMp4FileToolWithh265FilePath:(NSString *)h265FilePath
                                               pcmFilePath:(NSString *)pcmFilePath
                                               mp4FilePath:(NSString *)mp4FilePath
                                                videoWidth:(NSInteger)width
                                               videoHeight:(NSInteger)height
                                                 frameRate:(NSInteger)frameRate
                                           audioSampleRate:(int)audioSampleRate
                                             audioChannels:(int)audioChannels
                                            bitsPerChannel:(int)bitsPerChannel;

@end
