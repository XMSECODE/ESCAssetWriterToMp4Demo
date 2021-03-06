//
//  H264ToMp4.m
//  MTLiveStreamingKit
//
//  Created by 包红来 on 2017/6/16.
//  Copyright © 2017年 LGW. All rights reserved.
//
/**<
 等待isReadyForMoreMediaData为yes
 关于isReadyForMoreMediaData的介绍首先看头文件
 isReadyForMoreMediaData：写入的时候有个buffer，
 如果音频或者视频WriteInput的buffer写入一段时间的数据后满了，而另外一个没有满，isReadyForMoreMediaData就会等于NO，
 等待另外一个写入相同的时间的数据，如果另外一个WriteInput（markAsFinished）关闭了就不用考虑等待。
 直到两个频道都写入一段相同的时间后buffer就会清零，可以重新写入isReadyForMoreMediaData就会等于YES
 
 音视频的WriteInput开两条线程，使用dispatch_group_notify来处理写入完毕。
 >*/

#ifdef DEBUG
#   define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

#import "ESCH264OrH265StreamToMp4FileTool.h"
#include <mach/mach_time.h>

#define AV_W8(p, v) *(p) = (v)

#ifndef AV_WB16
#   define AV_WB16(p, darg) do {                \
unsigned d = (darg);                    \
((uint8_t*)(p))[1] = (d);               \
((uint8_t*)(p))[0] = (d)>>8;            \
} while(0)
#endif



@interface ESCH264OrH265StreamToMp4FileTool()

@property(nonatomic,assign)CMFormatDescriptionRef videoFormat;

@property(nonatomic,assign)CMFormatDescriptionRef audioFormat;

@property(nonatomic,assign)CMTime startTime;

@property(nonatomic,assign)int videoFrameIndex;

@property(nonatomic,assign)int audioFrameIndex;

@property(nonatomic,strong)AVAssetWriterInput* videoWriteInput;

@property(nonatomic,strong)AVAssetWriterInput* audioWriteInput;

@property(nonatomic,strong)AVAssetWriter* assetWriter;

@property (nonatomic) CGFloat rotate;

@property (nonatomic) NSString *filePath;

@property(nonatomic,assign) CGSize videoSize;

@property(nonatomic,assign)NSInteger frameRate;

@property(nonatomic,strong)NSData* sps;

@property(nonatomic,strong)NSData* pps;

@property(nonatomic,strong)NSData* vps;

@property(nonatomic,strong)NSData* sei;

@property(nonatomic,assign)BOOL getOtherDataSuccess;    //sps pps vps sei

@property(nonatomic,assign)int audioSampleRate;

@property(nonatomic,assign)int audioChannels;

@property(nonatomic,assign)int bitsPerChannel;

@property(nonatomic,strong)NSMutableArray<NSData *>* videoDataArray;

@property(nonatomic,strong)NSMutableArray<NSData *>* audioDataArray;

@property(nonatomic,strong)dispatch_queue_t recordQueue;

@property(nonatomic,assign)BOOL videoStarted;

@property(nonatomic,assign)BOOL audioStarted;

@property(nonatomic,assign)BOOL pushDataIsEnd;

@property(nonatomic,copy)void(^endRecordBlock)(void);

@property(nonatomic,strong)NSMutableData* temPCMData;

@property(nonatomic,assign)BOOL firstBuffer;

@end
const int32_t TIME_SCALE = 1000000000l;    // 1s = 1e10^9 ns

@implementation ESCH264OrH265StreamToMp4FileTool

- (instancetype) initWithVideoSize:(CGSize) videoSize filePath:(NSString *)filePath frameRate:(NSInteger)frameRate{
    if (self = [super init]) {
        _videoSize = videoSize;
        self.filePath = [filePath copy];
        DLog(@"H264ToMp4 setup start");
        unlink([self.filePath UTF8String]);//删除该文件,c语言用法
        [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:nil];
        NSError *error = nil;
        NSURL *outputUrl = [NSURL fileURLWithPath:self.filePath];
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputUrl fileType:AVFileTypeMPEG4 error:&error];
        self.frameRate = frameRate;
        
        self.videoDataArray = [NSMutableArray array];
        self.audioDataArray = [NSMutableArray array];
        self.recordQueue = dispatch_queue_create("record queue", NULL);
    }
    return self;
}

- (instancetype)initWithVideoSize:(CGSize) videoSize
                         filePath:(NSString *)filePath
                        frameRate:(NSInteger)frameRate
                  audioSampleRate:(int)audioSampleRate
                    audioChannels:(int)audioChannels
                   bitsPerChannel:(int)bitsPerChannel {
    if (self = [super init]) {
        _videoSize = videoSize;
        self.filePath = [filePath copy];
        DLog(@"H264ToMp4 setup start");
        unlink([self.filePath UTF8String]);//删除该文件,c语言用法
        [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:nil];
        NSError *error = nil;
        NSURL *outputUrl = [NSURL fileURLWithPath:self.filePath];
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputUrl fileType:AVFileTypeMPEG4 error:&error];
        self.frameRate = frameRate;
        self.audioChannels = audioChannels;
        self.audioSampleRate = audioSampleRate;
        self.bitsPerChannel = bitsPerChannel;
        
        self.videoDataArray = [NSMutableArray array];
        self.audioDataArray = [NSMutableArray array];
        self.recordQueue = dispatch_queue_create("record queue", NULL);
        [self setupAudioWriteInput];
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
    //    CMVideoFormatDescriptionCreate(<#CFAllocatorRef  _Nullable allocator#>, <#CMVideoCodecType codecType#>, <#int32_t width#>, <#int32_t height#>, <#CFDictionaryRef  _Nullable extensions#>, <#CMVideoFormatDescriptionRef  _Nullable * _Nonnull formatDescriptionOut#>)
    //    CMVideoFormatDescriptionCreateFromH264ParameterSets(<#CFAllocatorRef  _Nullable allocator#>, <#size_t parameterSetCount#>, <#const uint8_t *const  _Nonnull * _Nonnull parameterSetPointers#>, <#const size_t * _Nonnull parameterSetSizes#>, <#int NALUnitHeaderLength#>, <#CMFormatDescriptionRef  _Nullable * _Nonnull formatDescriptionOut#>)
    CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_H264, self.videoSize.width, self.videoSize.height, extensionDict, &_videoFormat);
    _videoWriteInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:_videoFormat];
    
    if ([_assetWriter canAddInput:_videoWriteInput]) {
        [_assetWriter addInput:_videoWriteInput];
        DLog(@"format === %@",self.videoFormat);
    }

//    //非实时源（例如AVAssetReader的实例）
//    self.audioWriteInput.expectsMediaDataInRealTime = NO;
    
    _startTime = CMTimeMake(0, TIME_SCALE);
    if ([_assetWriter startWriting]) {
        [_assetWriter startSessionAtSourceTime:_startTime];
        DLog(@"H264ToMp4 setup success");
    } else {
        DLog(@"[Error] startWritinge error:%@",_assetWriter.error);
    };
}

- (void) setupH265WithSPS:(NSData *)sps PPS:(NSData *)pps vps:(NSData *)vps sei:(NSData *)sei{
    if (self.videoWriteInput != nil) {
        return;
    }
    
    const CFStringRef hevcKey = CFSTR("hevC");
    const CFDataRef hevcValue = [self hevcExtradataCreate:sps PPS:pps VPS:vps SEI:sei];
    const void *atomDictKeys[] = { hevcKey };
    const void *atomDictValues[] = { hevcValue };
    CFDictionaryRef atomsDict = CFDictionaryCreate(kCFAllocatorDefault, atomDictKeys, atomDictValues, 1, nil, nil);
    
    const void *extensionDictKeys[] = { kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms };
    const void *extensionDictValues[] = { atomsDict };
    CFDictionaryRef extensionDict = CFDictionaryCreate(kCFAllocatorDefault, extensionDictKeys, extensionDictValues, 1, nil, nil);
    
    CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_HEVC, self.videoSize.width, self.videoSize.height, extensionDict, &_videoFormat);
    _videoWriteInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:_videoFormat];
    
    if ([_assetWriter canAddInput:_videoWriteInput]) {
        [_assetWriter addInput:_videoWriteInput];
        DLog(@"format === %@",self.videoFormat);
    }
    
//    _videoWriteInput.expectsMediaDataInRealTime = YES;
    
    
    
//    _videoWriteInput.expectsMediaDataInRealTime = YES;
    
    _startTime = CMTimeMake(0, TIME_SCALE);
    if ([_assetWriter startWriting]) {
        [_assetWriter startSessionAtSourceTime:_startTime];
        DLog(@"H265ToMp4 setup success");
    } else {
        DLog(@"[Error] startWritinge error:%@",_assetWriter.error);
    };
}

- (void)setupAudioWriteInput {
    AudioStreamBasicDescription audioDescription;
    audioDescription.mSampleRate = self.audioSampleRate;
    audioDescription.mChannelsPerFrame = self.audioChannels;
    audioDescription.mBitsPerChannel = self.bitsPerChannel;
    audioDescription.mFormatID = kAudioFormatLinearPCM;
    audioDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioDescription.mFramesPerPacket = 1;
    audioDescription.mBytesPerFrame = audioDescription.mBitsPerChannel / 8 * audioDescription.mChannelsPerFrame;
    audioDescription.mBytesPerPacket = audioDescription.mBytesPerFrame * audioDescription.mFramesPerPacket;
    audioDescription.mReserved = 0;
    
    CMAudioFormatDescriptionRef cmAudioFormatDescriptionRef;
    CMAudioFormatDescriptionCreate(NULL, &audioDescription, 0, NULL, 0, NULL, NULL, &cmAudioFormatDescriptionRef);
//    self.audioWriteInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:NULL sourceFormatHint:cmAudioFormatDescriptionRef];
    self.audioFormat = cmAudioFormatDescriptionRef;
    // 音频设置
    NSDictionary *aduioSetting = @{AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                   AVNumberOfChannelsKey : @(1),
                                   AVSampleRateKey : @(self.audioSampleRate)
                                   };
    AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:aduioSetting];
    self.audioWriteInput = audioInput;
    if ([_assetWriter canAddInput:self.audioWriteInput]) {
        [_assetWriter addInput:self.audioWriteInput];
        DLog(@"audioFormat format === %@",self.audioFormat);
    }
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
    DLog(@"%@==%@==%@",data,sps,pps);
    free(extradata);
    return data;
}

- (CFDataRef)hevcExtradataCreate:(NSData *)sps PPS:(NSData *) pps VPS:(NSData *)vps SEI:(NSData *)sei {
    NSArray *extradataArray = @[vps,sps,pps,sei];
    int extradata_size = 23 + 15 + (int)sps.length + (int)pps.length + (int)vps.length + (int)sei.length;
    
    CFDataRef data = NULL;
    uint8_t *p;
    uint8_t *extradata = calloc(1, extradata_size);
    if (!extradata){
        return NULL;
    }
    p = extradata;
    
    //2
    uint8_t general_profile_space = 0;
    //1
    uint8_t general_tier_flag = 0;
    //5
    uint8_t general_profile_idc = 0;
    //32
    //    uint general_profile_compatibility_flags = 0;
    //48
    //    uint8_t general_constraint_indicator_flags[6] = {0};
    //8
    uint8_t general_level_idc = 0;
    //12
    uint min_spatial_segmentation_idc = 0;
    //2
    uint8_t parallelismType = 0;
    //2
    uint8_t chromaFormat = 0;
    //3
    uint8_t bitDepathLumaMinus8 = 0;
    //3
    uint8_t bitDepthChromaMinus8 = 0;
    //16
    uint avgFrameRate = 0;
    //2
    uint8_t constantFrameRate = 0;
    //3
    uint8_t numTemporalLayers = 0;
    //1
    uint8_t temporalIdNested = 0;
    //2
    uint8_t lengthSizeMinusOne = 3;
    //8
    uint8_t numOfArrays = 4;
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
    //    memcpy(p[2], (void *)&general_profile_compatibility_flags, 4);
    p[2] = 0;
    p[3] = 0;
    p[4] = 0;
    p[5] = 0;
    //48            general_constraint_indicator_flags
    //    memcpy(p[6], (void *)general_constraint_indicator_flags, 6);
    p[6] = 0;
    p[7] = 0;
    p[8] = 0;
    p[9] = 0;
    p[10] = 0;
    p[11] = 0;
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
        p[23 + i] = arry_completeness;
        //1            reserved(0)
        //6             NAL_unit_type
        if (j == 0) {
            //vps
            p[23 + i] = p[23 + i] | 0x20;
        }else if (j == 1) {
            p[23 + i] = p[23 + i] | 0x21;
        }else if (j == 2) {
            p[23 + i] = p[23 + i] | 0x22;
        }
        //16            numNalus
        p[23 + i + 1] = 0x00;
        p[23 + i + 2] = 0x01;
        //              --repeated once per NAL --
        NSData *naluData = extradataArray[j];
        //16            nalUnitLength
        int naluLength = (int)naluData.length;
        uint8_t naluLength_one = naluLength & 0x0000ff00;
        uint8_t naluLength_two = naluLength & 0x000000ff;
        p[23 + i + 3] = naluLength_one;
        p[23 + i + 4] = naluLength_two;
        //N             NALU data
        uint8_t *pNaluData = (uint8_t *)[naluData bytes];
        //        memcpy(p[23 + i + 5], pNaluData, naluLength);
        for (int k = 0; k < naluLength; k++) {
            p[23 + i + 5] = pNaluData[k];
            i++;
        }
        j++;
        //        i += 1 + 2 + 2 + naluLength;
        i += 1 + 2 + 2;
    }
    
    data = CFDataCreate(kCFAllocatorDefault, extradata, extradata_size);
    free(extradata);
    return data;
}

- (void)pushH264DataContentSpsAndPpsData:(NSData *)h264Data {
    uint8_t *videoData = (uint8_t*)[h264Data bytes];
    
    NaluUnit naluUnit;
    int frame_size = 0;
    int cur_pos = 0;
    while([ESCH264OrH265StreamToMp4FileTool ESCReadOneNaluFromAnnexBFormatH264WithNalu:&naluUnit buf:videoData buf_size:h264Data.length cur_pos:&cur_pos]){
        if(naluUnit.type == NAL_SPS || naluUnit.type == NAL_PPS || naluUnit.type == NAL_SEI) {
            if (naluUnit.type == NAL_SPS) {
                self.sps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
            } else if(naluUnit.type == NAL_PPS) {
                self.pps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
            }else {
                continue;
            }
            if (self.sps && self.pps && self.getOtherDataSuccess == NO) {
                [self setupWithSPS:self.sps PPS:self.pps];
                self.getOtherDataSuccess = YES;
            }
            continue;
        }
        //获取NALUS的长度，开辟内存
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
        
        NSData *pushVideoData = [NSData dataWithBytes:frame_data length:frame_size];
        [self pushVideoData:pushVideoData];
        free(frame_data);
    }
    
}

- (void)pushH265DataContentSpsAndPpsData:(NSData *)h265Data {
    uint8_t *videoData = (uint8_t*)[h265Data bytes];
    
    NaluUnit naluUnit;
    int currentPoint = 0;
    
    while ([ESCH264OrH265StreamToMp4FileTool ESCReadOneNaluFromAnnexBFormatH265WithNalu:&naluUnit buf:videoData buf_size:h265Data.length cur_pos:&currentPoint]) {
        //填充nalu
        if(( (naluUnit.type == H265_NAL_VPS || naluUnit.type == H265_NAL_SPS || naluUnit.type == H265_NAL_PPS || naluUnit.type == H265_NAL_SEI) )&& self.getOtherDataSuccess == NO) {
            
            NSData *data = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
//            DLog(@"data====%@",data);
            if (naluUnit.type == H265_NAL_SPS) {
                self.sps = data;
            } else if(naluUnit.type == H265_NAL_PPS) {
                self.pps = data;
            } else if(naluUnit.type == H265_NAL_VPS){
                self.vps = data;
            }else if(naluUnit.type == H265_NAL_SEI){
                self.sei = data;
            }else {
                continue;
            }
            if (self.sps && self.pps && self.vps && self.sei && self.getOtherDataSuccess == NO) {
                [self setupH265WithSPS:self.sps PPS:self.pps vps:self.vps sei:self.sei];
                self.getOtherDataSuccess = YES;
                //                    currentPoint = 0;
                DLog(@"设置sps成功");
            }else {
                
            }
            continue;
        }
        //填充视频数据
        //获取NALUS的长度，开辟内存
        BOOL isIFrame = NO;
        if (naluUnit.type == H265_NAL_IDR) {
            isIFrame = YES;
        }
        int frame_size = naluUnit.size + 4;
        uint8_t *frame_data = (uint8_t *) calloc(1, frame_size);
        uint32_t littleLength = CFSwapInt32HostToBig(naluUnit.size);
        uint8_t *lengthAddress = (uint8_t*)&littleLength;
        memcpy(frame_data, lengthAddress, 4);
        memcpy(frame_data+4, naluUnit.data, naluUnit.size);
        
        NSData *pushVideoData = [NSData dataWithBytes:frame_data length:frame_size];
        [self pushVideoData:pushVideoData];
        free(frame_data);
       
    }
    
}

- (void)pushPCMDataContent:(NSData *)pcmData {
    
    if (self.temPCMData == nil) {
        self.temPCMData = [NSMutableData data];
    }
    NSData *temData = pcmData;
    if (self.temPCMData.length > 0) {
        [self.temPCMData appendData:pcmData];
        temData = self.temPCMData;
        self.temPCMData = nil;
    }
    
    //首先判断pcmData的长度
    int pcmLength = (int)temData.length;
    int i = 0;
    
    int writeLength = 1024 * self.bitsPerChannel * self.audioChannels / 8;
    
    while (i + writeLength <= pcmLength && pcmLength >= writeLength) {
        NSData *pcmSubData = [temData subdataWithRange:NSMakeRange(i, writeLength)];
        i += writeLength;
        [self pushPCMData:pcmSubData];
    }
    if (i < pcmLength) {
        NSData *pcmSubData = [temData subdataWithRange:NSMakeRange(i, pcmLength - i)];
        self.temPCMData = [pcmSubData mutableCopy];
    }
    
}

/**
 *  从data流中读取1个NALU     00000001 40010c01 ffff0160 00000300 b0000003 00000300 3fac09
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

/**
 *  从data流中读取1个NALU     40010c01 ffff0160 00000300 b0000003 00000300 3fac09
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
            int pos = i + 4;
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
            
            int type = (buf[i + 4] & 0x7E)>>1;
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

- (void)pushVideoData:(NSData *)videoData{
    dispatch_async(self.recordQueue, ^{
        [self.videoDataArray addObject:videoData];
        
        if (self->_assetWriter.status == AVAssetWriterStatusUnknown) {
            DLog(@"_assetWriter status not ready");
            return;
        }
        if (self.videoStarted == NO) {
            self.videoStarted = YES;
            [self.videoWriteInput requestMediaDataWhenReadyOnQueue:self.recordQueue usingBlock:^{
                //取出数据填充
                [self pushCacheVideoData];
            }];
        }
    });
}

- (void)pushCacheVideoData {
    while (1) {
        if (self.videoDataArray.count == 0) {
            if (self.pushDataIsEnd == YES) {
                [self endRecorded];
            }
            return;
        }
        if (_assetWriter.status == AVAssetWriterStatusUnknown) {
            DLog(@"_assetWriter status not ready");
            return;
        }
        if ([_videoWriteInput isReadyForMoreMediaData]) {
            NSData *videoData = [self.videoDataArray firstObject];
            CMSampleBufferRef videoSample = [self videoSampleBufferWithData:videoData formatDescriptor:self.videoFormat dataIndex:self.videoFrameIndex];
            if (videoSample) {
                [_videoWriteInput appendSampleBuffer:videoSample];
//                DLog(@"pushCacheVideoData video appendSampleBuffer success == %ld",self.videoDataArray.count);
                self.videoFrameIndex++;
                CFRelease(videoSample);
                [self.videoDataArray removeObject:videoData];
            }
        }else {
//            DLog(@"pushCacheVideoData isReadyForMoreMediaData == NO=%ld",self.videoDataArray.count);
            return;
        }
        
    }
}

- (void)pushPCMData:(NSData *)pcmData{
    dispatch_async(self.recordQueue, ^{
        [self.audioDataArray addObject:pcmData];
        if (self->_assetWriter.status == AVAssetWriterStatusUnknown) {
            DLog(@"pushPCMData _assetWriter status not ready");
            return;
        }
        if (self.audioStarted == NO) {
            self.audioStarted = YES;
            [self.audioWriteInput requestMediaDataWhenReadyOnQueue:self.recordQueue usingBlock:^{
                [self pushCachePCMData];
            }];
        }
    });
}

- (void)pushCachePCMData {
    while (1) {
        if (self.audioDataArray.count == 0) {
            if (self.pushDataIsEnd == YES) {
                if (self.videoDataArray.count > 0) {
                    int8_t *temData = malloc(2048);
                    for (int i = 0; i < 2048; i++) {
                        temData[i] = 0;
                    }
                    NSData *temPcmData = [NSData dataWithBytes:temData length:2048];
                    free(temData);
                    [self.audioDataArray addObject:temPcmData];
                }else {
                    [self endRecorded];
                    return;
                }
            }else {
                return;
            }
        }
        if (_assetWriter.status == AVAssetWriterStatusUnknown) {
            DLog(@"_assetWriter status not ready");
            return;
        }
        //    DLog(@"%ld===%@",aacData.length,aacData);
        if ([self.audioWriteInput isReadyForMoreMediaData]) {
            
            NSData *pcmData = [self.audioDataArray firstObject];
            CMSampleBufferRef pcmSample = [self audioSampleBufferWithData:pcmData formatDescriptor:self.audioFormat dataIndex:self.audioFrameIndex];
            if (pcmSample) {
                [self.audioWriteInput appendSampleBuffer:pcmSample];
//                DLog(@"audio appendSampleBuffer success == %lu",self.audioDataArray.count);
                self.audioFrameIndex += 1024;
                [self.audioDataArray removeObject:pcmData];
                CFRelease(pcmSample);
            }
        } else {
//            DLog(@"audio write input isReadyForMoreMediaData NO==%lu ",self.audioDataArray.count);
            return;
        }
    }
}

- (CMSampleBufferRef)videoSampleBufferWithData:(NSData*)data formatDescriptor:(CMFormatDescriptionRef)formatDescription dataIndex:(int)dataIndex {
    OSStatus result;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    size_t data_len = data.length;
    
    
    size_t blockLength = data.length;
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
        DLog(@"create block buffer failed!");
        return NULL;
    }
    
    result = CMBlockBufferReplaceDataBytes([data bytes], blockBuffer, 0, [data length]);
    
    // check error
    if (result != noErr) {
        DLog(@"replace block buffer failed!");
        return NULL;
    }
    const size_t sampleSizes[] = {[data length]};
    
    
    int64_t ptss = (dataIndex * (1000.0 / self.frameRate)) *(TIME_SCALE/1000);
    //    DLog(@"pts:%lld",pts);
    CMTime pts = CMTimeMake(ptss, TIME_SCALE);
    
    
    CMSampleTimingInfo timeInfoArray[1] = { {
        .duration = CMTimeMake(1, 25),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = pts,
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
        DLog(@"CMSampleBufferCreate result:%d",result);
        return NULL;
    }
    // check error
    return sampleBuffer;
    
}

- (CMSampleBufferRef)audioSampleBufferWithData:(NSData*)data formatDescriptor:(CMFormatDescriptionRef)formatDescription dataIndex:(int)dataIndex {
    OSStatus result;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    size_t data_len = data.length;
    
    // _blockBuffer is a CMBlockBufferRef instance variable
    
    size_t blockLength = data.length;
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
        DLog(@"create block buffer failed!");
        return NULL;
    }
    
    result = CMBlockBufferReplaceDataBytes([data bytes], blockBuffer, 0, [data length]);
    
    // check error
    if (result != noErr) {
        DLog(@"replace block buffer failed!");
        return NULL;
    }
    
    int64_t ptst = (dataIndex * (1000.0 / self.audioSampleRate)) *(TIME_SCALE/1000);
    //    DLog(@"pts:%lld",pts);
    CMTime pts = CMTimeMake(ptst, TIME_SCALE);
    
    
    CMSampleTimingInfo timeInfoArray[1] = { {
        .duration = CMTimeMake(1024, 8000),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = pts,
    } };
    size_t samplesizesarray[1024] = {2};
    for (int i = 0; i < 1024; i++) {
        samplesizesarray[i] = 2;
    }
    
    result = CMSampleBufferCreate(kCFAllocatorDefault,//
                                  blockBuffer,//dataBuffer
                                  YES,//dataReady
                                  NULL,//makeDataReadyCallback
                                  NULL,//makeDataReadyRefcon
                                  formatDescription,
                                  1024,//numSamples
                                  1,//numSampleTimingEntries
                                  timeInfoArray,//
                                  1,
                                  samplesizesarray,//sampleSizeArray
                                  &sampleBuffer);
    if (result != noErr) {
        DLog(@"CMSampleBufferCreate result:%d",result);
        return NULL;
    }
    // check error
    return sampleBuffer;
    
}

- (void)endWritingCompletionHandler:(void (^)(void))handler {
    //结束
    dispatch_async(self.recordQueue, ^{
        self.endRecordBlock = handler;
        self.pushDataIsEnd = YES;
    });
}

- (void)endRecorded {
    
    int64_t ptss = (_videoFrameIndex * (1000.0 / self.frameRate)) *(TIME_SCALE/1000);
    CMTime time = CMTimeMake(ptss, TIME_SCALE);
    if (_assetWriter.status == AVAssetWriterStatusUnknown) {
        return;
    }
    DLog(@"%ld==%@",(long)self.assetWriter.status,self.assetWriter.error);
    if (self.videoWriteInput) {
        [_videoWriteInput markAsFinished];
    }
    if (self.audioWriteInput) {
        [self.audioWriteInput markAsFinished];
    }
    [_assetWriter endSessionAtSourceTime:time];
    [_assetWriter finishWritingWithCompletionHandler:^{
        DLog(@"finishWriting");
        if (self.endRecordBlock) {
            self.endRecordBlock();
        }
    }];
}

@end
