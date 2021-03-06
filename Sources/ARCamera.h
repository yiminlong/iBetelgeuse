//
//  ARCamera.h
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

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>


/**
 * Class that provides information about a camera.
 */
@interface ARCamera : NSObject {
@private
	BOOL physical;
	CGFloat focalLength;
	CGSize imagePlaneSize;
	
	CGFloat distanceToViewPlane;
	CGFloat angleOfView;
	CATransform3D perspectiveTransform;
}

#if TARGET_OS_IPHONE
/**
 * Returns the shared instance that represents the camera of the current device. For devices without a camera, a virtual camera is returned that corresponds to looking through the device at arm's length. For devices with more than one camera, the most appropriate camera is returned (e.g. the back-facing camera on an iPhone).
 */
+ (ARCamera *)currentCamera;
#endif

/**
 * Initializes the receiver with the given properties.
 *
 * @param focalLength The focal length of the camera lens in meters. Must be strictly positive.
 * @param imagePlaneSize The size of the camera sensor in meters. Must be strictly positive.
 * @param physical Whether the values given correspond to an actual physical camera.
 *
 * @return The receiver.
 */
- (id)initWithFocalLength:(CGFloat)focalLength imagePlaneSize:(CGSize)imagePlaneSize physical:(BOOL)physical;

/**
 * Flag indicating whether the receiver represents a physical camera, i.e. whether the current device has an actual camera.
 */
@property(nonatomic, readonly, getter=isPhysical) BOOL physical;

/**
 * Focal length of the camera in meters.
 */
@property(nonatomic, readonly) CGFloat focalLength;

/**
 * Dimensions of the image plane (camera sensor) in meters.
 */
@property(nonatomic, readonly) CGSize imagePlaneSize;

/**
 * The distance to the view plane in logical units. A view plane of [-1,1]x[-1,1] is assumed.
 */
@property(nonatomic, readonly) CGFloat distanceToViewPlane;

/**
 * The largest angle of view in radians given the receiver's focal length and image plane.
 */
@property(nonatomic, readonly) CGFloat angleOfView;

/**
 * A perspective transform that corresponds to the receiver's focal length and image plane size. A view plane of [-1,1]x[-1,1] located in the -z direction is assumed. If the image plane is not square, the view plane is projected on the smallest square that encloses the image plane.
 */
@property(nonatomic, readonly) CATransform3D perspectiveTransform;

@end
