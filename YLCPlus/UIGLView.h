//
//  ALMoviePlayerControls.h
//  ALMoviePlayerController
//
//  Created by Anthony Lobianco on 10/8/13.
//  Copyright (c) 2013 Anthony Lobianco. All rights reserved.
//
#import <UIKit/UIKit.h>
@interface UIGLView : UIView
-(void)displayYUV420pData:(void*)y :(void*)u :(void*)v :(NSInteger)w :(NSInteger)h :(NSInteger)linesize;
-(void)displayYUV420pData:(void*)y :(void*)u :(void*)v :(NSInteger)w :(NSInteger)h :(NSInteger)linesize :(NSInteger)yuvType;
-(void)displayYUV420pData:(void*)y :(void*)u :(void*)v :(NSInteger)w :(NSInteger)h :(NSInteger)linesize :(NSInteger)yuvType :(BOOL)scale;
@end
