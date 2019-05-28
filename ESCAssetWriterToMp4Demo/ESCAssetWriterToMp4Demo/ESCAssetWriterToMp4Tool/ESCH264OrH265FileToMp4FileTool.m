//
//  ESCH264FileToMp4FileTool.m
//  ESCH264ToMp4Demo
//
//  Created by xiang on 2018/6/26.
//  Copyright © 2018年 xiang. All rights reserved.
//

#import "ESCH264OrH265FileToMp4FileTool.h"

@implementation ESCH264OrH265FileToMp4FileTool

+ (void)ESCH264FileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate{
    
    ESCH264OrH265StreamToMp4FileTool *h264MP4 = [[ESCH264OrH265StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate];
    
    NSData *h264Data = [NSData dataWithContentsOfFile:h264FilePath];
    
    [h264MP4 pushH264DataContentSpsAndPpsData:h264Data];

    [h264MP4 endWritingCompletionHandler:nil];
}

+ (void)ESCH265FileToMp4FileToolWithh265FilePath:(NSString *)h265FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate {
    
    ESCH264OrH265StreamToMp4FileTool *h265MP4 = [[ESCH264OrH265StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate];
    
    NSData *h265Data = [NSData dataWithContentsOfFile:h265FilePath];
    
    [h265MP4 pushH265DataContentSpsAndPpsData:h265Data];
    
    [h265MP4 endWritingCompletionHandler:nil];
}

+ (void)ESCH264FileAndPCMFileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath
                                               pcmFilePath:(NSString *)pcmFilePath
                                               mp4FilePath:(NSString *)mp4FilePath
                                                videoWidth:(NSInteger)width
                                               videoHeight:(NSInteger)height
                                                 frameRate:(NSInteger)frameRate
                                           audioSampleRate:(int)audioSampleRate
                                             audioChannels:(int)audioChannels
                                            bitsPerChannel:(int)bitsPerChannel {
    ESCH264OrH265StreamToMp4FileTool *h264MP4 = [[ESCH264OrH265StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate audioSampleRate:audioSampleRate audioChannels:audioChannels bitsPerChannel:bitsPerChannel];
    NSData *h264Data = [NSData dataWithContentsOfFile:h264FilePath];
    NSData *pcmData = [NSData dataWithContentsOfFile:pcmFilePath];
    
    [h264MP4 pushH264DataContentSpsAndPpsData:h264Data];
    [h264MP4 pushPCMDataContent:pcmData];
    
    [h264MP4 endWritingCompletionHandler:nil];

}

+ (void)ESCH265FileAndPCMFileToMp4FileToolWithh265FilePath:(NSString *)h265FilePath
                                               pcmFilePath:(NSString *)pcmFilePath
                                               mp4FilePath:(NSString *)mp4FilePath
                                                videoWidth:(NSInteger)width
                                               videoHeight:(NSInteger)height
                                                 frameRate:(NSInteger)frameRate
                                           audioSampleRate:(int)audioSampleRate
                                             audioChannels:(int)audioChannels
                                            bitsPerChannel:(int)bitsPerChannel {
    
    ESCH264OrH265StreamToMp4FileTool *h265MP4 = [[ESCH264OrH265StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate audioSampleRate:audioSampleRate audioChannels:audioChannels bitsPerChannel:bitsPerChannel];
    
    NSData *h265Data = [NSData dataWithContentsOfFile:h265FilePath];
    NSData *pcmData = [NSData dataWithContentsOfFile:pcmFilePath];
    
    [h265MP4 pushH265DataContentSpsAndPpsData:h265Data];
    [h265MP4 pushPCMDataContent:pcmData];
    
    [h265MP4 endWritingCompletionHandler:nil];
}

@end
