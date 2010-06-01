//
//  ARMainController.m
//  iBetelgeuse
//
//  Copyright 2010 Finalist IT Group. All rights reserved.
//
//  This file is part of iBetelgeuse.
//  
//  iBetelgeuse is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//  
//  iBetelgeuse is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//  
//  You should have received a copy of the GNU General Public License
//  along with iBetelgeuse.  If not, see <http://www.gnu.org/licenses/>.
//

#import "ARMainController.h"
#import "ARDimension.h"
#import "AROverlay.h"
#import "AROverlayContainerView.h"
#import "AROverlayView.h"
#import "ARFeature.h"
#import "ARFeatureContainerView.h"
#import "ARFeatureView.h"
#import "ARAction.h"
#import "ARSpatialStateManager.h"
#import "ARWGS84.h"
#import "ARLocation.h"
#import "ARRadarView.h"
#import "ARAssetDataUser.h"
#import <QuartzCore/QuartzCore.h>


#define SCREEN_SIZE_X 320
#define SCREEN_SIZE_Y 480
#define CAMERA_CONTROLS_HEIGHT (53.)
#define CAMERA_VIEW_SCALE (SCREEN_SIZE_Y / (SCREEN_SIZE_Y - CAMERA_CONTROLS_HEIGHT))

// Fraction of the refresh rate of the screen at which to update
// Note: a frame interval of 2 results in 30 FPS and seems smooth enough
#define FRAME_INTERVAL 2


@interface ARMainController ()

@property(nonatomic, retain) NSURL *pendingDimensionURL;
@property(nonatomic, retain) ARDimension *dimension;
@property(nonatomic, readonly) UIImagePickerController *cameraViewController;
@property(nonatomic, readonly) ARFeatureContainerView *featureContainerView;
@property(nonatomic, readonly) AROverlayContainerView *overlayContainerView;
@property(nonatomic, readonly) ARRadarView *radarView;

@property(nonatomic, retain) CADisplayLink *displayLink;

@property(nonatomic, retain) ARDimensionRequest *dimensionRequest;
@property(nonatomic, readonly) ARAssetManager *assetManager;
@property(nonatomic, readonly) ARAssetManager *assetManagerIfAvailable;
@property(nonatomic, readonly) ARSpatialStateManager *spatialStateManager;
@property(nonatomic, retain) NSTimer *refreshTimer;
@property(nonatomic, getter=isRefreshingOnDistance) BOOL refreshingOnDistance;
@property(nonatomic, retain) ARLocation *refreshLocation;

- (UIImagePickerController *)cameraViewController;
- (void)createOverlayViews;
- (void)createFeatureViews;
- (void)updateFeatureViews;

- (void)setNeedsUpdate;
- (void)updateIfNeeded;

- (void)startDimensionRequestWithURL:(NSURL *)aURL type:(ARDimensionRequestType)type source:(NSString *)source;
- (void)startRefreshingOnTime;
- (void)stopRefreshingOnTime;
- (void)startRefreshingOnDistanceResetLocation:(BOOL)reset;
- (void)stopRefreshingOnDistance;

- (void)performAction:(ARAction *)action source:(NSString *)source;

@end


@implementation ARMainController

@synthesize pendingDimensionURL;
@synthesize dimension;
@synthesize featureContainerView;
@synthesize overlayContainerView;
@synthesize radarView;

@synthesize displayLink;

@synthesize dimensionRequest;
@synthesize refreshTimer;
@synthesize refreshingOnDistance;
@synthesize refreshLocation;

#pragma mark NSObject

- (id)init {
	return [self initWithURL:nil];
}

- (id)initWithURL:(NSURL *)aURL {
	if (self = [super init]) {
		pendingDimensionURL = [aURL retain];
		
		if (aURL) {
			DebugLog(@"Got dimension URL, waiting for location fix");
		}
	}
	return self;
}

- (void)dealloc {
	[pendingDimensionURL release];
	[dimension release];
	[cameraViewController release];
	
	[displayLink invalidate];
	[displayLink release];
	
	[dimensionRequest release];
	[assetManager release];
	[spatialStateManager release];
	[refreshTimer invalidate];
	[refreshTimer release];
	[refreshLocation release];
	
	[super dealloc];
}

#pragma mark UIViewController

- (void)loadView {
	[super loadView];
	UIView *view = [self view];
	
	// We want our view to be fully opaque for hit testing to work as expected
	[view setBackgroundColor:[UIColor blackColor]];
	
#if !TARGET_IPHONE_SIMULATOR
	[view addSubview:[[self cameraViewController] view]];
#endif

	// We are setting the feature container's origin to the center of the screen
	featureContainerView = [[ARFeatureContainerView alloc] init];
	[featureContainerView setCenter:CGPointMake(SCREEN_SIZE_X / 2., SCREEN_SIZE_Y / 2.)];
	[featureContainerView setBounds:CGRectMake(-SCREEN_SIZE_X / 2., -SCREEN_SIZE_Y / 2., SCREEN_SIZE_X, SCREEN_SIZE_Y)];
	[view addSubview:featureContainerView];
	[featureContainerView release];
	
	radarView = [[ARRadarView alloc] init];
	[radarView setFrame:CGRectMake(10, SCREEN_SIZE_Y - 100 - 10, 100, 100)];
	[view addSubview:radarView];
	[radarView release];
	
	overlayContainerView = [[AROverlayContainerView alloc] init];
	[overlayContainerView setFrame:CGRectMake(0, 0, SCREEN_SIZE_X, SCREEN_SIZE_Y)];
	[view addSubview:overlayContainerView];
	[overlayContainerView release];
}

- (void)viewDidUnload {
	[super viewDidUnload];
	
	[cameraViewController release];
	cameraViewController = nil;
	featureContainerView = nil;
	radarView = nil;
	overlayContainerView = nil;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
	[[self cameraViewController] viewWillAppear:animated];
	
	[[self spatialStateManager] startUpdating];

	// Use a display link to sync up with the screen, so that we don't update the screen more than necessary
	CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateWithDisplayLink:)];
	[link setFrameInterval:FRAME_INTERVAL];
	[self setDisplayLink:link];
	[link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	
	// Invalidate the screen by default
	[self setNeedsUpdate];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	
	[[self cameraViewController] viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	
	[[self cameraViewController] viewWillDisappear:animated];
	
	[[self spatialStateManager] stopUpdating];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	
	[[self cameraViewController] viewDidDisappear:animated];
	
	// This invalidates the display link
	[self setDisplayLink:nil];
}

#pragma mark CADisplayLink

- (void)updateWithDisplayLink:(CADisplayLink *)sender {
	// If the screen has been invalidated, update it
	[self updateIfNeeded];
}

#pragma mark ARDimensionRequestDelegate

- (void)dimensionRequest:(ARDimensionRequest *)request didFinishWithDimension:(ARDimension *)aDimension {
	// Save the dimension
	[self setDimension:aDimension];
	
	// Forget the dimension request
	[self setDimensionRequest:nil];

	// Cancel loading any assets before we start reloading them in the create... methods below
	[[self assetManagerIfAvailable] cancelLoadingAllAssets];
	
	[self createOverlayViews];
	[self createFeatureViews];
	
	[self startRefreshingOnTime];
	[self startRefreshingOnDistanceResetLocation:YES];
}

- (void)dimensionRequest:(ARDimensionRequest *)request didFailWithError:(NSError *)error {
	// Forget the dimension request
	[self setDimensionRequest:nil];

	[self startRefreshingOnTime];
	[self startRefreshingOnDistanceResetLocation:NO];
	
	UIAlertView *alert = [[UIAlertView alloc] init];
	[alert setTitle:NSLocalizedString(@"Could not update dimension", @"main controller alert title")];
	[alert setMessage:[error localizedDescription]];
	[alert addButtonWithTitle:NSLocalizedString(@"Close", @"main controller alert button")];
	[alert show];
	[alert release];
}

#pragma mark ARAssetManagerDelegate

- (void)assetManager:(ARAssetManager *)manager didLoadData:(NSData *)data forAsset:(ARAsset *)asset {
	// Find overlays that need this data
	// TODO: Refactor
	for (UIView *view in [overlayContainerView subviews]) {
		if ([view conformsToProtocol:@protocol(ARAssetDataUser)]) {
			id <ARAssetDataUser> user = (id <ARAssetDataUser>)view;
			if ([[user assetIdentifiersForNeededData] containsObject:[asset identifier]]) {
				[user useData:data forAssetIdentifier:[asset identifier]];
			}
		}
	}
	
	// Find features that need this data
	// TODO: Refactor
	for (UIView *view in [featureContainerView subviews]) {
		if ([view conformsToProtocol:@protocol(ARAssetDataUser)]) {
			id <ARAssetDataUser> user = (id <ARAssetDataUser>)view;
			if ([[user assetIdentifiersForNeededData] containsObject:[asset identifier]]) {
				[user useData:data forAssetIdentifier:[asset identifier]];
			}
		}
	}
}

- (void)assetManager:(ARAssetManager *)manager didFailWithError:(NSError *)error forAsset:(ARAsset *)asset {
	// TODO: What to do with the overlay/feature views?
}

#pragma mark ARSpatialStateManagerDelegate

- (void)spatialStateManagerDidUpdate:(ARSpatialStateManager *)manager {
	// Invalidate the screen, the display link will take care of actually updating the screen when needed
	[self setNeedsUpdate];
}

- (void)spatialStateManagerLocationDidUpdate:(ARSpatialStateManager *)manager {
	if ([manager location]) {
		[manager setEFToECEFSpaceOffset:[manager locationInECEFSpace]];
		
		// If we have a location fix, send a request for any pending URL
		if ([self pendingDimensionURL]) {
			[self startDimensionRequestWithURL:[self pendingDimensionURL] type:ARDimensionRequestTypeInit source:nil];
			[self setPendingDimensionURL:nil];
		}
		
		// Deal with the refresh location
		if ([self isRefreshingOnDistance]) {
			// If we don't have a refresh location yet, set it now
			if (![self refreshLocation]) {
				[self setRefreshLocation:[manager location]];
			}
			else if ([[manager location] straightLineDistanceToLocation:[self refreshLocation]] >= [dimension refreshDistance]) {
				[self startDimensionRequestWithURL:[[self dimension] refreshURL] type:ARDimensionRequestTypeDistanceRefresh source:nil];
				[self stopRefreshingOnDistance];
			}
		}
	}
}

#pragma mark NSTimerInvocation

- (void)refreshTimerDidFire:(NSTimer *)aTimer {
	[self startDimensionRequestWithURL:[[self dimension] refreshURL] type:ARDimensionRequestTypeTimeRefresh source:nil];
}

#pragma mark ARMainController

- (UIImagePickerController *)cameraViewController {
	// Lazily create camera view controller, if necessary
	if (cameraViewController == nil) {
#if !TARGET_IPHONE_SIMULATOR
		cameraViewController = [[UIImagePickerController alloc] init];
		[cameraViewController setSourceType:UIImagePickerControllerSourceTypeCamera];
		[cameraViewController setShowsCameraControls:NO];
		[cameraViewController setCameraViewTransform:CGAffineTransformTranslate(CGAffineTransformMakeScale(CAMERA_VIEW_SCALE, CAMERA_VIEW_SCALE), 0, CAMERA_CONTROLS_HEIGHT / 2)];
#endif
	}
	return cameraViewController;
}

- (void)setDisplayLink:(CADisplayLink *)aLink {
	if (displayLink != aLink) {
		// Remove the existing link from the runloop
		[displayLink invalidate];
		
		[displayLink release];
		displayLink = [aLink retain];
	}
}

- (ARAssetManager *)assetManager {
	if (assetManager == nil) {
		assetManager = [[ARAssetManager alloc] init];
		[assetManager setDelegate:self];
	}
	return assetManager;
}

- (ARAssetManager *)assetManagerIfAvailable {
	// This is an accessor that doesn't attempt to lazily create an asset manager
	return assetManager;
}

- (ARSpatialStateManager *)spatialStateManager {
	if (spatialStateManager == nil) {
		spatialStateManager = [[ARSpatialStateManager alloc] init];
		[spatialStateManager setDelegate:self];
	}
	return spatialStateManager;
}

- (void)setRefreshTimer:(NSTimer *)aTimer {
	if (refreshTimer != aTimer) {
		// Unschedule the existing timer from the runloop
		[refreshTimer invalidate];
		
		[refreshTimer release];
		refreshTimer = [aTimer retain];
	}
}

- (void)createOverlayViews {
	// Remove all existing overlay views
	UIView *view;
	while (view = [[overlayContainerView subviews] lastObject]) {
		[view removeFromSuperview];
	}
	
	for (AROverlay *overlay in [dimension overlays]) {
		AROverlayView *view = [AROverlayView viewForOverlay:overlay];
		[[view layer] setPosition:[overlay origin]];
		[overlayContainerView addSubview:view];
		
		// Register for events if necessary
		if ([overlay action]) {
			[view addTarget:self action:@selector(didTapOverlay:) forControlEvents:UIControlEventTouchUpInside];
		}
		
		// Start loading any needed asset data
		// TODO: Refactor this (see createFeatureViews)
		if ([view conformsToProtocol:@protocol(ARAssetDataUser)]) {
			id <ARAssetDataUser> user = (id <ARAssetDataUser>)view;
			for (NSString *identifier in [user assetIdentifiersForNeededData]) {
				ARAsset *asset = [[dimension assets] objectForKey:identifier];
				if (asset == nil) {
					DebugLog(@"Overlay view wants asset with non-existent identifier: %@", identifier);
				}
				else {
					[[self assetManager] startLoadingAsset:asset];
				}
			}
		}
	}
}

- (void)createFeatureViews {
	// Remove all existing feature views
	UIView *view;
	while (view = [[featureContainerView subviews] lastObject]) {
		[view removeFromSuperview];
	}
	
	for (ARFeature *feature in [dimension features]) {
		ARFeatureView *view = [ARFeatureView viewForFeature:feature];
		[featureContainerView addSubview:view];
		
		// Register for events if necessary
		if ([feature action]) {
			// Note: at this time, the controls are unable to determine correctly whether a touch was inside their bounds or not, so subscribe to either event
			[view addTarget:self action:@selector(didTapFeature:) forControlEvents:UIControlEventTouchUpInside];
			[view addTarget:self action:@selector(didTapFeature:) forControlEvents:UIControlEventTouchUpOutside];
		}
		
		// Start loading any needed asset data
		// TODO: Refactor this (see createOverlayViews)
		if ([view conformsToProtocol:@protocol(ARAssetDataUser)]) {
			id <ARAssetDataUser> user = (id <ARAssetDataUser>)view;
			for (NSString *identifier in [user assetIdentifiersForNeededData]) {
				ARAsset *asset = [[dimension assets] objectForKey:identifier];
				if (asset == nil) {
					DebugLog(@"Feature view wants asset with non-existent identifier: %@", identifier);
				}
				else {
					[[self assetManager] startLoadingAsset:asset];
				}
			}
		}
	}
	
	[radarView setFeatures:[dimension features]];
	
	[self updateFeatureViews];
}

- (void)updateFeatureViews {
	[featureContainerView updateWithSpatialState:spatialStateManager usingRelativeAltitude:[dimension relativeAltitude]];
	[radarView updateWithSpatialState:spatialStateManager usingRelativeAltitude:[dimension relativeAltitude]];
}

- (void)setNeedsUpdate {
	needsUpdate = YES;
}

- (void)updateIfNeeded {
	if (needsUpdate) {
		needsUpdate = NO;
		
		[self updateFeatureViews];
	}
}

- (void)startDimensionRequestWithURL:(NSURL *)aURL type:(ARDimensionRequestType)type source:(NSString *)source {
	NSAssert(aURL, @"Expected non-nil URL.");
	
	// Cancel loading any assets
	[[self assetManagerIfAvailable] cancelLoadingAllAssets];
	
	// Make sure to kill any timer, since we don't want it firing when we're already refreshing
	[self stopRefreshingOnTime];
	[self stopRefreshingOnDistance];

	ARDimensionRequest *request = [[ARDimensionRequest alloc] initWithURL:aURL location:[[self spatialStateManager] location] type:type];
	[request setSource:source];
	[request setDelegate:self];
	[self setDimensionRequest:request];
	[request release];

	[request start];
}

- (void)startRefreshingOnTime {
	if (![[self dimension] refreshURL] || [[self dimension] refreshTime] == ARDimensionRefreshTimeInfinite) {
		[self setRefreshTimer:nil];
		
		DebugLog(@"Dimension refresh timer not scheduled");
	}
	else {
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:[[self dimension] refreshTime] target:self selector:@selector(refreshTimerDidFire:) userInfo:nil repeats:NO];
		[self setRefreshTimer:timer];
		
		DebugLog(@"Scheduling dimension refresh timer with timeout %fs", [[self dimension] refreshTime]);
	}
}

- (void)stopRefreshingOnTime {
	[self setRefreshTimer:nil];
}

- (void)startRefreshingOnDistanceResetLocation:(BOOL)reset {
	if (![[self dimension] refreshURL] || [[self dimension] refreshDistance] == ARDimensionRefreshDistanceInfinite) {
		[self setRefreshingOnDistance:NO];
	}
	else {
		[self setRefreshingOnDistance:YES];
		
		if (reset) {
			[self setRefreshLocation:[[self spatialStateManager] location]];
		}
	}
}

- (void)stopRefreshingOnDistance {
	[self setRefreshingOnDistance:NO];
}

- (void)didTapOverlay:(AROverlayView *)view {
	AROverlay *overlay = [view overlay];
	[self performAction:[overlay action] source:[overlay identifier]];
}

- (void)didTapFeature:(ARFeatureView *)view {
	ARFeature *feature = [view feature];
	[self performAction:[feature action] source:[feature identifier]];
}

- (void)performAction:(ARAction *)action source:(NSString *)source {
	switch ([action type]) {
		case ARActionTypeRefresh:
			[self startDimensionRequestWithURL:[[self dimension] refreshURL] type:ARDimensionRequestTypeActionRefresh source:source];
			break;
			
		case ARActionTypeDimension:
			NSAssert([action URL] != nil, @"Expected non-nil URL.");
			[self startDimensionRequestWithURL:[action URL] type:ARDimensionRequestTypeInit source:nil];
			break;
			
		case ARActionTypeURL:
			NSAssert([action URL] != nil, @"Expected non-nil URL.");
			[[UIApplication sharedApplication] openURL:[action URL]];
			break;
			
		default:
			DebugLog(@"Unrecognized action type %d", [action type]);
			break;
	}
}

@end
