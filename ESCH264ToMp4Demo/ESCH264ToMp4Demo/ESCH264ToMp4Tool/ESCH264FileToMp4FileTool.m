//
//  ESCH264FileToMp4FileTool.m
//  ESCH264ToMp4Demo
//
//  Created by xiang on 2018/6/26.
//  Copyright © 2018年 xiang. All rights reserved.
//

#import "ESCH264FileToMp4FileTool.h"

@implementation ESCH264FileToMp4FileTool

+ (void)ESCH264FileToMp4FileToolWithh264FilePath:(NSString *)h264FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate{
    
    ESCH264StreamToMp4FileTool *h264MP4 = [[ESCH264StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:h264FilePath];
    NSData *allData = [fileHandle readDataToEndOfFile];
    uint8_t *videoData = (uint8_t*)[allData bytes];
    
    NaluUnit naluUnit;
    int cur_pos = 0;
    while([self ESCReadOneNaluFromAnnexBFormatH264WithNalu:&naluUnit buf:videoData buf_size:allData.length cur_pos:&cur_pos]) {
        NSData *data = [NSData dataWithBytes:naluUnit.data - 3 length:naluUnit.size + 3];
        [h264MP4 pushH264DataContentSpsAndPpsData:data];
    }
    [h264MP4 endWritingCompletionHandler:nil];
}

+ (void)ESCH265FileToMp4FileToolWithh264FilePath:(NSString *)h265FilePath
                                     mp4FilePath:(NSString *)mp4FilePath
                                      videoWidth:(NSInteger)width
                                     videoHeight:(NSInteger)height
                                       frameRate:(NSInteger)frameRate {
    
    ESCH264StreamToMp4FileTool *h264MP4 = [[ESCH264StreamToMp4FileTool alloc] initWithVideoSize:CGSizeMake(width, height) filePath:mp4FilePath frameRate:frameRate];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:h265FilePath];
    NSData *allData = [fileHandle readDataToEndOfFile];
    uint8_t *videoData = (uint8_t*)[allData bytes];
    
    NaluUnit naluUnit;
    int cur_pos = 0;
    [h264MP4 pushH265DataContentSpsAndPpsData:allData];

//    while([self ESCReadOneNaluFromAnnexBFormatH265WithNalu:&naluUnit buf:videoData buf_size:allData.length cur_pos:&cur_pos]) {
//        NSData *data = [NSData dataWithBytes:naluUnit.data - 4 length:naluUnit.size + 4];
//        NSLog(@"%d",data.length);
//    }
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
+ (BOOL)ESCReadOneNaluFromAnnexBFormatH265WithNalu:(NaluUnit *)nalu
                                               buf:(unsigned char *)buf
                                          buf_size:(NSInteger)buf_size
                                           cur_pos:(int *)cur_pos {
    int i = *cur_pos;
    while(i + 3 < buf_size) {
        //读起始位置
        if(buf[i] == 0x00 && buf[i+1] == 0x00 && buf[i+2] == 0x00 && buf[i+3] == 0x01) {
            i = i + 4;
            int pos = i;
            //读截止位置
            while (pos + 3 < buf_size) {
                if(buf[pos] == 0x00 && buf[pos+1] == 0x00 && buf[pos+2] == 0x00 && buf[pos+3] == 0x01) {
                    break;
                }
                pos++;
            }
            if(pos+4 == buf_size) {
                (*nalu).size = pos + 3 - i;
            } else {
                while(buf[pos-1] == 0x00)
                    pos--;
                (*nalu).size = pos-i;
            }
            
            int type = (buf[i] & 0x7E)>>1;
            (*nalu).type = type;
            (*nalu).data = buf + i;
            *cur_pos = pos;
            return true;
        } else {
            i++;
        }
    }
    return false;
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
