//
//  HMLauncherView_Private.h
//  HMLauncherView
//
//  Created by レンヂイ プラナタ on 6/12/12.
//  Copyright (c) 2012 Heiko Maass. All rights reserved.
//

#import <HMLauncherView/HMLauncherView.h>

@interface HMLauncherView () {
  BOOL editing;
}

- (void) enumeratePagesUsingBlock:(void (^) (NSUInteger page)) block;
- (void) enumerateIconsOfPage:(NSUInteger) page
                   usingBlock:(void (^) (HMLauncherIcon* icon, NSUInteger idx)) block;


- (CGFloat) calculateIconSpacer:(NSUInteger) numberOfColumns buttonSize:(CGSize) buttonSize;
- (NSInteger) calculateSpringOffset:(HMLauncherIcon*) icon;
- (void) executeScroll:(NSTimer*) timer;

- (void) didLongPressIcon:(UILongPressGestureRecognizer*) sender withEvent:(UIEvent*) event;
- (void) didTapIcon:(UITapGestureRecognizer*) sender;
- (void) longPressBegan:(HMLauncherIcon*) icon;
- (void) longPressMoved:(HMLauncherIcon*) icon
                toPoint:(CGPoint) newPosition;
- (void) longPressEnded:(HMLauncherIcon*) icon;
- (void)    performMove:(HMLauncherIcon *)icon
                toPoint:(CGPoint)newCenter
           launcherView:(HMLauncherView *)launcherView;
- (void) removeAllGestureRecognizers:(HMLauncherIcon*) icon;
- (UILongPressGestureRecognizer*) launcherIcon:(HMLauncherIcon*) icon
     addLongPressGestureRecognizerWithDuration:(CGFloat) duration
               requireGestureRecognizersToFail:(NSArray*) recognizersToFail;
- (UITapGestureRecognizer*) launcherIcon:(HMLauncherIcon*) icon
 addTapRecognizerWithNumberOfTapsRequred:(NSUInteger) tapsRequired;

- (NSIndexPath*) iconIndexForPoint:(CGPoint) center;
- (NSUInteger) pageIndexForPoint:(CGPoint) center;

- (void) makeIconDraggable:(HMLauncherIcon*) icon;
- (void) makeIconNonDraggable:(HMLauncherIcon*) icon
           sourceLauncherView:(HMLauncherView*) sourceLauncherView
           targetLauncherView:(HMLauncherView*) targetLauncherView
                   completion:(void (^) (void)) block;

- (void) startShaking;
- (void) stopShaking;

- (void) checkIfScrollingIsNeeded:(HMLauncherIcon*) launcherIcon;
- (void) startScrollTimerWithOffset:(NSInteger) offset;
- (void) stopScrollTimer;
- (void) executeScroll:(NSTimer *)timer;

- (void) updatePagerWithContentOffset:(CGPoint) contentOffset;
- (void) updateScrollViewContentSize;
- (void) updateDeleteButtons;
- (UIView*) keyView;

/**
 * Update the tapGestureRecogniser in each icon to enable/disable depending
 * on the current mode.
 */
- (void) updateTapGestureRecogniserIfNecessary;

/**
 * Enable/Disable every tapGestureRecogniser in a specified icon.
 *
 * @discussion  We should only have 1 tap recogniser on each icon, if we have more
 *              most likely that is an addition to the `default` one, for now
 *              we print the warning on the console.
 */
- (void) tapGestureRecogniserFor:(HMLauncherIcon *)icon enabled:(BOOL)enabled;

@property (nonatomic, retain) UIScrollView *scrollView;
@property (nonatomic, retain) UIPageControl *pageControl;
@property (nonatomic, assign) NSTimer *scrollTimer;
@property (nonatomic, assign) HMLauncherIcon *dragIcon;
@property (nonatomic, assign) HMLauncherIcon *closingIcon;

/**
 * Unused backgroundViews at the moment. Might be used by the dataSource
 * to get a reusable backgroundView.
 */
@property (nonatomic, retain) NSMutableSet *cachedBackgroundViews;

/**
 * Holds the reference to all backgroundViews used by the LauncherView.
 */
@property (nonatomic, retain) NSMutableArray *backgroundViews;

/**
 * This enables a customisation on the pageControl class used.
 * Could be set on the User-Defined runtime settings with xib
 * for ease-of-use.
 */
@property (nonatomic, retain) NSString *pageControlClassName;

/**
 * A boolean to indicate that the current targetIcon (draggedIcon)
 * is outside the boundaries of the HMLauncher
 */
@property (nonatomic, assign) BOOL targetIconIsOutside;

/**
 * The view used as the draggedIcon base.
 */
@property (nonatomic, strong) UIView *keyView;

@end
