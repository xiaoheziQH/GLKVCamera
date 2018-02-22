//
//  XBFilteredView.m
//  XBImageFilters
//
//  Created by xiss burg on 3/2/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "XBFilteredView.h"
#import "GLKProgram.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/host_info.h>
#import <mach/mach.h>
#import <OpenGLES/ES2/glext.h>
#import "rotamap.h"


const GLKMatrix2 GLKMatrix2Identity = {1, 0, 0, 1};

typedef struct {
    GLKVector4 position;
    GLKVector2 texCoord;
} Vertex;

CGSize CGSizeRotate(CGSize size, GLKMatrix4 m);

@interface XBFilteredView ()
{
    GLKMatrix4 _vMatrix;
    GLKMatrix4 _projMatrix;
    GLKMatrix4 _rotaMatrix;
    GLKMatrix4 _mMatrix;
}

@property (assign, nonatomic) GLuint framebuffer;
@property (assign, nonatomic) GLuint colorRenderbuffer;
@property (assign, nonatomic) GLint viewportWidth;
@property (assign, nonatomic) GLint viewportHeight;

@property (assign, nonatomic) CGRect previousBounds; //used in layoutSubviews to determine whether the framebuffer should be recreated

@property (assign, nonatomic) GLuint imageQuadVertexBuffer;
@property (assign, nonatomic) GLuint radarQuadVertexBuffer;
@property (assign, nonatomic) GLuint mainTexture;
@property (assign, nonatomic) GLint textureWidth, textureHeight;

@property (assign, nonatomic) GLKMatrix4 contentModeTransform;

@property (assign, nonatomic) GLuint radarTexture;
@property (assign, nonatomic) GLuint radarbuffer;

@property (strong, nonatomic) CMMotionManager * motionManager;


- (void)setupGL;
- (void)destroyGL;
- (GLuint)generateDefaultTextureWithWidth:(GLint)width height:(GLint)height data:(GLvoid *)data;
- (GLuint)generateDefaultFramebufferWithTargetTexture:(GLuint)texture;

- (void)refreshContentTransform;

- (GLKMatrix4)transformForAspectFitOrFill:(BOOL)fit;
- (GLKMatrix4)transformForPositionalContentMode:(UIViewContentMode)contentMode;

@end

@implementation XBFilteredView

@synthesize context = _context;
@synthesize framebuffer = _framebuffer;
@synthesize colorRenderbuffer = _colorRenderbuffer;
@synthesize viewportWidth = _viewportWidth;
@synthesize viewportHeight = _viewportHeight;
@synthesize previousBounds = _previousBounds;
@synthesize imageQuadVertexBuffer = _imageQuadVertexBuffer;
@synthesize radarQuadVertexBuffer = _radarQuadVertexBuffer;
@synthesize mainTexture = _mainTexture;
@synthesize radarTexture = _radarTexture;
@synthesize textureWidth = _textureWidth, textureHeight = _textureHeight;
@synthesize contentTransform = _contentTransform;
@synthesize contentModeTransform = _contentModeTransform;
@synthesize contentSize = _contentSize;
@synthesize texCoordTransform = _texCoordTransform;
@synthesize programs = _programs;
@synthesize maxTextureSize = _maxTextureSize;
@synthesize motionManager = _motionManager;

+ (EAGLContext *)newContext
{
    static EAGLSharegroup *sharegroup = nil;
    if (sharegroup == nil) {
        EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        sharegroup = context.sharegroup;
        return context;
    }
    else {
        return [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup:sharegroup];
    }
}

/**
 * Actual initializer. Called both in initWithFrame: when creating an instance programatically and in awakeFromNib when creating an instance
 * from a nib/storyboard.
 */
- (void)_XBFilteredViewInit //Use a weird name to avoid being overidden
{
    self.contentScaleFactor = [[UIScreen mainScreen] scale];
    self.layer.opaque = YES;
    ((CAEAGLLayer *)self.layer).drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];

    _context = [XBFilteredView newContext];
    
    self.previousBounds = CGRectZero;

    if ([self needsToCreateFramebuffer]) {
        [self createFramebuffer];
        self.previousBounds = self.bounds;
    }
    [self setupGL];
}

- (void)drawFrame{
    
    _vMatrix = GLKMatrix4MakeLookAt(0, 0, -0.2, 0, 0, 1, 0, 1, 0);
    
    _vMatrix = GLKMatrix4Multiply(_rotaMatrix, _vMatrix);
    _uVMPTransform = GLKMatrix4Multiply(_projMatrix, _vMatrix);
    if (_programs.count > 1) {
        GLKProgram *program = [self.programs objectAtIndex:1];
        [program setValue:(void *)&_uVMPTransform forUniformNamed:@"uMVPMatrix"];
    }
 
}
- (void)startMotionManager {

    if (_motionManager == nil) {
        _motionManager = [[CMMotionManager alloc] init];
    }
    if (!_motionManager.isDeviceMotionAvailable) {
        NSLog(@"_motionManager不可用");
        return;
    }
    [_motionManager startDeviceMotionUpdates];
    
}
- (void)stopMotionManager {
    if (_motionManager != nil) {
        if (_motionManager.deviceMotionActive) {
            [_motionManager stopDeviceMotionUpdates];
        }
    }
}
- (void)handleDeviceMotion {
    [EAGLContext setCurrentContext:self.context];
    if (_motionManager == nil || !_motionManager.isDeviceMotionActive) {
        [self startMotionManager];
        return;
    }
    
    //四元数
    CMDeviceMotion *deviceMotion = _motionManager.deviceMotion;
    CMQuaternion quateration = deviceMotion.attitude.quaternion;
    float vertor[5] = {quateration.x,quateration.y,quateration.z,quateration.w,0};
    GLKMatrix4 mm;
    getRotationMatrixFromVector(mm.m, 16, vertor, 5);
    remapCoordinateSystem(mm.m, 1 | 0x80, 2 | 0x80, _rotaMatrix.m);
    [self drawFrame];
}
- (BOOL) shouldAutorotate {
    return NO;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self _XBFilteredViewInit];
    }
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self _XBFilteredViewInit];
}

- (void)dealloc
{
    [EAGLContext setCurrentContext:self.context];
    [self destroyGL];
    _context = nil;
    [EAGLContext setCurrentContext:nil];
}

#pragma mark - Overrides

+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (void)layoutSubviews
{
    if ([self needsToCreateFramebuffer]) {
        [self createFramebuffer];
    }
    
    [self refreshContentModeTransform];
    
    self.previousBounds = self.bounds;
    [self display];
}

#pragma mark - Properties

- (void)setContentTransform:(GLKMatrix4)contentTransform
{
    _contentTransform = contentTransform;
    [self refreshContentModeTransform];
}

- (void)setContentModeTransform:(GLKMatrix4)contentModeTransform
{
    _contentModeTransform = contentModeTransform;
    [self refreshContentTransform];
}

- (void)setContentSize:(CGSize)contentSize
{
    _contentSize = contentSize;
    [self refreshContentModeTransform];
}

- (void)setTexCoordTransform:(GLKMatrix2)texCoordTransform
{
    _texCoordTransform = texCoordTransform;
    GLKProgram *program = [self.programs objectAtIndex:0];
    [program setValue:&_texCoordTransform forUniformNamed:@"u_texCoordTransform"];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor
{
    [super setBackgroundColor:backgroundColor];
    [EAGLContext setCurrentContext:self.context];
    CGFloat r, g, b, a;
    [self.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
    glClearColor(r, g, b, a);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

- (void)setContentMode:(UIViewContentMode)contentMode
{
    [super setContentMode:contentMode];
    [self refreshContentModeTransform];
}
- (BOOL)setBlendFilter{
    [EAGLContext setCurrentContext:self.context];
    NSMutableArray *programs = [[NSMutableArray alloc] initWithCapacity:2];
    GLKProgram *program = [GLKProgram defaultProgram];
    [programs addObject:program];
    NSString *radarVSPath = [[NSBundle mainBundle] pathForResource:@"RShader" ofType:@"vsh"];
    NSString *radarFSPath = [[NSBundle mainBundle] pathForResource:@"RShader" ofType:@"fsh"];
    NSError *error = nil;
    GLKProgram *rprogram = [[GLKProgram alloc] initWithVertexShaderFromFile:radarVSPath fragmentShaderFromFile:radarFSPath error:&error];
    if (rprogram == nil) {
        NSLog(@"%@", error.localizedDescription);
        return NO;
    }
    [programs addObject:rprogram];
    self.programs = programs;
    return YES;
}
- (void)setDefaultFilter
{
    self.programs = @[[GLKProgram defaultProgram]];
}
- (void)setPrograms:(NSArray *)programs
{
    if (programs == _programs) {
        return;
    }
    _programs = [programs copy];
    
    for (int i = 0; i < _programs.count; ++i) {
        GLKProgram *program = _programs[i];
        if (i == 0) {
            GLKMatrix4 m = GLKMatrix4Identity;
            m = GLKMatrix4Multiply(self.contentModeTransform, self.contentTransform);
            [program setValue:&m forUniformNamed:@"u_contentTransform"];
            [program setValue:&_texCoordTransform forUniformNamed:@"u_texCoordTransform"];
        }
        
        GLuint sourceTexture = 0;
        if (i == 0) {
            sourceTexture = self.mainTexture;
        } else {
            sourceTexture = self.radarTexture;
        }
        
        [program bindSamplerNamed:@"s_texture" toTexture:sourceTexture unit:0];
        
        // Enable vertex position and texCoord attributes
        GLKAttribute *positionAttribute = [program.attributes objectForKey:@"a_position"];
        glVertexAttribPointer(positionAttribute.location, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, position));
        glEnableVertexAttribArray(positionAttribute.location);
        
        GLKAttribute *texCoordAttribute = [program.attributes objectForKey:@"a_texCoord"];
        glVertexAttribPointer(texCoordAttribute.location, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, texCoord));
        glEnableVertexAttribArray(texCoordAttribute.location);
    }
    [self refreshContentTransform];
}

#pragma mark - radar image
- (void)changeTexture:(UIImage *)radar{
    glDeleteTextures(1, &_radarTexture);
    [self _setTextureImage:radar];
}

- (void)_setTextureImage:(UIImage *)radar{
    
    [EAGLContext setCurrentContext:self.context];
    UIImage *image = radar;
    
    CGSize size = self.bounds.size;
    CGImageRef CGImage = image.CGImage;
    GLint width = (GLint)size.width;
    GLint height = (GLint)size.width;
    size_t bitsPerComponent = 8;
    size_t bytesPerRow = width * 4;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    // Invert vertically for OpenGL
    
    CGRect rect = CGRectMake(0, 0, width, height);
    CGContextSetBlendMode(context, kCGBlendModeMultiply);
    CGContextSetAlpha(context, 0.39);//100
    CGContextClearRect(context, rect);//to transparent
    
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1.0, -1.0);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), CGImage);
    
    int distance = (int)width/50;
    float co = 1.0f;
    for (int i = 0; i < width; i += distance) {//|
        CGFloat cyan[4] = {
            co,co,
            co,co
        };
        CGContextSetStrokeColor(context, cyan);
        CGContextSetLineWidth(context, 1.0f);
        CGPoint aPoints[2];
        aPoints[0] = CGPointMake(i, 0);
        aPoints[1] = CGPointMake(i, width);
        CGContextAddLines(context, aPoints, 2);
        CGContextDrawPath(context, kCGPathEOFillStroke);
    }
    for (int i = 0; i < width; i += distance) {//-
        CGFloat cyan[4] = {
            co,co,
            co,co
        };
        CGContextSetStrokeColor(context, cyan);
        CGContextSetLineWidth(context, 1.0f);
        CGPoint aPoints[2];
        aPoints[0] = CGPointMake(0, i);
        aPoints[1] = CGPointMake(width, i);
        CGContextAddLines(context, aPoints, 2);
        CGContextDrawPath(context, kCGPathEOFillStroke);
    }
    GLubyte *textureData = (GLubyte *)CGBitmapContextGetData(context);
    self.radarTexture = [self generateDefaultTextureWithWidth:width height:height data:textureData];
    
}

#pragma mark - AVcapture
- (void)_setTextureDataWithTextureCache:(CVOpenGLESTextureCacheRef)textureCache texture:(CVOpenGLESTextureRef *)texture imageBuffer:(CVImageBufferRef)imageBuffer
{
    [EAGLContext setCurrentContext:self.context];
    
    // Compensate for padding. A small black line will be visible on the right. Also adjust the texture coordinate transform to fix this.
    GLint width = (GLint)CVPixelBufferGetWidth(imageBuffer);
    GLint height = (GLint)CVPixelBufferGetHeight(imageBuffer);
    
    CVReturn ret = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, NULL, GL_TEXTURE_2D, GL_RGBA, width, height, GL_BGRA, GL_UNSIGNED_BYTE, 0, texture);
    if (ret != kCVReturnSuccess) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage: %d", ret);
    }
    
    if (width != self.textureWidth || height != self.textureHeight) {
        self.textureWidth = width;
        self.textureHeight = height;
        
        [self refreshContentTransform];
    }
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(CVOpenGLESTextureGetTarget(*texture), CVOpenGLESTextureGetName(*texture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // Update the texture in the first shader
    if (self.programs.count > 0 && CVOpenGLESTextureGetName(*texture) != self.mainTexture) {
        self.mainTexture = CVOpenGLESTextureGetName(*texture);
        GLKProgram *firstProgram = [self.programs objectAtIndex:0];
        [firstProgram bindSamplerNamed:@"s_texture" toTexture:self.mainTexture unit:0];
    }
}
- (void)display
{
    [self displayWithFramebuffer:self.framebuffer width:self.viewportWidth height:self.viewportHeight present:YES];
}

- (void)displayWithFramebuffer:(GLuint)framebuffer width:(GLsizei)width height:(GLsizei)height present:(BOOL)present
{
    [EAGLContext setCurrentContext:self.context];
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    for (int i = 0; i < self.programs.count; i++) {
        GLKProgram *program = [self.programs objectAtIndex:i];
        if (i == 0) {
            glBindBuffer(GL_ARRAY_BUFFER, self.imageQuadVertexBuffer);
            
        } else {
            [self handleDeviceMotion];
            glBindBuffer(GL_ARRAY_BUFFER, self.radarQuadVertexBuffer);
        }
        
        GLKAttribute *positionAttribute = [program.attributes objectForKey:@"a_position"];
        glVertexAttribPointer(positionAttribute.location, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, position));
        glEnableVertexAttribArray(positionAttribute.location);
        
        GLKAttribute *texCoordAttribute = [program.attributes objectForKey:@"a_texCoord"];
        glVertexAttribPointer(texCoordAttribute.location, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, texCoord));
        glEnableVertexAttribArray(texCoordAttribute.location);
        
        [program prepareToDraw];
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    
    if (present) {
        [self.context presentRenderbuffer:GL_RENDERBUFFER];
    }

    
#ifdef DEBUG
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"OpenGL error: 0x%x", error);
    }
#endif
}

#pragma mark - Private Methods
- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    // Make sure the background color is set
    self.backgroundColor = [UIColor clearColor];
    //关闭深度测试
    glDisable(GL_DEPTH_TEST);
    //开启混合
    glEnable(GL_BLEND);
    //设置混合因子
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // Create vertices
    //    CGFloat ONE = 0.3f;
    Vertex vertices[] = {
        {{ 1,  1, 0, 1}, {1, 1}},
        {{-1,  1, 0, 1}, {0, 1}},
        {{ 1, -1, 0, 1}, {1, 0}},
        {{-1, -1, 0, 1}, {0, 0}}
    };
    
    // Create vertex buffer and fill it with data
    glGenBuffers(1, &_imageQuadVertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, self.imageQuadVertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    glGenBuffers(1, &_radarQuadVertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _radarQuadVertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    
    // Setup default shader
    [self setDefaultFilter];

    // Initialize transform to the most basic projection, and set others to identity
    self.contentModeTransform = GLKMatrix4MakeOrtho(-1.f, 1.f, -1.f, 1.f, -1.f, 1.f);
    self.contentTransform = GLKMatrix4Identity;
    self.texCoordTransform = GLKMatrix2Identity;
    
    self.uVMPTransform = GLKMatrix4Identity;
    _rotaMatrix = GLKMatrix4Identity;
    
    [self creatProjMatrix];
   
    // Enable vertex position and texCoord attributes
  
    // Get max tex size
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &_maxTextureSize);
    glActiveTexture(GL_TEXTURE0);
    
}

- (void)destroyGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_imageQuadVertexBuffer);
    self.imageQuadVertexBuffer = 0;
    glDeleteBuffers(1, &_radarQuadVertexBuffer);
    self.radarQuadVertexBuffer = 0;
    
    glDeleteTextures(1, &_mainTexture);
    glDeleteTextures(1, &_radarTexture);
    
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    [self destroyFramebuffer];
}
- (UIImage *)drawImage:(NSString*)fileName {
    UIImage * img = [UIImage imageNamed:fileName];
    CGFloat width = img.size.width;
    CGFloat height = img.size.height;
    UIGraphicsBeginImageContextWithOptions(img.size, NO, [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect rect = CGRectMake(0, 0, width, height);

    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1.0, -1.0);
    CGContextSetBlendMode(context, kCGBlendModeMultiply);
    CGContextSetAlpha(context, 0.78);//200
    CGContextClearRect(context, rect);//to transparent

    CGContextDrawImage(context, rect, img.CGImage);
    
    int distance = (int)width/40;
    for (int i = 0; i < width; i += distance) {
        CGFloat cyan[4] = {
            0.9f,0.9f,
            0.0f,1.0f
        };
        CGContextSetStrokeColor(context, cyan);
        CGContextSetLineWidth(context, 1.0f);
        CGPoint aPoints[2];
        aPoints[0] = CGPointMake(i, 0);
        aPoints[1] = CGPointMake(i, width);
        CGContextAddLines(context, aPoints, 2);
        CGContextDrawPath(context, kCGPathStroke);
    }
    for (int i = 0; i < width; i += distance) {
        CGFloat cyan[4] = {
            0.9f,0.9f,
            0.9f,1.0f
        };
        CGContextSetStrokeColor(context, cyan);
        CGContextSetLineWidth(context, 1.0f);
        CGPoint aPoints[2];
        aPoints[0] = CGPointMake(0, i);
        aPoints[1] = CGPointMake(width, i);
        CGContextAddLines(context, aPoints, 2);
        CGContextDrawPath(context, kCGPathStroke);
    }
    
    UIImage * result = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return  result;
}

- (GLuint)generateDefaultTextureWithWidth:(GLint)width height:(GLint)height data:(GLvoid *)data
{
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
//    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
//    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, data);
    glBindTexture(GL_TEXTURE_2D, 0);
    return texture;
}

- (GLuint)generateDefaultFramebufferWithTargetTexture:(GLuint)texture
{
    GLuint framebuffer = 0;
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return framebuffer;
}

- (void)refreshContentTransform
{

    GLKMatrix4 composedTransform = GLKMatrix4Multiply(self.contentModeTransform, self.contentTransform);
    GLKProgram *program = [self.programs objectAtIndex:0];
    [program setValue:composedTransform.m forUniformNamed:@"u_contentTransform"];
}

- (GLKMatrix4)transformForAspectFitOrFill:(BOOL)fit
{
    CGSize contentSize = CGSizeRotate(self.contentSize, self.contentTransform);
    float imageAspect = contentSize.width/contentSize.height;
    float viewAspect = self.bounds.size.width/self.bounds.size.height;
    GLKMatrix4 transform;
    
    if ((imageAspect > viewAspect && fit) || (imageAspect < viewAspect && !fit)) {
        transform = GLKMatrix4MakeOrtho(-1, 1, -imageAspect/viewAspect, imageAspect/viewAspect, -1, 1);
    }
    else {
        transform = GLKMatrix4MakeOrtho(-viewAspect/imageAspect, viewAspect/imageAspect, -1, 1, -1, 1);
    }
    
    return transform;
}

- (GLKMatrix4)transformForPositionalContentMode:(UIViewContentMode)contentMode
{
    CGSize contentSize = CGSizeRotate(self.contentSize, self.contentTransform);
    float widthRatio = self.bounds.size.width/contentSize.width*self.contentScaleFactor;
    float heightRatio = self.bounds.size.height/contentSize.height*self.contentScaleFactor;
    GLKMatrix4 transform = GLKMatrix4Identity;
    
    switch (contentMode) {
        case UIViewContentModeCenter:
            transform = GLKMatrix4MakeOrtho(-widthRatio, widthRatio, -heightRatio, heightRatio, -1, 1);
            break;
            
        case UIViewContentModeBottom:
            transform = GLKMatrix4MakeOrtho(-widthRatio, widthRatio, -1, 2*heightRatio - 1, -1, 1);
            break;
            
        case UIViewContentModeTop:
            transform = GLKMatrix4MakeOrtho(-widthRatio, widthRatio, -2*heightRatio + 1, 1, -1, 1);
            break;
            
        case UIViewContentModeLeft:
            transform = GLKMatrix4MakeOrtho(-1, 2*widthRatio - 1, -heightRatio, heightRatio, -1, 1);
            break;
            
        case UIViewContentModeRight:
            transform = GLKMatrix4MakeOrtho(-2*widthRatio + 1, 1, -heightRatio, heightRatio, -1, 1);
            break;
            
        case UIViewContentModeTopLeft:
            transform = GLKMatrix4MakeOrtho(-1, 2*widthRatio - 1, -2*heightRatio + 1, 1, -1, 1);
            break;
            
        case UIViewContentModeTopRight:
            transform = GLKMatrix4MakeOrtho(-2*widthRatio + 1, 1, -2*heightRatio + 1, 1, -1, 1);
            break;
            
        case UIViewContentModeBottomLeft:
            transform = GLKMatrix4MakeOrtho(-1, 2*widthRatio - 1, -1, 2*heightRatio - 1, -1, 1);
            break;
            
        case UIViewContentModeBottomRight:
            transform = GLKMatrix4MakeOrtho(-2*widthRatio + 1, 1, -1, 2*heightRatio - 1, -1, 1);
            break;
            
        default:
            NSLog(@"Warning: Invalid contentMode given to transformForPositionalContentMode: %ld", (long)contentMode);
            break;
    }
    
    return transform;
}

- (BOOL)needsToCreateFramebuffer
{
    return !CGSizeEqualToSize(self.previousBounds.size, self.bounds.size);
}

- (BOOL)createFramebuffer
{
    [EAGLContext setCurrentContext:self.context];
    
    [self destroyFramebuffer];
    
    glGenFramebuffers(1, &_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, self.framebuffer);
    
    glGenRenderbuffers(1, &_colorRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, self.colorRenderbuffer);
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, self.colorRenderbuffer);
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_viewportWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_viewportHeight);
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Failed to create framebuffer: %x", status);
        return NO;
    }
    
    glBindRenderbuffer(GL_RENDERBUFFER, self.colorRenderbuffer);
    glViewport(0, 0, self.viewportWidth, self.viewportHeight);
    
    return YES;
}
- (void)creatProjMatrix {
    CGSize size = self.bounds.size;
    float height = size.height;
    float width = size.width;
    float f = 2.0 * atanf(0.5);
    float left = (3.0e-4f*(float)tan(f/2.0f)*height/width);
    float right = left * height / width;
    _projMatrix = GLKMatrix4MakeFrustum(-left, left, -right, right, 3.0e-4f, 100.0f);
    NSLog(@"%f,%f",left,right);
}
- (void)destroyFramebuffer
{
    glDeleteFramebuffers(1, &_framebuffer);
    self.framebuffer = 0;
    
    glDeleteRenderbuffers(1, &_colorRenderbuffer);
    self.colorRenderbuffer = 0;
}

- (void)refreshContentModeTransform
{
    switch (self.contentMode) {
        case UIViewContentModeScaleToFill:
            self.contentModeTransform = GLKMatrix4MakeOrtho(-1.f, 1.f, -1.f, 1.f, -1.f, 1.f);
            break;
            
        case UIViewContentModeScaleAspectFit:
            self.contentModeTransform = [self transformForAspectFitOrFill:YES];
            break;
            
        case UIViewContentModeScaleAspectFill:
            self.contentModeTransform = [self transformForAspectFitOrFill:NO];
            break;
            
        case UIViewContentModeCenter:
        case UIViewContentModeBottom:
        case UIViewContentModeTop:
        case UIViewContentModeLeft:
        case UIViewContentModeRight:
        case UIViewContentModeBottomLeft:
        case UIViewContentModeBottomRight:
        case UIViewContentModeTopLeft:
        case UIViewContentModeTopRight:
            self.contentModeTransform = [self transformForPositionalContentMode:self.contentMode];
            break;
            
        case UIViewContentModeRedraw:
            break;
            
        default:
            break;
    }
}

@end

#pragma mark - Functions

CGSize CGSizeRotate(CGSize size, GLKMatrix4 m)
{
    CGPoint p = CGPointMake(size.width/2, size.height/2);
    GLKVector4 v = GLKMatrix4MultiplyVector4(m, GLKVector4Make(p.x, p.y, 0, 1));
    return CGSizeMake(fabsf(v.x) * 2, fabsf(v.y) * 2);
}
