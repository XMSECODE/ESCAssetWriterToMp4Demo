//
//  ESCH264FileToMp4FileTool.h
//  ESCH264ToMp4Demo
//
//  Created by xiang on 2018/6/26.
//  Copyright © 2018年 xiang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ESCH264StreamToMp4FileTool.h"

@interface ESCH264FileToMp4FileTool : NSObject

+ (void)ESCH264FileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath mp4FilePath:(NSString *)mp4FilePath videoWidth:(NSInteger)width videoHeight:(NSInteger)height frameRate:(NSInteger)frameRate;

@end
