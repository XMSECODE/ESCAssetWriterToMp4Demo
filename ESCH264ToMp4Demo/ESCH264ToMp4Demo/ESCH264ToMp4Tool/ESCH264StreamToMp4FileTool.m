//
//  H264ToMp4.m
//  MTLiveStreamingKit
//
//  Created by 包红来 on 2017/6/16.
//  Copyright © 2017年 LGW. All rights reserved.
//

#import "ESCH264StreamToMp4FileTool.h"
#include <mach/mach_time.h>

#define AV_W8(p, v) *(p) = (v)

#ifndef AV_WB16
#   define AV_WB16(p, darg) do {                \
unsigned d = (darg);                    \
((uint8_t*)(p))[1] = (d);               \
((uint8_t*)(p))[0] = (d)>>8;            \
} while(0)
#endif

@interface ESCH264StreamToMp4FileTool()

@property(nonatomic,assign)CMFormatDescriptionRef videoFormat;

@property(nonatomic,assign)CMTime startTime;

@property(nonatomic,assign)int frameIndex;

@property(nonatomic,strong)AVAssetWriterInput* videoWriteInput;

@property(nonatomic,strong)AVAssetWriter* assetWriter;

@property (nonatomic) CGFloat rotate;

@property (nonatomic) NSString *filePath;

@property(nonatomic,assign) CGSize videoSize;

@property(nonatomic,assign)NSInteger frameRate;

@property(nonatomic,strong)NSData* sps;

@property(nonatomic,strong)NSData* pps;

@property(nonatomic,assign)BOOL spsAndppsWrite;

@end
const int32_t TIME_SCALE = 1000000000l;    // 1s = 1e10^9 ns

@implementation ESCH264StreamToMp4FileTool

- (instancetype) initWithVideoSize:(CGSize) videoSize filePath:(NSString *)filePath frameRate:(NSInteger)frameRate{
    if (self = [super init]) {
        _videoSize = videoSize;
        self.filePath = [filePath copy];
        NSLog(@"H264ToMp4 setup start");
        unlink([self.filePath UTF8String]);//删除该文件,c语言用法
        [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:nil];
        NSError *error = nil;
        NSURL *outputUrl = [NSURL fileURLWithPath:self.filePath];
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputUrl fileType:AVFileTypeMPEG4 error:&error];
        self.frameRate = frameRate;
    }
    return self;
}

- (void) setupWithSPS:(NSData *)sps PPS:(NSData *)pps {
    if (self.videoWriteInput != nil) {
        return;
    }
    
    const CFStringRef avcCKey = CFSTR("avcC");
    const CFDataRef avcCValue = [self avccExtradataCreate:sps PPS:pps];
    const void *atomDictKeys[] = { avcCKey };
    const void *atomDictValues[] = { avcCValue };
    CFDictionaryRef atomsDict = CFDictionaryCreate(kCFAllocatorDefault, atomDictKeys, atomDictValues, 1, nil, nil);
    
    const void *extensionDictKeys[] = { kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms };
    const void *extensionDictValues[] = { atomsDict };
    CFDictionaryRef extensionDict = CFDictionaryCreate(kCFAllocatorDefault, extensionDictKeys, extensionDictValues, 1, nil, nil);
    
    CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_H264, self.videoSize.width, self.videoSize.height, extensionDict, &_videoFormat);
    _videoWriteInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:_videoFormat];
    
    if ([_assetWriter canAddInput:_videoWriteInput]) {
        [_assetWriter addInput:_videoWriteInput];
    }
    _videoWriteInput.expectsMediaDataInRealTime = YES;
    _startTime = CMTimeMake(0, TIME_SCALE);
    if ([_assetWriter startWriting]) {
        [_assetWriter startSessionAtSourceTime:_startTime];
        NSLog(@"H264ToMp4 setup success");
    } else {
        NSLog(@"[Error] startWritinge error:%@",_assetWriter.error);
    };
}

- (CFDataRef) avccExtradataCreate:(NSData *)sps PPS:(NSData *) pps {
    CFDataRef data = NULL;
    uint8_t *sps_data = (uint8_t*)[sps bytes];
    uint8_t *pps_data = (uint8_t*)[pps bytes];
    int sps_data_size = (int)sps.length;
    int pps_data_size = (int)pps.length;
    uint8_t *p;
    int extradata_size = 6 + 2 + sps_data_size + 3 + pps_data_size;
    uint8_t *extradata = calloc(1, extradata_size);
    if (!extradata){
        return NULL;
    }
    p = extradata;
    
    AV_W8(p + 0, 1); /* version */
    AV_W8(p + 1, sps_data[1]); /* profile */
    AV_W8(p + 2, sps_data[2]); /* profile compat */
    AV_W8(p + 3, sps_data[3]); /* level */
    AV_W8(p + 4, 0xff); /* 6 bits reserved (111111) + 2 bits nal size length - 1 (11) */
    AV_W8(p + 5, 0xe1); /* 3 bits reserved (111) + 5 bits number of sps (00001) */
    AV_WB16(p + 6, sps_data_size);
    memcpy(p + 8,sps_data, sps_data_size);
    p += 8 + sps_data_size;
    AV_W8(p + 0, 1); /* number of pps */
    AV_WB16(p + 1, pps_data_size);
    memcpy(p + 3, pps_data, pps_data_size);
    
    p += 3 + pps_data_size;
    assert(p - extradata == extradata_size);
    
    data = CFDataCreate(kCFAllocatorDefault, extradata, extradata_size);
    free(extradata);
    return data;
}

- (void)pushH264DataContentSpsAndPpsData:(NSData *)h264Data {
    uint8_t *videoData = (uint8_t*)[h264Data bytes];
    
    NaluUnit naluUnit;
    int frame_size = 0;
    int cur_pos = 0;
    while([ESCH264StreamToMp4FileTool ESCReadOneNaluFromAnnexBFormatH264WithNalu:&naluUnit buf:videoData buf_size:h264Data.length cur_pos:&cur_pos]) {
        if(naluUnit.type == NAL_SPS || naluUnit.type == NAL_PPS || naluUnit.type == NAL_SEI) {
            if (naluUnit.type == NAL_SPS) {
                self.sps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
            } else if(naluUnit.type == NAL_PPS) {
                self.pps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
            } else {
                continue;
            }
            if (self.sps && self.pps && self.spsAndppsWrite == NO) {
                [self setupWithSPS:self.sps PPS:self.pps];
                self.spsAndppsWrite = YES;
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
        
        [self pushH264Data:frame_data length:frame_size];
        
        free(frame_data);
    }
    
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

- (void)pushH264Data:(unsigned char *)dataBuffer length:(uint32_t)len{
    if (_assetWriter.status == AVAssetWriterStatusUnknown) {
        NSLog(@"_assetWriter status not ready");
        return;
    }
    NSData *h264Data = [NSData dataWithBytes:dataBuffer length:len];
    CMSampleBufferRef h264Sample = [self sampleBufferWithData:h264Data formatDescriptor:_videoFormat];
    if ([_videoWriteInput isReadyForMoreMediaData]) {
        [_videoWriteInput appendSampleBuffer:h264Sample];
        NSLog(@"appendSampleBuffer success");
    } else {
        NSLog(@"_videoWriteInput isReadyForMoreMediaData NO status:%ld",(long)_assetWriter.status);
    }
    CFRelease(h264Sample);
}

- (CMSampleBufferRef)sampleBufferWithData:(NSData*)data formatDescriptor:(CMFormatDescriptionRef)formatDescription {
    OSStatus result;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    size_t data_len = data.length;
    
    // _blockBuffer is a CMBlockBufferRef instance variable
   
    size_t blockLength = 100*1024;
    result = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                NULL,
                                                blockLength,
                                                kCFAllocatorDefault,
                                                NULL,
                                                0,
                                                data_len,
                                                kCMBlockBufferAssureMemoryNowFlag,
                                                &blockBuffer);
    if (result != noErr) {
        NSLog(@"create block buffer failed!");
        return NULL;
    }
    
    result = CMBlockBufferReplaceDataBytes([data bytes], blockBuffer, 0, [data length]);
    
    // check error
    if (result != noErr) {
        NSLog(@"replace block buffer failed!");
        return NULL;
    }
    const size_t sampleSizes[] = {[data length]};
    CMTime pts = [self timeWithFrame:_frameIndex];
    
    CMSampleTimingInfo timeInfoArray[1] = { {
        .duration = CMTimeMake(0, 0),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = CMTimeMake(0, 0),
    } };
    
    result = CMSampleBufferCreate(kCFAllocatorDefault,//
                                  blockBuffer,//dataBuffer
                                  YES,//dataReady
                                  NULL,//makeDataReadyCallback
                                  NULL,//makeDataReadyRefcon
                                  formatDescription,
                                  1,//numSamples
                                  1,//numSampleTimingEntries
                                  timeInfoArray,//
                                  1,
                                  sampleSizes,//sampleSizeArray
                                  &sampleBuffer);
    if (result != noErr) {
        NSLog(@"CMSampleBufferCreate result:%d",result);
        return NULL;
    }
    _frameIndex ++;

    // check error
    
    return sampleBuffer;
}

- (void) endWritingCompletionHandler:(void (^)(void))handler {
     CMTime time = [self timeWithFrame:_frameIndex];
    [_videoWriteInput markAsFinished];
    [_assetWriter endSessionAtSourceTime:time];
    [_assetWriter finishWritingWithCompletionHandler:^{
        NSLog(@"finishWriting");
        if (handler) {
            handler();
        }
    }];
}


- (CMTime) timeWithFrame:(int) frameIndex{
    int64_t pts = (frameIndex * (1000.0 / self.frameRate)) *(TIME_SCALE/1000);
    NSLog(@"pts:%lld",pts);
    return CMTimeMake(pts, TIME_SCALE);
}


@end
