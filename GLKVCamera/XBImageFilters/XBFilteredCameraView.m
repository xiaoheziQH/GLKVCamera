//
//  XBFilteredCameraView.m
//  XBImageFilters
//
//  Created by xiss burg on 3/2/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "XBFilteredCameraView.h"
#import <sys/time.h>
#import <objc/message.h>

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_6_0
    #define XBDispatchRelease(d)
#else
    #define XBDispatchRelease(d) (dispatch_release(d));
#endif

#define kMaxTimeSamples 10

NSString *const XBCaptureQualityPhoto = @"XBCaptureQualityPhoto";
NSString *const XBCaptureQualityHigh = @"XBCaptureQualityHigh";
NSString *const XBCaptureQualityMedium = @"XBCaptureQualityMedium";
NSString *const XBCaptureQualityLow = @"XBCaptureQualityLow";
NSString *const XBCaptureQuality1280x720 = @"XBCaptureQuality1280x720";
NSString *const XBCaptureQualityiFrame1280x720 = @"XBCaptureQualityiFrame1280x720";
NSString *const XBCaptureQualityiFrame960x540 = @"XBCaptureQualityiFrame960x540";
NSString *const XBCaptureQuality640x480 = @"XBCaptureQuality640x480";
NSString *const XBCaptureQuality352x288 = @"XBCaptureQuality352x288";

@interface XBFilteredCameraView ()

@property (strong, nonatomic) AVCaptureSession *captureSession;
@property (strong, nonatomic) AVCaptureDevice *device;
@property (strong, nonatomic) AVCaptureDeviceInput *input;
@property (strong, nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (assign, nonatomic) CVOpenGLESTextureCacheRef videoTextureCache;
@property (assign, nonatomic) CVOpenGLESTextureRef videoMainTexture;
@property (assign, nonatomic) size_t videoWidth, videoHeight;
@property (assign, nonatomic) BOOL shouldStartCapturingWhenBecomesActive;
@property (strong, nonatomic) NSMutableArray *secondsPerFrameArray;
@property (assign, nonatomic) BOOL takeAPhotoAfterAdjustingFocus;
@property (copy, nonatomic) void (^takeAPhotoCompletion)(UIImage *image);


- (void)setupOutputs;

@end

@implementation XBFilteredCameraView

@synthesize captureSession = _captureSession;
@synthesize device = _device;
@synthesize input = _input;
@synthesize videoDataOutput = _videoDataOutput;
@synthesize stillImageOutput = _stillImageOutput;
@synthesize videoTextureCache = _videoTextureCache;
@synthesize videoMainTexture = _videoMainTexture;
@synthesize videoWidth = _videoWidth, videoHeight = _videoHeight;
@synthesize cameraPosition = _cameraPosition;
@synthesize videoCaptureQuality = _videoCaptureQuality;
@synthesize flashMode = _flashMode;
@synthesize torchMode = _torchMode;
@synthesize photoOrientation = _photoOrientation;
@synthesize shouldStartCapturingWhenBecomesActive = _shouldStartCapturingWhenBecomesActive;
@synthesize rendering = _rendering;
@synthesize capturing = _capturing;

- (void)_XBFilteredCameraViewInit
{
    [EAGLContext setCurrentContext:self.context];
    self.contentMode = UIViewContentModeScaleAspectFill;
    
    self.videoHeight = self.videoWidth = 0;
    self.shouldStartCapturingWhenBecomesActive = NO;
    
    self.captureSession = [[AVCaptureSession alloc] init];
    self.videoCaptureQuality = XBCaptureQualityPhoto;
    self.photoOrientation = XBPhotoOrientationAuto;
    
    // Use the rear camera by default
    self.cameraPosition = XBCameraPositionBack;
    
    UITapGestureRecognizer *tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAction:)];
    [self addGestureRecognizer:tgr];
    
    [self setupOutputs];
    
    self.waitForFocus = YES;
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_6_0
    CVReturn ret = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_videoTextureCache);
#else
    CVReturn ret = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)self.context, NULL, &_videoTextureCache);
#endif
    if (ret != kCVReturnSuccess) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate: %d", ret);
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActiveNotification:) name:UIApplicationDidBecomeActiveNotification object:[UIApplication sharedApplication]];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self _XBFilteredCameraViewInit];
    }
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self _XBFilteredCameraViewInit];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopCapturing];
    [self cleanUpTextures];
    CFRelease(self.videoTextureCache);
}

#pragma mark - Properties

- (void)setCameraPosition:(XBCameraPosition)cameraPosition
{
    // Attempt to obtain the requested device. If not found, the state of this object is not changed and a warning is printed.
    AVCaptureDevice *newDevice = nil;

    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if ([device hasMediaType:AVMediaTypeVideo] && 
            ((device.position == AVCaptureDevicePositionBack && cameraPosition == XBCameraPositionBack) || 
             (device.position == AVCaptureDevicePositionFront && cameraPosition == XBCameraPositionFront))) {
            newDevice = device;
            break;
        }
    }

    if (newDevice == nil) {
        NSLog(@"XBFilteredCameraView: Failed to set camera position. No device found in the %@.", cameraPosition == XBCameraPositionFront? @"front": (cameraPosition == XBCameraPositionBack? @"back": @"unknown position"));
        return;
    }
    
    _cameraPosition = cameraPosition;
    self.device = newDevice;
    
    [self.captureSession beginConfiguration];
    [self.captureSession removeInput:self.input];
    
    NSError *error = nil;    
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&error];
    
    if (self.input) {
        [self.captureSession addInput:self.input];
    }
    else {
        NSLog(@"XBFilteredCameraView: Failed to create device input: %@", [error localizedDescription]);
    }
    
    [self.captureSession commitConfiguration];
    
    // refresh orientation
    AVCaptureConnection *connection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    // And the contentTransform
    if (_cameraPosition == XBCameraPositionBack) {
        self.contentTransform = GLKMatrix4Multiply(GLKMatrix4MakeScale(-1, 1, 1), GLKMatrix4MakeRotation(-M_PI, 0, 0, 1)); // Compensate for weird camera rotation
    }
    else if (_cameraPosition == XBCameraPositionFront) {
        self.contentTransform = GLKMatrix4MakeRotation(-M_PI, 0, 0, 1);
    }
}

- (void)setDevice:(AVCaptureDevice *)device
{
    _device = device;
    
}

- (BOOL)focusPointSupported
{
    return self.device.focusPointOfInterestSupported;
}

- (CGPoint)focusPoint
{
    return CGPointMake((1 - self.device.focusPointOfInterest.y)*self.bounds.size.width, self.device.focusPointOfInterest.x*self.bounds.size.height);
}

- (void)setFocusPoint:(CGPoint)focusPoint
{
    if (!self.focusPointSupported) {
        return;
    }
    
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) {
        NSLog(@"XBFilteredCameraView: Failed to set focus point: %@", [error localizedDescription]);
        return;
    }
    
    self.device.focusPointOfInterest = CGPointMake(focusPoint.y/self.bounds.size.height, 1 - focusPoint.x/self.bounds.size.width);
    self.device.focusMode = AVCaptureFocusModeAutoFocus;
    self.device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    [self.device unlockForConfiguration];
}

- (BOOL)exposurePointSupported
{
    return self.device.exposurePointOfInterestSupported;
}

- (CGPoint)exposurePoint
{
    return CGPointMake((1 - self.device.exposurePointOfInterest.y)*self.bounds.size.width, self.device.exposurePointOfInterest.x*self.bounds.size.height);
}

- (BOOL)lowLightBoostSupported
{
    if ([self.device respondsToSelector:@selector(isLowLightBoostSupported)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(self.device, @selector(isLowLightBoostSupported));
    }
    return NO;
}

- (BOOL)lowLightBoostEnabled
{
    if ([self.device respondsToSelector:@selector(isLowLightBoostEnabled)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(self.device, @selector(isLowLightBoostEnabled));
    }
    return NO;
}

- (BOOL)automaticallyEnablesLowLightBoostWhenAvailable
{
    if ([self.device respondsToSelector:@selector(automaticallyEnablesLowLightBoostWhenAvailable)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(self.device, @selector(automaticallyEnablesLowLightBoostWhenAvailable));
    }
    return NO;
}

- (void)setAutomaticallyEnablesLowLightBoostWhenAvailable:(BOOL)automaticallyEnablesLowLightBoostWhenAvailable
{
    if (self.lowLightBoostSupported && [self.device respondsToSelector:@selector(setAutomaticallyEnablesLowLightBoostWhenAvailable:)]) {
        NSError *error = nil;
        if (![self.device lockForConfiguration:&error]) {
            NSLog(@"XBFilteredCameraView: Failed to enable automatic low light boost: %@", [error localizedDescription]);
            return;
        }
        ((void(*)(id, SEL, BOOL))objc_msgSend)(self.device, @selector(setAutomaticallyEnablesLowLightBoostWhenAvailable:), automaticallyEnablesLowLightBoostWhenAvailable);
        [self.device unlockForConfiguration];
    }
}
//bao guang
- (void)setExposurePoint:(CGPoint)exposurePoint
{
    if (!self.exposurePointSupported) {
        return;
    }
    
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) {
        NSLog(@"XBFilteredCameraView: Failed to set exposure point: %@", [error localizedDescription]);
        return;
    }
    self.device.exposureMode = AVCaptureExposureModeLocked;
    self.device.exposurePointOfInterest = CGPointMake(exposurePoint.y/self.bounds.size.height, 1 - exposurePoint.x/self.bounds.size.width);
    self.device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    [self.device unlockForConfiguration];
}

- (void)setVideoCaptureQuality:(NSString *)videoCaptureQuality
{
    _videoCaptureQuality = [videoCaptureQuality copy];
    self.captureSession.sessionPreset = [self captureSessionPresetFromCaptureQuality:_videoCaptureQuality];
}
//shan guang deng
- (void)setFlashMode:(XBFlashMode)flashMode
{
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) {
        NSLog(@"XBFilteredCameraView: Failed to set flash mode: %@", [error localizedDescription]);
        return;
    }
    
    _flashMode = flashMode;
    
    switch (_flashMode) {
        case XBFlashModeOff:
            self.device.flashMode = AVCaptureFlashModeOff;
            break;
        
        case XBFlashModeOn:
            self.device.flashMode = AVCaptureFlashModeOn;
            break;
            
        case XBFlashModeAuto:
            self.device.flashMode = AVCaptureFlashModeAuto;
            break;
    }
    
    [self.device unlockForConfiguration];
}
//shou dian tong
- (void)setTorchMode:(XBTorchMode)torchMode
{
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) {
        NSLog(@"XBFilteredCameraView: Failed to set torch mode: %@", [error localizedDescription]);
        return;
    }
    
    _torchMode = torchMode;
    
    switch (_torchMode) {
        case XBTorchModeOff:
            self.device.torchMode = AVCaptureTorchModeOff;
            break;

        case XBTorchModeOn:
            self.device.torchMode = AVCaptureTorchModeOn;
            break;
            
        case XBTorchModeAuto:
            self.device.torchMode = AVCaptureTorchModeAuto;
            break;
    }
    
    [self.device unlockForConfiguration];
}

- (BOOL)hasTorch
{
    return [self.device hasTorch];
}

- (BOOL)isCapturing
{
    return self.captureSession.isRunning;
}

- (void)setCapturing:(BOOL)capturing
{
    capturing? [self startCapturing]: [self stopCapturing];
}

- (void)setRendering:(BOOL)rendering
{
    _rendering = rendering;
    
    if (_rendering) {
        [self.videoDataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    }
    else {
        [self.videoDataOutput setSampleBufferDelegate:nil queue:NULL];
    }
}

- (GLKMatrix2)rawTexCoordTransform
{
    XBPhotoOrientation orientation = self.photoOrientation != XBPhotoOrientationAuto? self.photoOrientation: [self photoOrientationForDeviceOrientation];
    return [self rawTexCoordTransformForPhotoOrientation:orientation cameraPosition:self.cameraPosition];
}

#pragma mark - Methods

- (void)startCapturing
{
    self.rendering = YES;
//    [self startMotionManager];
    [self.captureSession startRunning];
}

- (void)stopCapturing
{
    self.rendering = NO;
//    [self stopMotionManager];
    [self.captureSession stopRunning];
}

- (BOOL)hasCameraAtPosition:(XBCameraPosition)cameraPosition
{
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if ([device hasMediaType:AVMediaTypeVideo] && 
            ((device.position == AVCaptureDevicePositionBack && cameraPosition == XBCameraPositionBack) || 
             (device.position == AVCaptureDevicePositionFront && cameraPosition == XBCameraPositionFront))) {
            return YES;
        }
    }
    
    return NO;
}

- (void)toggleTorch
{
    self.torchMode = self.torchMode == XBTorchModeOff? XBTorchModeOn: XBTorchModeOff;
}



- (XBPhotoOrientation)photoOrientationForDeviceOrientation
{
    XBPhotoOrientation orientation = XBPhotoOrientationPortrait;
    
    switch ([[UIDevice currentDevice] orientation]) {
        case UIDeviceOrientationLandscapeLeft:
            orientation = XBPhotoOrientationLandscapeLeft;
            break;
            
        case UIDeviceOrientationLandscapeRight:
            orientation = XBPhotoOrientationLandscapeRight;
            break;
            
        case UIDeviceOrientationPortrait:
            orientation = XBPhotoOrientationPortrait;
            break;
            
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = XBPhotoOrientationPortraitUpsideDown;
            break;
            
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationUnknown:
            orientation = XBPhotoOrientationPortrait;
            break;
    }
    
    return orientation;
}

- (GLKMatrix4)contentTransformForPhotoOrientation:(XBPhotoOrientation)photoOrientation cameraPosition:(XBCameraPosition)cameraPosition
{
    GLKMatrix4 contentTransform = GLKMatrix4Identity;
    
    if (self.cameraPosition == XBCameraPositionBack) {
        switch (photoOrientation) {
            case XBPhotoOrientationPortrait:
                contentTransform = GLKMatrix4MakeRotation(M_PI_2, 0, 0, 1);
                break;
                
            case XBPhotoOrientationPortraitUpsideDown:
                contentTransform = GLKMatrix4MakeRotation(-M_PI_2, 0, 0, 1);
                break;
                
            case XBPhotoOrientationLandscapeLeft:
                contentTransform = GLKMatrix4Identity;
                break;
                
            case XBPhotoOrientationLandscapeRight:
                contentTransform = GLKMatrix4MakeRotation(M_PI, 0, 0, 1);
                break;
                
            default:
                break;
        }
    }
    else if (self.cameraPosition == XBCameraPositionFront) {
        switch (photoOrientation) {
            case XBPhotoOrientationPortrait:
                contentTransform = GLKMatrix4MakeRotation(M_PI_2, 0, 0, 1);
                break;
                
            case XBPhotoOrientationPortraitUpsideDown:
                contentTransform = GLKMatrix4MakeRotation(-M_PI_2, 0, 0, 1);
                break;
                
            case XBPhotoOrientationLandscapeLeft:
                contentTransform = GLKMatrix4MakeRotation(M_PI, 0, 0, 1);
                break;
                
            case XBPhotoOrientationLandscapeRight:
                contentTransform = GLKMatrix4Identity;
                break;
                
            default:
                break;
        }
    }
    
    return contentTransform;
}

- (GLKMatrix2)rawTexCoordTransformForPhotoOrientation:(XBPhotoOrientation)photoOrientation cameraPosition:(XBCameraPosition)cameraPosition
{
    GLKMatrix2 m = GLKMatrix2Identity;
    
    if (self.cameraPosition == XBCameraPositionBack) {
        switch (photoOrientation) {
            case XBPhotoOrientationPortrait:
                m = (GLKMatrix2){1, 0, 0, -1};
                break;
                
            case XBPhotoOrientationPortraitUpsideDown:
                m = (GLKMatrix2){-1, 0, 0, 1};
                break;
                
            case XBPhotoOrientationLandscapeLeft:
                m = (GLKMatrix2){0, -1, -1, 0};
                break;
                
            case XBPhotoOrientationLandscapeRight:
                m = (GLKMatrix2){0, 1, 1, 0};
                break;
                
            default:
                break;
        }
    }
    else if (self.cameraPosition == XBCameraPositionFront) {
        switch (photoOrientation) {
            case XBPhotoOrientationPortrait:
                m = (GLKMatrix2){-1, 0, 0, -1};
                break;
                
            case XBPhotoOrientationPortraitUpsideDown:
                m = (GLKMatrix2){1, 0, 0, 1};
                break;
                
            case XBPhotoOrientationLandscapeLeft:
                m = (GLKMatrix2){0, 1, -1, 0};
                break;
                
            case XBPhotoOrientationLandscapeRight:
                m = (GLKMatrix2){0, -1, 1, 0};
                break;
                
            default:
                break;
        }
    }
    
    return m;
}

- (void)cleanUpTextures
{
    if (self.videoMainTexture != NULL) {
        CFRelease(self.videoMainTexture);
        self.videoMainTexture = NULL;
    }
    
    CVOpenGLESTextureCacheFlush(self.videoTextureCache, 0);
}

#pragma mark - Private Methods

- (void)setupOutputs
{
    [self.captureSession beginConfiguration];
    
    [self.captureSession removeOutput:self.videoDataOutput];
    [self.captureSession removeOutput:self.stillImageOutput];
    
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.videoDataOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [self.videoDataOutput setSampleBufferDelegate:self queue:kBgQueue];
    [self.captureSession addOutput:self.videoDataOutput];
    
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    self.stillImageOutput.outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG, AVVideoCodecKey, [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey, nil];
    [self.captureSession addOutput:self.stillImageOutput];

    [self.captureSession commitConfiguration];
    
    AVCaptureConnection *connection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
}

- (NSString *)captureSessionPresetFromCaptureQuality:(NSString *)captureQuality
{
    if ([captureQuality isEqualToString:XBCaptureQualityPhoto]) {
        return AVCaptureSessionPresetPhoto;
    }
    else if ([captureQuality isEqualToString:XBCaptureQualityHigh]) {
        return AVCaptureSessionPresetHigh;
    }
    else if ([captureQuality isEqualToString:XBCaptureQualityMedium]) {
        return AVCaptureSessionPresetMedium;
    }
    else if ([captureQuality isEqualToString:XBCaptureQualityLow]) {
        return AVCaptureSessionPresetLow;
    }
    else if ([captureQuality isEqualToString:XBCaptureQuality1280x720]) {
        return AVCaptureSessionPreset1280x720;
    }
    else if ([captureQuality isEqualToString:XBCaptureQualityiFrame1280x720]) {
        return AVCaptureSessionPresetiFrame1280x720;
    }
    else if ([captureQuality isEqualToString:XBCaptureQualityiFrame960x540]) {
        return AVCaptureSessionPresetiFrame960x540;
    }
    else if ([captureQuality isEqualToString:XBCaptureQuality640x480]) {
        return AVCaptureSessionPreset640x480;
    }
    else if ([captureQuality isEqualToString:XBCaptureQuality352x288]) {
        return AVCaptureSessionPreset352x288;
    }
    else {
        return nil;
    }
}

#pragma mark - Gesture recognition

- (void)tapAction:(UITapGestureRecognizer *)tgr
{
    if (tgr.state == UIGestureRecognizerStateRecognized) {
        CGPoint location = [tgr locationInView:self];
        self.focusPoint = location;
        self.exposurePoint = location;
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (!self.isRendering) {
        return;
    }
        
    [EAGLContext setCurrentContext:self.context];
    
    [self cleanUpTextures];
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Compensate for padding. A small black line will be visible on the right. Also adjust the texture coordinate transform to fix this.
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    if (width != self.videoWidth || height != self.videoHeight) {
        self.videoWidth = width;
        self.videoHeight = height;
        self.contentSize = CGSizeMake(width, height);
        float ratio = (float)CVPixelBufferGetWidth(imageBuffer)/width;
        self.texCoordTransform = (GLKMatrix2){ratio, 0, 0, 1}; // Apply a horizontal stretch to hide the row padding
    }
    
    [self _setTextureDataWithTextureCache:self.videoTextureCache texture:&_videoMainTexture imageBuffer:imageBuffer];
    [self display];
    
}

#pragma mark - Notifications

- (void)applicationDidEnterBackgroundNotification:(NSNotification *)notification
{
    self.shouldStartCapturingWhenBecomesActive = self.captureSession.running;
    [self stopCapturing];
    glFinish();
}

- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification
{
//    if (self.shouldStartCapturingWhenBecomesActive) {
        [self startCapturing];
//    }
}

@end
