//
//  ViewController.m
//  H264ToMP4
//
//  Created by 包红来 on 2017/6/20.
//  Copyright © 2017年 包红来. All rights reserved.
//

#import "ViewController.h"
#import "ESCH264FileToMp4FileTool.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.view.backgroundColor = [UIColor whiteColor];
    UIButton *startBt = [[UIButton alloc] initWithFrame:CGRectMake(20, 80, 100, 40)];
    [startBt setTitle:@"开始写入1" forState:UIControlStateNormal];
    [startBt addTarget:self action:@selector(startWrite) forControlEvents:UIControlEventTouchUpInside];
    [startBt setBackgroundColor:[UIColor blueColor]];
    [self.view addSubview:startBt];
}

- (void) startWrite {
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"h264toMp41.mp4"];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"video3" ofType:@"h264"];
    NSLog(@"%@",filePath);
    [ESCH264FileToMp4FileTool ESCH264FileToMp4FileToolWithh264FilePath:path mp4FilePath:filePath videoWidth:1280 videoHeight:720];
}

@end
