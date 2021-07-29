//
//  YLNewAudioManage.m
//  YLFFmpegCode
//
//  Created by yangyilin on 2021/4/29.
//  Copyright © 2021 com.anjubao.testSDK. All rights reserved.
//
#define kOutputBus 0
#define kInputBus 1
#import "YLNewAudioManage.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#include "YLData.h"
struct AACBuffer {
    uint8_t *buf;
    int rloc;
    int wloc;
    int maxSize;
    int remainSize;
};

int buffer_write(struct AACBuffer *buffer, const uint8_t *data, int size) {
    printf("remain == %d--- %d \n", buffer->remainSize, size);
    if (size > buffer->remainSize) {
        return -1;
    }
    int a = buffer->wloc + size;
    int f = a - buffer->maxSize;
    if (f > 0) {
        int s = (size - f);
        memcpy(buffer->buf + buffer->wloc, data, s);
        buffer->wloc += s;
        buffer->wloc = (buffer->wloc%buffer->maxSize);
        buffer->remainSize -= s;
        return buffer_write(buffer, data + s, f);
    } else {
        memcpy(buffer->buf + buffer->wloc, data, size);
        buffer->wloc += size;
        buffer->wloc = (buffer->wloc%buffer->maxSize);
        buffer->remainSize -= size;
    }
    return 0;
}

void buffer_read(struct AACBuffer *buffer, uint8_t *data, int size) {
    int h = buffer->maxSize - buffer->remainSize;
    if (h <= 0) {
        return;
    }
    int l = size - h;
    if (l <= 0) {
        memcpy(data, buffer->buf + buffer->rloc, size);
        buffer->rloc += size;
        buffer->rloc = (buffer->rloc%buffer->maxSize);
        buffer->remainSize += size;
    } else {
        memset(data, 0, size);
        memcpy(data, buffer->buf + buffer->rloc, h);
        buffer->rloc += h;
        buffer->rloc = (buffer->rloc%buffer->maxSize);
        buffer->remainSize += h;
    }
//    printf("remain == %d \n", buffer->remainSize);
}

@interface YLNewAudioManage() {
    OSStatus status;
    AudioComponentInstance audioUnit;
    struct AACBuffer buffer;
}
@end
@implementation YLNewAudioManage


- (void)sendBuffer:(uint8_t *)data size:(int)size numFrames:(int)num {
    if (size == 0) return;
    buffer_write(&buffer, data, size);
}

void checkStatus(OSStatus status) {
    
}

static OSStatus playbackCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    YLNewAudioManage *manage = (__bridge YLNewAudioManage *)inRefCon;
     
    for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        if (manage->buffer.maxSize - manage->buffer.remainSize < ioData->mBuffers[iBuffer].mDataByteSize) {
            manage.callback();
        }
        printf("semain == %d-------%u \n", manage->buffer.maxSize - manage->buffer.remainSize, (unsigned int)ioData->mBuffers[iBuffer].mDataByteSize);
        buffer_read(&(manage->buffer), ioData->mBuffers[iBuffer].mData, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    return noErr;
}

- (void)play {
    [self start];
    AudioOutputUnitStart(audioUnit);
}


- (void)start {
    int maxSize = 2*1024;
    buffer.buf = calloc(maxSize, sizeof(float));
    buffer.maxSize = maxSize*4;
    buffer.remainSize = maxSize*4;
    NSError *error = nil;
    
    // set audio session
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    [audioSession setActive:YES error:&error];
    // 描述音频元件
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    // 获得一个元件
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);

    // 获得 Audio Unit
    status = AudioComponentInstanceNew(inputComponent, &audioUnit);
    checkStatus(status);

    UInt32 flag = 1;
    // 为播放打开 IO
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  kOutputBus,
                                  &flag,
                                  sizeof(flag));
    checkStatus(status);

    // 描述格式
    AudioStreamBasicDescription audioFormat = [self getAudioFormat];

    // 设置格式
    checkStatus(status);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  kOutputBus,
                                  &audioFormat,
                                  sizeof(audioFormat));
    checkStatus(status);


    // 设置数据采集回调函数
    AURenderCallbackStruct callbackStruct;
    // 设置声音输出回调函数。当speaker需要数据时就会调用回调函数去获取数据。它是 "拉" 数据的概念。
    callbackStruct.inputProc = playbackCallback;
    callbackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  kOutputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    checkStatus(status);
    status = AudioUnitInitialize(audioUnit);
    checkStatus(status);
}

-(AudioStreamBasicDescription)getAudioFormat {
    AudioStreamBasicDescription format = {};
    format.mSampleRate         = 8000;
    format.mFormatID           = kAudioFormatLinearPCM;
    format.mFormatFlags        = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
    format.mFramesPerPacket    = 1;
    format.mChannelsPerFrame   = 1;
    format.mBitsPerChannel = 32;
    format.mBytesPerPacket = 4;
    format.mBytesPerFrame  = 4;
    return format;
}
@end
