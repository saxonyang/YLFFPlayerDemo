//
//  YLNewAudioManage.h
//  YLFFmpegCode
//
//  Created by yangyilin on 2021/4/29.
//  Copyright © 2021 com.anjubao.testSDK. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>
#import "YLModel.h"

NS_ASSUME_NONNULL_BEGIN
typedef int (^AudioCallBack2)(void);

@interface YLNewAudioManage : NSObject
@property(nonatomic, copy) AudioCallBack2 callback;

-(AudioStreamBasicDescription)getAudioFormat;
- (void)sendBuffer:(uint8_t *)data size:(int)size numFrames:(int)num;
- (void)play;
@end

NS_ASSUME_NONNULL_END
