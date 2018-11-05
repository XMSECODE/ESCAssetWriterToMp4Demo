//
//  ESCH264View.h
//  ESCH264ToMp4Demo
//
//  Created by xiang on 2018/7/3.
//  Copyright © 2018年 xiang. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface ESCH264View : UIView

@property(nonatomic,assign) CGSize videoSize;

- (void)showSampBuff:(CMSampleBufferRef)sampleBuffer;

- (void)pushH264DataContentSpsAndPpsData:(NSData *)h264Data;

@end
