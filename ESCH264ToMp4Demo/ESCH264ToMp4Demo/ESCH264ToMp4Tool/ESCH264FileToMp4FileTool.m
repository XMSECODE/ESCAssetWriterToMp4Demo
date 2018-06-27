//
//  ESCH264FileToMp4FileTool.m
//  ESCH264ToMp4Demo
//
//  Created by xiang on 2018/6/26.
//  Copyright © 2018年 xiang. All rights reserved.
//

#import "ESCH264FileToMp4FileTool.h"

@implementation ESCH264FileToMp4FileTool

+ (void)ESCH264FileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath mp4FilePath:(NSString *)mp4FilePath videoWidth:(NSInteger)width videoHeight:(NSInteger)height {
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"h264toMp42.mp4"];
    
    ESCH264StreamToMp4FileTool *h264MP4 = [[ESCH264StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:filePath];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:h264FilePath];
    NSData *allData = [fileHandle readDataToEndOfFile];
    uint8_t *videoData = (uint8_t*)[allData bytes];
    
    NaluUnit naluUnit;
    NSData *sps = nil;
    NSData *pps = nil;
    int frame_size = 0;
    BOOL spsAndppsWrite = NO;
    int cur_pos = 0;
    while([self ESCReadOneNaluFromAnnexBFormatH264WithNalu:&naluUnit buf:videoData buf_size:allData.length cur_pos:&cur_pos]) {
        if(naluUnit.type == NAL_SPS || naluUnit.type == NAL_PPS || naluUnit.type == NAL_SEI) {
            if (naluUnit.type == NAL_SPS) {
                sps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
            } else if(naluUnit.type == NAL_PPS) {
                pps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
            } else {
                continue;
            }
            if (sps && pps && spsAndppsWrite == NO) {
                [h264MP4 setupWithSPS:sps PPS:pps];
                spsAndppsWrite = YES;
            }
            continue;
        }
        //获取NALUS的长度，开辟内存
        frame_size += naluUnit.size;
        BOOL isIFrame = NO;
        if (naluUnit.type == NAL_SLICE_IDR) {
            isIFrame = YES;
        }
        frame_size = naluUnit.size + 4;
        uint8_t *frame_data = (uint8_t *) calloc(1, frame_size);//avcc header 占用4个字节
        uint32_t littleLength = CFSwapInt32HostToBig(naluUnit.size);
        uint8_t *lengthAddress = (uint8_t*)&littleLength;
        memcpy(frame_data, lengthAddress, 4);
        memcpy(frame_data+4, naluUnit.data, naluUnit.size);
        [h264MP4 pushH264Data:frame_data length:frame_size];
        free(frame_data);
    }
    
    [h264MP4 endWritingCompletionHandler:nil];
}

/**
 *  从data流中读取1个NALU
 *
 *  @param nalu     NaluUnit
 *  @param buf      data流指针
 *  @param buf_size data流长度
 *  @param cur_pos  当前位置
 *
 *  @return 成功 or 失败
 */
+ (BOOL)ESCReadOneNaluFromAnnexBFormatH264WithNalu:(NaluUnit *)nalu buf:(unsigned char *)buf buf_size:(NSInteger)buf_size cur_pos:(int *)cur_pos {
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
