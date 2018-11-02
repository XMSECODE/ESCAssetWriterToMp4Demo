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

@property(nonatomic,strong)AVAssetWriterInput* audioWriteInput;

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
    NSLog(@"%@==%@==%@",data,sps,pps);
    free(extradata);
    return data;
}

- (CFDataRef) hevcExtradataCreate:(NSData *)sps PPS:(NSData *) pps VPS:(NSData *)vps {
    NSArray *extradataArray = @[vps,sps,pps];
    int totalLength = 23 + 15 + (int)sps.length + (int)pps.length + (int)vps.length;
    
    CFDataRef data = NULL;
    int sps_data_size = (int)sps.length;
    int pps_data_size = (int)pps.length;
    uint8_t *p;
    int extradata_size = 6 + 2 + sps_data_size + 3 + pps_data_size;
    uint8_t *extradata = calloc(1, totalLength);
    if (!extradata){
        return NULL;
    }
    p = extradata;
    
    //2
    uint8_t general_profile_space = 1;
    //1
    uint8_t general_tier_flag = 1;
    //5
    uint8_t general_profile_idc = 1;
    //32
    uint general_profile_compatibility_flags = 1;
    //48
    uint8_t general_constraint_indicator_flags[6] = {};
    //8
    uint8_t general_level_idc = 1;
    //12
    uint min_spatial_segmentation_idc = 1;
    //2
    uint8_t parallelismType = 1;
    //2
    uint8_t chromaFormat = 1;
    //3
    uint8_t bitDepathLumaMinus8 = 1;
    //3
    uint8_t bitDepthChromaMinus8 = 1;
    //16
    uint avgFrameRate = 1;
    //2
    uint8_t constantFrameRate = 1;
    //3
    uint8_t numTemporalLayers = 1;
    //1
    uint8_t temporalIdNested = 1;
    //2
    uint8_t lengthSizeMinusOne = 1;
    //8
    uint8_t numOfArrays = 1;
    //1
    uint8_t arry_completeness = 0;
    
    //bits          type
    //8             configurationVersion always 0x01
    p[0] = 1;
    //2              general_profile_space
    p[1] = general_profile_space & 0xc0;
    //1                general_tier_flag
    general_tier_flag = general_tier_flag << 5;
    p[1] = p[1] | general_tier_flag;
    //5              general_profile_idc
    p[1] = p[1] | general_profile_idc;
    //32            general_profile_compatibility_flags
    memcpy(p[2], (void *)&general_profile_compatibility_flags, 4);
    //48            general_constraint_indicator_flags
    memcpy(p[6], (void *)&general_constraint_indicator_flags, 6);
    //8             general_level_idc
    p[12] = general_level_idc;
    //4             reserved('1111')
    p[13] = 0xf0;
    //12            min_spatial_segmentation_idc
    uint8_t min_spatial_segmentation_idc_4 = min_spatial_segmentation_idc & 0x00ff0000;
    uint8_t min_spatial_segmentation_idc_8 = min_spatial_segmentation_idc & 0x0000ffff;
    p[13] = p[13] | min_spatial_segmentation_idc_4;
    p[14] = min_spatial_segmentation_idc_8;
    //6             reserved('111111')
    p[15] = 0xfc;
    //2             parallelismType
    parallelismType = parallelismType & 0x03;
    p[15] = p[15] | parallelismType;
    //6             reserved('111111')
    p[16] = 0xfc;
    //2   chromaFormat
    chromaFormat = chromaFormat & 0x03;
    p[16] = p[16] | chromaFormat;
    //5             reserved('11111')
    p[17] = 0xf8;
    //3            bitDepathLumaMinus8
    bitDepathLumaMinus8 = bitDepathLumaMinus8 & 0x07;
    p[17] = p[17] | bitDepathLumaMinus8;
    //5             reserved('11111')
    p[18] = 0xf8;
    //3            bitDepthChromaMinus8
    bitDepthChromaMinus8 = bitDepthChromaMinus8 & 0x07;
    p[18] = p[18] | bitDepthChromaMinus8;
    //16            avgFrameRate
    uint8_t avgFrameRate_1_byte = avgFrameRate & 0x0000ff00;
    uint8_t avgFrameRate_2_byte = avgFrameRate & 0x000000ff;
    p[19] = avgFrameRate_1_byte;
    p[20] = avgFrameRate_2_byte;
    //2             constantFrameRate
    constantFrameRate = constantFrameRate & 0xc0;
    p[21] = constantFrameRate;
    //3             numTemporalLayers
    numTemporalLayers = numTemporalLayers & 0x38;
    p[21] = p[21] | numTemporalLayers;
    //1            temporalIdNested
    temporalIdNested = temporalIdNested & 0x04;
    p[21] = p[21] | temporalIdNested;
    //2            lengthSizeMinusOne
    lengthSizeMinusOne = lengthSizeMinusOne & 0x03;
    p[21] = p[21] | lengthSizeMinusOne;
    //8             numOfArrays
    p[22] = numOfArrays;
    //              -- repeated of Array(VPS/SPS/PPS)   --
    int j = 0;
    for (int i = 0; i < numOfArrays;) {
        //1             arry_completeness
        arry_completeness = arry_completeness & 0x80;
        p[22 + i] = arry_completeness;
        //1            reserved(0)
        //6             NAL_unit_type
        if (j == 0) {
            //vps
            p[22 + i] = p[22 + i] | 0x20;
        }else if (j == 1) {
            p[22 + i] = p[22 + i] | 0x21;
        }else if (j == 2) {
            p[22 + i] = p[22 + i] | 0x22;
        }
        //16            numNalus
        p[22 + i + 1] = 0x00;
        p[22 + i + 2] = 0x01;
        //              --repeated once per NAL --
        NSData *naluData = extradataArray[j];
        //16            nalUnitLength
        int naluLength = (int)naluData.length;
        uint8_t naluLength_one = naluLength & 0x0000ff00;
        uint8_t naluLength_two = naluLength & 0x000000ff;
        p[22 + i + 3] = naluLength_one;
        p[22 + i + 4] = naluLength_two;
        //N             NALU data
        const void *pNaluData = [naluData bytes];
        memcpy(p[22 + i + 5], pNaluData, naluLength);
        j++;
        i += 1 + 2 + 2 + naluLength;
    }
 
    data = CFDataCreate(kCFAllocatorDefault, extradata, extradata_size);
    NSLog(@"%@==%@==%@",data,sps,pps);
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
