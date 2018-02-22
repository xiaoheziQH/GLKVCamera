//
//  ViewController.m
//  GLKVCamera
//
//  Created by QiuH on 2017/11/2.
//  Copyright © 2017年 QiuH. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <OpenGLES/ES2/glext.h>
#import "XBFilteredCameraView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CoreMotion.h>
#import "rotamap.h"
#define kVSPathsKey @"vsPaths"
#define kFSPathsKey @"fsPaths"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet XBFilteredCameraView *XBcameraView;
@property (nonatomic, copy) NSArray *filterPathArray;
@property (nonatomic, copy) NSArray *filterNameArray;
@property (nonatomic, assign) NSUInteger filterIndex;

@end

@implementation ViewController
{
    int count;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    count = 0;
    UIImage * radar = [UIImage imageNamed:@"radar.png"];
    [self.XBcameraView changeTexture:radar];
    [self.XBcameraView setBlendFilter];
    // Do any additional setup after loading the view, typically from a nib.

}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.XBcameraView startCapturing];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self.XBcameraView stopCapturing];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (IBAction)switch:(id)sender {
//    if (count%2 == 0) {
        UIImage * radar = [UIImage imageNamed:@"bo.png"];
        [self.XBcameraView changeTexture:radar];
//    } else {
//        [self.XBcameraView _setTextureImage:@"radar.png"];
//    }
//    count++;
}
@end
