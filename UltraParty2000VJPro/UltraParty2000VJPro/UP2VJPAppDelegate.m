//
//  UP2VJPAppDelegate.m
//  UltraParty2000VJPro
//
//  Created by vade on 4/3/14.
//  Copyright (c) 2014 Ultravisual. All rights reserved.
//

#import "UP2VJPAppDelegate.h"
#import <OpenGL/OpenGL.h>
#import <Quartz/Quartz.h>
#import <CoreVideo/CoreVideo.h>

#import <OpenGL/CGLMacro.h>

@interface UP2VJPAppDelegate ()
@property (atomic, readwrite, strong) NSOpenGLContext* context;
@property (atomic, readwrite, strong) NSOpenGLPixelFormat* pixelFormat;
@property (atomic, readwrite, strong) QCComposition* composition;
@property (atomic, readwrite, assign) CVDisplayLinkRef displayLink;
@property (atomic, readwrite, assign) id savedInputValues;

// UI
@property (nonatomic, readwrite, strong) IBOutlet NSView* view;
@property (nonatomic, readwrite, strong) IBOutlet QCCompositionParameterView* parameterView;


// Only accessed on CVDisplaylink thread
// QCRenderer as per API contract. Init, use, release on same thread or else.
@property (nonatomic, readwrite, strong) QCRenderer* renderer;
@property (nonatomic, readwrite, assign) NSTimeInterval	startTime;

- (CVReturn)displayLinkRenderCallback:(const CVTimeStamp *)timeStamp;

@end

#pragma mark - Display Link Callback

CVReturn MyDisplayLinkCallback(CVDisplayLinkRef displayLink,const CVTimeStamp *inNow,const CVTimeStamp *inOutputTime,CVOptionFlags flagsIn,CVOptionFlags *flagsOut,void *displayLinkContext)
{
	CVReturn error = [(__bridge UP2VJPAppDelegate*) displayLinkContext displayLinkRenderCallback:inOutputTime];
	return error;
}


@implementation UP2VJPAppDelegate

#pragma mark - Setup

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSString* jsonPlugin = [[NSBundle mainBundle] builtInPlugInsPath];
	jsonPlugin = [jsonPlugin stringByAppendingPathComponent:@"QCJSON.plugin"];
	
	if(![QCPlugIn loadPlugInAtPath:jsonPlugin])
	{
		NSLog(@"WHAT THE SHIT");
	}
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateRenderView:) name:NSViewFrameDidChangeNotification object:self.view];
	
	id propertyList = [[NSUserDefaults standardUserDefaults] valueForKey:@"UP2VJPSavedInputValues"];
	
	if(propertyList)
		self.savedInputValues = propertyList;
	
	self.pixelFormat = [self selectPixelFormat];
	if([self setupOpenGLContext:self.pixelFormat])
	{
		[self loadComposition];
		[self initDisplayLink];
	}
	else
	{
		// Terminate app, whoops, no OpenGL. Fuck.
	}
}

- (void) applicationWillTerminate:(NSNotification*)aNotification
{
	CVDisplayLinkStop(self.displayLink);
	CVDisplayLinkRelease(self.displayLink);
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:self.view];
		
	//Destroy the OpenGL context
	[self.context clearDrawable];
	
	[self.parameterView setCompositionRenderer:nil];
	
	// Save our input keys for next time.
	id propertyList = [self.renderer propertyListFromInputValues];
	
	[[NSUserDefaults standardUserDefaults] setValue:propertyList forKey:@"UP2VJPSavedInputValues"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSOpenGLPixelFormat*) selectPixelFormat
{
	// open gl initting
	NSOpenGLPixelFormatAttribute attributes[] =
	{
		NSOpenGLPFADoubleBuffer,
		NSOpenGLPFAAllowOfflineRenderers,
		NSOpenGLPFAAcceleratedCompute,
		NSOpenGLPFAAccelerated,
		NSOpenGLPFADepthSize, 24,
		NSOpenGLPFAMultisample,
		NSOpenGLPFASampleBuffers, 1,
		NSOpenGLPFASamples, 4,
		(NSOpenGLPixelFormatAttribute) 0
	};
	
	NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
	
	if(format)
		return format;
		
	else
	{
		NSOpenGLPixelFormatAttribute attributes[] =
		{
			NSOpenGLPFADoubleBuffer,
			NSOpenGLPFAAccelerated,
			NSOpenGLPFAAllowOfflineRenderers,
			NSOpenGLPFAAcceleratedCompute,
			NSOpenGLPFADepthSize, 24,
			(NSOpenGLPixelFormatAttribute) 0
		};
		
		format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
	}
	
	if(format)
		return format;
	
	return nil;
}

- (BOOL) setupOpenGLContext:(NSOpenGLPixelFormat*)format
{
	self.context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
	
	[self.context setView:self.view];

	GLint value = 1;
	[self.context setValues:&value forParameter:NSOpenGLCPSwapInterval];

	return (self.context) ? TRUE : FALSE;
}

- (void) loadComposition
{
	NSString* compositionFilePath = [[NSBundle mainBundle] pathForResource:@"UltraParty2000VJPro" ofType:@"qtz"];
	
	if(compositionFilePath)
		self.composition = [QCComposition compositionWithFile:compositionFilePath];
	else
	{
		// Terminate app, whoops, no Composition. Fuck.
	}

}

- (void) initDisplayLink
{
    CVReturn            error = kCVReturnSuccess;

    error = CVDisplayLinkCreateWithActiveCGDisplays(&(_displayLink));
    if(error)
    {
        NSLog(@"DisplayLink created with error:%d", error);
        self.displayLink = NULL;
        return;
    }
	
    error = CVDisplayLinkSetOutputCallback(self.displayLink,MyDisplayLinkCallback, (__bridge void *)(self));
	if(error)
    {
        NSLog(@"DisplayLink could not link to callback, error:%d", error);
        self.displayLink = NULL;
        return;
    }
	
	CVDisplayLinkStart(self.displayLink);
	
	if(!CVDisplayLinkIsRunning(self.displayLink))
	{
		NSLog(@"DisplayLink is not running - it should be. ");
	}
}

#pragma mark - Rendering

- (CVReturn)displayLinkRenderCallback:(const CVTimeStamp *)timeStamp
{
    CVReturn rv = kCVReturnError;
	@autoreleasepool
    {
		[self renderWithEvent:[NSApp currentEvent]];
		rv = kCVReturnSuccess;
    }
    return rv;
}

- (void) updateRenderView:(NSNotification *) notification
{
	CVDisplayLinkStop(self.displayLink);
	
	CGLContextObj cgl_ctx = [self.context CGLContextObj];
	CGLLockContext(cgl_ctx);
	
	NSRect mainRenderViewFrame = [self.view frame];
	
	glViewport(0, 0, mainRenderViewFrame.size.width, mainRenderViewFrame.size.height);
	glClear(GL_COLOR_BUFFER_BIT);
	
	//[self.context flushBuffer];
	[self.context update];

	CGLUnlockContext(cgl_ctx);

	CVDisplayLinkStart(self.displayLink);
}


- (void) renderWithEvent:(NSEvent*)event
{
	// Lazy load our QCRenderer on our CVDisplaylink thread, as per API contract
	if(!self.renderer)
	{
		CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		
		self.renderer = [[QCRenderer alloc] initWithCGLContext:self.context.CGLContextObj
												   pixelFormat:self.pixelFormat.CGLPixelFormatObj
													colorSpace:colorspace
												   composition:self.composition];
		CGColorSpaceRelease(colorspace);
		
		dispatch_async(dispatch_get_main_queue(), ^
		{
			[self.parameterView setCompositionRenderer:self.renderer];
		});
	}
	
	NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];
	NSPoint mouseLocation;
	NSDictionary* arguments;
	
	//Let's compute our local time
	if(self.startTime == 0)
	{
		self.startTime = time;
		time = 0;
	}
	else
		time -= _startTime;
	
	NSWindow* renderWindow = self.window;
	mouseLocation = [renderWindow mouseLocationOutsideOfEventStream];
	mouseLocation.x /= renderWindow.frame.size.width;
	mouseLocation.y /= renderWindow.frame.size.height;
	if(event)
	{
		arguments = @{QCRendererMouseLocationKey : [NSValue valueWithPoint:mouseLocation],
					  QCRendererEventKey : event};
	}
	else
		arguments = @{QCRendererMouseLocationKey : [NSValue valueWithPoint:mouseLocation]};

	//Render a frame
	CGLContextObj cgl_ctx = [self.context CGLContextObj];
	CGLLockContext(cgl_ctx);
	
	if(![self.renderer renderAtTime:time arguments:arguments])
		NSLog(@"Rendering failed at time %.3fs", time);
	
	//Flush the OpenGL context to display the frame on screen
	[self.context flushBuffer];
	CGLUnlockContext(cgl_ctx);
}

#pragma mark - Paramterization

- (IBAction) setCollectionUUID:(id)sender
{
	[self.renderer setValue:[sender stringValue] forInputKey:@"Collection_UUID"];
}

@end
