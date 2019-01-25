//
//  ViewController.m
//  H264ToMP4
//
//  Created by 包红来 on 2017/6/20.
//  Copyright © 2017年 包红来. All rights reserved.
//

#import "ViewController.h"
#import "ESCH264OrH265FileToMp4FileTool.h"
#import "ESCH264View.h"

@interface ViewController ()

@property(nonatomic,weak)ESCH264View* h264View;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    UIButton *startWrite264Button = [[UIButton alloc] initWithFrame:CGRectMake(20, 20, 150, 100)];
    [startWrite264Button setTitle:@"开始写入h264" forState:UIControlStateNormal];
    [startWrite264Button addTarget:self action:@selector(startWriteH264) forControlEvents:UIControlEventTouchUpInside];
    [startWrite264Button setBackgroundColor:[UIColor blueColor]];
    [self.view addSubview:startWrite264Button];
    
    UIButton *startWriteH265Button = [[UIButton alloc] initWithFrame:CGRectMake(20, 150, 150, 100)];
    [startWriteH265Button setTitle:@"开始写入h265" forState:UIControlStateNormal];
    [startWriteH265Button addTarget:self action:@selector(startWriteH265) forControlEvents:UIControlEventTouchUpInside];
    [startWriteH265Button setBackgroundColor:[UIColor blueColor]];
    [self.view addSubview:startWriteH265Button];
    
    ESCH264View *h264View = [[ESCH264View alloc] init];
    h264View.frame = CGRectMake(20, 250, 300, 300);
    h264View.videoSize = CGSizeMake(1280, 720);
    [self.view addSubview:h264View];
    self.h264View = h264View;
    
}

- (void)startWriteH265 {
    NSString *h265Path = [[NSBundle mainBundle] pathForResource:@"test_1_640_360.h265" ofType:nil];
    NSString *aacFilePath = [[NSBundle mainBundle] pathForResource:@"8000_1_16.aac" ofType:nil];
    
    NSString *h265Mp4FilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"h265toMp4.mp4"];
    
    [ESCH264OrH265FileToMp4FileTool ESCH265FileAndAACFileToMp4FileToolWithh264FilePath:h265Path aacFilePath:aacFilePath mp4FilePath:h265Mp4FilePath videoWidth:640 videoHeight:360 frameRate:25 audioSampleRate:8000 audioChannels:1 bitsPerChannel:16];
}

- (void)startWriteH264 {
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"h264toMp4.mp4"];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"video3" ofType:@"h264"];
    NSLog(@"%@",filePath);
    [ESCH264OrH265FileToMp4FileTool ESCH264FileToMp4FileToolWithh264FilePath:path mp4FilePath:filePath videoWidth:1280 videoHeight:720 frameRate:25];
    
//    [self ESCH264FileShowWithh264FilePath:path];
}


- (void)ESCH264FileShowWithh264FilePath:(NSString *)h264FilePath {
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:h264FilePath];
    NSData *allData = [fileHandle readDataToEndOfFile];
    uint8_t *videoData = (uint8_t*)[allData bytes];
    
    NaluUnit naluUnit;
    int cur_pos = 0;
    while([self ESCReadOneNaluFromAnnexBFormatH264WithNalu:&naluUnit buf:videoData buf_size:allData.length cur_pos:&cur_pos]) {
        NSData *data = [NSData dataWithBytes:naluUnit.data - 3 length:naluUnit.size + 3];
        [self.h264View pushH264DataContentSpsAndPpsData:data];
        [NSThread sleepForTimeInterval:0.04];
    }
}

- (BOOL)ESCReadOneNaluFromAnnexBFormatH264WithNalu:(NaluUnit *)nalu buf:(unsigned char *)buf buf_size:(NSInteger)buf_size cur_pos:(int *)cur_pos {
    int i = *cur_pos;
    while(i + 2 < buf_size)
    {
        if(buf[i] == 0x00 && buf[i+1] == 0x00 && buf[i+2] == 0x01) {
            i = i + 3;
            int pos = i;
            while (pos + 2 < buf_size)
            {
                if(buf[pos] == 0x00 && buf[pos+1] == 0x00 && buf[pos+2] == 0x01)
                    break;
                pos++;
            }
            if(pos+2 == buf_size) {
                (*nalu).size = pos+2-i;
            } else {
                while(buf[pos-1] == 0x00)
                    pos--;
                (*nalu).size = pos-i;
            }
            (*nalu).type = buf[i] & 0x1f;
            (*nalu).data = buf + i;
            *cur_pos = pos;
            return true;
        } else {
            i++;
        }
    }
    return false;
}

@end
