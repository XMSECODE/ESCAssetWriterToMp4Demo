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
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:h264FilePath];
    NSData *allData = [fileHandle readDataToEndOfFile];
    
    [h264MP4 pushH264DataContentSpsAndPpsData:allData];

    [h264MP4 endWritingCompletionHandler:nil];
}

+ (void)ESCH265FileToMp4FileToolWithh264FilePath:(NSString *)h265FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate {
    
    ESCH264OrH265StreamToMp4FileTool *h265MP4 = [[ESCH264OrH265StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:h265FilePath];
    NSData *allData = [fileHandle readDataToEndOfFile];
    
    [h265MP4 pushH265DataContentSpsAndPpsData:allData];
    
    [h265MP4 endWritingCompletionHandler:nil];
}

@end
