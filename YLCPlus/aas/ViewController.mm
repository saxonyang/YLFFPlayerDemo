//
//  ViewController.m
//  YLCPlus
//
//  Created by yangyilin on 2021/7/1.
//

#import "ViewController.h"
#import "IAMedia.h"
#import "YLNewAudioManage.h"
@interface ViewController ()

@end

@implementation ViewController
const char url[] = "rtsp://192.168.0.100:554/Live/MainStream";//视频 h265,  音频 AAC 单声道 8000
YLNewAudioManage *unit;
IAMedia media;
UIGLView *window;
UIImageView *imageV;
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.redColor;
    window = [[UIGLView alloc]init];
    window.frame = CGRectMake(0, 64, 1920/5, 1080/5);
    window.backgroundColor = UIColor.blackColor;
    [self.view addSubview:window];
    imageV = [[UIImageView alloc]init];
    imageV.frame = CGRectMake(0, 64 + 1080/5 + 60, 1920/8, 1080/8);
    imageV.backgroundColor = UIColor.greenColor;
    [self.view addSubview:imageV];
    
    UIButton *btn1 = [UIButton buttonWithType: UIButtonTypeCustom];
    btn1.backgroundColor = UIColor.orangeColor;
    [self.view addSubview:btn1];
    [btn1 setTitle:@"取消录屏" forState:UIControlStateSelected];
    [btn1 setTitle:@"录屏" forState:UIControlStateNormal];
    btn1.frame = CGRectMake(0, 64 + 1080/5 + 260, 60, 60);
    [btn1 addTarget:self action:@selector(click1:) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *btn2 = [UIButton buttonWithType: UIButtonTypeCustom];
    btn2.backgroundColor = UIColor.purpleColor;
    [self.view addSubview:btn2];
    [btn2 setTitle:@"取消下载" forState:UIControlStateSelected];
    [btn2 setTitle:@"下载" forState:UIControlStateNormal];
    btn2.frame = CGRectMake(140, 64 + 1080/5 + 260, 60, 60);
    [btn2 addTarget:self action:@selector(click2:) forControlEvents:UIControlEventTouchUpInside];
    
    
    unit = [[YLNewAudioManage alloc]init];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        unit.callback = ^{
            return media.refleshFrame();
        };
        [unit play];
        NSLog(@"语音 %@", NSThread.currentThread);
    });
    dispatch_async(queue, ^{
        NSLog(@"视频 %@", NSThread.currentThread);
        media.renderData = callback;
        media.renderYUV = callback1;
        media.renderRGB = callback2;
        media.play(url);
    });
}


void callback(uint8_t *data, int size, int num) {
    [unit sendBuffer:data size:size numFrames:num];
}

void callback1(uint8_t *Y, uint8_t *U, uint8_t *V, int linesize, int width, int height) {
    [window displayYUV420pData:Y :U :V :width :height :linesize];
}

void callback2(uint8_t *rgb, int linesize, int width, int height) {
    int bytes_per_pix = 4;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef newContext = CGBitmapContextCreate(rgb,
    width, height, 8,
    width * bytes_per_pix,
    colorSpace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGImageRef frame = CGBitmapContextCreateImage(newContext);
    UIImage *image = [UIImage imageWithCGImage:frame];
    CGImageRelease(frame);
    CGContextRelease(newContext);
    CGColorSpaceRelease(colorSpace);
    dispatch_async(dispatch_get_main_queue(), ^{
        imageV.image = image;
    });
}

- (void)click1:(UIButton *)sender {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths objectAtIndex:0];
    docDir = [docDir stringByAppendingString:@"/recode.mp4"];
    const char* filename = (char*)[docDir UTF8String];
    [sender setSelected:!sender.isSelected];
    if (sender.isSelected) {
        if (media.recode_media(filename) < 0) {
            NSLog(@"创建失败");
        }
    } else {
        media.stop_recode_media();
    }
}

- (void)click2:(UIButton *)sender {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths objectAtIndex:0];
    docDir = [docDir stringByAppendingString:@"/download.mp4"];
    const char* filename = (char*) [docDir UTF8String];
    [sender setSelected:!sender.isSelected];
    if (sender.isSelected) {
        NSLog(@"开始下载");
        media.download_Media(filename);
    } else {
        NSLog(@"停止下载");
        media.stop_download_Media(filename, false);
    }
}

@end
