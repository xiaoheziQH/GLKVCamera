//
//  XBFilteredView.h
//  XBImageFilters
//
//  Created by xiss burg on 3/2/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import "GLKProgram.h"
#import <CoreMotion/CoreMotion.h>

#define kBgQueue dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)

@class XBFilteredView;

@interface XBFilteredView : UIView

@property (assign, nonatomic) GLKMatrix4 contentTransform;
@property (assign, nonatomic) CGSize contentSize; // Content size used to compute the contentMode transform. By default it can be the texture size.
@property (assign, nonatomic) GLKMatrix2 texCoordTransform;
@property (readonly, nonatomic) GLint maxTextureSize; // Maximum texture width and height
@property (readonly, nonatomic) GLuint mainTexture;
@property (readonly, nonatomic) GLuint radarTexture;
@property (assign, nonatomic) GLKMatrix4 uVMPTransform;
@property (readonly, nonatomic) EAGLContext *context;
@property (readonly, nonatomic) CMMotionManager * motionManager;
@property (copy, nonatomic) NSArray *programs;

/*
 * Returns an image with the contents of the framebuffer. 
 */
- (void)changeTexture:(UIImage *)radar;
- (BOOL)setBlendFilter;
- (void)startMotionManager;
- (void)stopMotionManager;
/*
 * Draws the OpenGL contents immediately.
 */
- (void)display;
- (void)displayWithFramebuffer:(GLuint)framebuffer width:(GLsizei)width height:(GLsizei)height present:(BOOL)present;


/* These methods are conceptually protected and should not be called directly. They are intended to be called by subclasses. */
- (void)_setTextureDataWithTextureCache:(CVOpenGLESTextureCacheRef)textureCache texture:(CVOpenGLESTextureRef *)texture imageBuffer:(CVImageBufferRef)imageBuffer;
@end

extern const GLKMatrix2 GLKMatrix2Identity;
