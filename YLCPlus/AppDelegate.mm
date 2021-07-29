//
//  AppDelegate.m
//  YLCPlus
//
//  Created by yangyilin on 2021/7/1.
//

#import "AppDelegate.h"
#import "ViewController.h"
@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc]init];
    self.window.backgroundColor = UIColor.whiteColor;
    [self.window setHidden:NO];
    UIViewController *vc = [[ViewController alloc]init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}



@end
