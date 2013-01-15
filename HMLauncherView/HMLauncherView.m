//
// Copyright 2012 Heiko Maaß (mail@heikomaass.de)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "HMLauncherView.h"
#import "HMLauncherItem.h"
#import "HMLauncherView_Private.h"

static const CGFloat kShakeRadians = 3.0f;
static const NSTimeInterval kShakeTime = 0.15;
static const CGFloat kScrollingFraction = 0.25f;
static const NSTimeInterval kScrollTimerInterval = 0.7;
static const CGFloat kLongPressDuration = 0.3;
static const CGFloat kLayoutIconDuration = 0.35;

@implementation NSIndexPath(LauncherPath)
- (NSUInteger) pageIndex {
    return [self indexAtPosition:0];
}

- (NSUInteger) iconIndex {
    return [self indexAtPosition:1];    
}
@end

@implementation HMLauncherView
@synthesize dataSource;
@synthesize delegate;
@synthesize pageControl;
@synthesize scrollView;
@synthesize scrollTimer;
@synthesize dragIcon;
@synthesize closingIcon;
@synthesize shouldRemoveWhenDraggedOutside;
@synthesize shouldReceiveTapWhileEditing;
@synthesize shouldLayoutDragButton;
@synthesize targetIconIsOutside;
@synthesize targetPath;
@synthesize persistKey;
@synthesize keyView = _keyView;

@synthesize pageControlClassName = _pageControlClassName;

// Related to backgroundViews
@synthesize backgroundViews, cachedBackgroundViews;

// Some UI related parameters
@synthesize shakeRadian;
@synthesize shakeTime;
@synthesize scrollTimerInterval;
@synthesize longPressDuration;

// Some dragged-icon behavior
@synthesize draggedIconMagnification;
@synthesize draggedIconOpacity;
@synthesize draggedIconOffset;

- (void) reloadData {
    self.dragIcon = nil;
    self.targetPath = nil;
    NSUInteger numberOfPages = [self.dataSource numberOfPagesInLauncherView:self];
    [self.pageControl setNumberOfPages:numberOfPages];
    
    // Remove all previous stuff from ScrollView (this includes any background view if there is one)
    [[scrollView subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIView *subview = obj;
        [subview removeFromSuperview];
    }];
  
    // Toss away the background view that is currently being hold
    for (UIView *view in self.backgroundViews) {
        [self.cachedBackgroundViews addObject:view];
    }
    [self.backgroundViews removeAllObjects];
  
    //  Set whether the scrollView should bounce.
    if ([self.dataSource respondsToSelector:@selector(launcherViewShouldBounce:)]) {
      self.scrollView.bounces = [self.dataSource launcherViewShouldBounce:self];
    }
  
    // Add all buttons to ScrollView
    [self enumeratePagesUsingBlock:^(NSUInteger page) {
        // When we are reloading the page, try to add background view if needed.
        [self addBackgroundViewIfNescessaryToPage:page];
        [self enumerateIconsOfPage:page usingBlock:^(HMLauncherIcon *icon, NSUInteger idx) {
            [self removeAllGestureRecognizers:icon];
            [self addIcon:icon];
        }];
    }];
    [self setNeedsLayout];
}

- (void) addIcon:(HMLauncherIcon*) icon {
    NSAssert([self.dataSource launcherView:self contains:icon] == YES, @"Model is inconsistent with view");
  
    // Then add the required gesture recogniser.
    UITapGestureRecognizer *tapGestureRecognizer = nil;
    if (self.editing == NO && icon.canBeTapped) {
        tapGestureRecognizer = [self launcherIcon:icon addTapRecognizerWithNumberOfTapsRequred:1];
    }
  
    if (self.editing == NO && icon.canBeDragged) {
        UIGestureRecognizer *shorterLongPressGesture = [self launcherIcon:icon addLongPressGestureRecognizerWithDuration:0.1 requireGestureRecognizerToFail:nil];
        shorterLongPressGesture.delegate = self;
        [self launcherIcon:icon addLongPressGestureRecognizerWithDuration:self.longPressDuration requireGestureRecognizerToFail:shorterLongPressGesture];
    }
  
    [self.scrollView addSubview:icon];
}

- (void) removeIcon:(HMLauncherIcon *)icon {
    [icon removeFromSuperview];
    [self removeAllGestureRecognizers:icon];
}

- (void) removeIconAnimated:(HMLauncherIcon*) icon  
                 completion:(void (^)(void))block {
    NSAssert([self.dataSource launcherView:self contains:icon] == NO, @"Model is inconsistent with view");    
    [UIView animateWithDuration:0.25 animations:^{
        icon.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        NSLog(@"removeIconAnimated finished");
        [self removeIcon:icon];
        block();
    }];
}

- (BOOL) editing {
    return editing;
}

- (UIView *) keyView {
    if (_keyView == nil) {
        UIWindow *w = [self window];
      
        // Add it as a subview.
        UIView *vw = [[UIView alloc] initWithFrame:w.frame];
        vw.backgroundColor = [UIColor clearColor];
        vw.userInteractionEnabled = NO;
        [w addSubview:vw];
      
        // Assign it.
        self.keyView = vw;
    }
  
    // And dont forget to bring us to the most-top layer.
    [_keyView.superview bringSubviewToFront:_keyView];
    return _keyView;
}

- (CGSize) calculateIconSpacerForTotalColumns:(NSUInteger) totalColumns totalRows:(NSUInteger) totalRows buttonSize:(CGSize) buttonSize {
    // If the dataSource wants a custom implementation.
    if ([self.dataSource respondsToSelector:@selector(buttonSpacerInLauncherView:)])
    {
      return [self.dataSource buttonSpacerInLauncherView:self];
    }
  
    // Otherwise, try to be smart and divide it even-ly
    CGFloat contentWidth = CGRectGetWidth(self.bounds);
    CGFloat contentHeight = CGRectGetHeight(self.bounds);
  
    CGFloat allIconsWidth = totalColumns * buttonSize.width;
    CGFloat allIconsHeight = totalRows * buttonSize.height;
  
    CGFloat iconXSpacer = (contentWidth - allIconsWidth) / (totalColumns - 1);
    CGFloat iconYSpacer = (contentHeight - allIconsHeight) / (totalRows - 1);
  
    return (CGSize){ iconXSpacer, iconYSpacer };
}

- (void) layoutSubviews {
    if (self.pageControlLayoutBlock != NULL) {
      self.pageControlLayoutBlock(self, self.pageControl);
    }
  
    CGRect scrollViewFrame = self.bounds;
    if (!CGRectEqualToRect(scrollViewFrame, self.scrollView.frame)) {
        // see http://openradar.appspot.com/8045239
        self.scrollView.frame = scrollViewFrame;       
    }
    [self updateScrollViewContentSize];
  
    if (self.editing == NO) {
      [self layoutIcons];
    }
}

- (void) layoutIconsAnimated {
    [UIView animateWithDuration:kLayoutIconDuration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         [self layoutIcons];
                     }            
                     completion:^(BOOL finished) {
                     }];
}

- (void) layoutIcons {
    BOOL targetSpacerNeeded = self.targetPath != nil;
    NSAssert((self.shouldLayoutDragButton && targetSpacerNeeded) == NO, 
             @"targetPath cannot be set, when dragButton should be layouted");
    
    NSUInteger numberOfColumns = [self.dataSource numberOfColumnsInLauncherView:self]; 
    NSUInteger numberOfRows    = [self.dataSource numberOfRowsInLauncherView:self];
    CGSize  iconSize           = [self.dataSource buttonDimensionsInLauncherView:self];
    CGSize iconSpacer         = [self calculateIconSpacerForTotalColumns:numberOfColumns totalRows:numberOfRows buttonSize:iconSize];
    
    CGFloat pageWidth = CGRectGetWidth(self.scrollView.bounds);
    
    __block NSInteger columnIndexForNextPage = 0;
    
    [self enumeratePagesUsingBlock:^(NSUInteger pageIndex) {
        CGFloat pageX   = pageWidth * pageIndex;
        NSInteger iconY = 0;
        CGFloat iconXStart = pageX;
        NSInteger currentColumnIndex = columnIndexForNextPage;
        columnIndexForNextPage = 0;
        NSInteger currentRowIndex = 0;
        
        NSMutableArray *iconsWithSpacer = [NSMutableArray arrayWithCapacity:(numberOfColumns * numberOfRows) + 1];
        [self enumerateIconsOfPage:pageIndex usingBlock:^(HMLauncherIcon *icon, NSUInteger iconIndex) {
            if (icon != dragIcon || (icon == dragIcon && shouldLayoutDragButton)) {
                [iconsWithSpacer addObject:icon];
            } 
        }];
        
        if (targetSpacerNeeded) {
            if ([self.targetPath pageIndex] == pageIndex) {
                NSInteger iconIndex = [self.targetPath iconIndex];
                if ([iconsWithSpacer count] > 0 && iconIndex < [iconsWithSpacer count]) {
                    [iconsWithSpacer insertObject:[NSNull null] atIndex:iconIndex];
                } else {
                    [iconsWithSpacer addObject:[NSNull null]];
                } 
            }
        }
      
        for (NSObject *iconObj in iconsWithSpacer) {
            if (currentColumnIndex == numberOfColumns) {
                iconY += iconSize.height + iconSpacer.height;
                currentColumnIndex = 0;
                currentRowIndex++;
            }
            
            if (currentRowIndex == numberOfRows) {
                currentRowIndex = 0;
                iconXStart += pageWidth;
                iconY = 0;
                columnIndexForNextPage++;
            }
            
            if ([iconObj isKindOfClass:[HMLauncherIcon class]]) {
                HMLauncherIcon *icon = (HMLauncherIcon*) iconObj;
                CGFloat iconX = iconXStart + (currentColumnIndex * (iconSize.width + iconSpacer.width));
                [icon setBounds:CGRectMake(0, 0, iconSize.width, iconSize.height)];
                CGPoint iconCenterInScrollView = CGPointMake(iconX + iconSize.width / 2, iconY + iconSize.height / 2);
                if (icon != dragIcon) {
                    [icon setCenter:iconCenterInScrollView];
                } else if (shouldLayoutDragButton) {
                    CGPoint iconCenterInKeyView = [self.scrollView convertPoint:iconCenterInScrollView 
                                                                         toView:icon.superview];
                    [icon setCenter:iconCenterInKeyView];           
                }
            }
            currentColumnIndex++;  
        }; 
    }];
}

- (void) removeAllGestureRecognizers:(HMLauncherIcon*) icon {
    NSArray *gestureRecognizers = [[icon gestureRecognizers] copy];
    for (UIGestureRecognizer *recognizer in gestureRecognizers) {
        [icon removeGestureRecognizer:recognizer];
    }
    [gestureRecognizers release];
}

- (UILongPressGestureRecognizer*) launcherIcon:(HMLauncherIcon*) icon 
     addLongPressGestureRecognizerWithDuration:(CGFloat) duration 
                requireGestureRecognizerToFail:(UIGestureRecognizer*) recognizerToFail {
  
    // LongPress gesture
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self 
                                                                                            action:@selector(didLongPressIcon:withEvent:)];
  
    [longPress setMinimumPressDuration:duration];
    if (recognizerToFail) {
        [longPress requireGestureRecognizerToFail:recognizerToFail];
    }
  
    [icon addGestureRecognizer:longPress];
    return [longPress autorelease];
}

- (UITapGestureRecognizer*) launcherIcon:(HMLauncherIcon*) icon addTapRecognizerWithNumberOfTapsRequred:(NSUInteger) tapsRequired {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapIcon:)];
    [tap setNumberOfTapsRequired:tapsRequired];
    [tap setDelegate:self];
    [tap setCancelsTouchesInView:icon.tapRecognizerShouldCancelTouch];
    [icon addGestureRecognizer:tap];
    return [tap autorelease];
}

# pragma mark - Background View related
- (UIView *)reusableBackgroundView {
  //Quick return if we have nothing.
  if (self.cachedBackgroundViews.count == 0) {
    return nil;
  }
  
  // Get one of the reusable background view from our cache and make sure to
  // remove it from the cache.
  UIView *reusableBGView = [[[self cachedBackgroundViews] anyObject] retain];
  [[self cachedBackgroundViews] removeObject:reusableBGView];
  return [reusableBGView autorelease];
}

- (void)addBackgroundViewIfNescessaryToPage:(NSUInteger)page {
  // Only do this if the dataSource is implementing it.
  if ([self.dataSource respondsToSelector:@selector(launcherView:backgroundForPage:)]) {
    // Grab the backgroundView from the datasource.
    UIView *view = [self.dataSource launcherView:self backgroundForPage:page];
    CGRect frame = view.frame;
    frame.origin.x = frame.origin.x + CGRectGetWidth(self.scrollView.bounds)*page;
    view.frame = frame;
    
    // Add the background to the subview.
    [self.scrollView addSubview:view];
    
    // Record that the backgroundView is currently used.
    self.backgroundViews[self.backgroundViews.count] = view;
  }
}

# pragma mark - Gesture Actions
- (void) didTapIcon:(UITapGestureRecognizer*) sender {
    HMLauncherIcon *launcherIcon = (HMLauncherIcon*) sender.view;
  
    CGPoint locationInView = [sender locationOfTouch:0 inView:launcherIcon];
    if (self.editing && [launcherIcon hitCloseButton:locationInView]) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"HMLauncherView_ConfirmDelete", nil), launcherIcon.launcherItem.titleText];
        
      
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"HMLauncherView_Alert", nil) 
                                                            message:message
                                                           delegate:self 
                                                  cancelButtonTitle:NSLocalizedString(@"HMLauncherView_Cancel",nil)
                                                  otherButtonTitles:NSLocalizedString(@"HMLauncherView_Ok", nil), nil];
        self.closingIcon = launcherIcon;
        [alertView show];
        [alertView release];
    } else {
        if ([self.delegate respondsToSelector:@selector(launcherView:didTapLauncherIcon:)]) {
            [self.delegate launcherView:self didTapLauncherIcon:launcherIcon];            
        }
    }
}

- (void) didLongPressIcon:(UILongPressGestureRecognizer*) sender withEvent:(UIEvent*) event {
    if ([self.scrollView isDragging]) {
        return;
    }
    HMLauncherIcon *icon = (HMLauncherIcon*) sender.view;
    if (sender.state == UIGestureRecognizerStateBegan) {
        [self longPressBegan:icon];
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        CGPoint iconPoint = [sender locationInView:self];
        [self longPressMoved:icon toPoint:iconPoint];
    } else if (sender.state == UIGestureRecognizerStateEnded) {
        [self longPressEnded:icon ];
    } else if (sender.state == UIGestureRecognizerStateCancelled) {
        [self longPressEnded:icon];
    }
}

- (void) longPressBegan:(HMLauncherIcon*) icon {
    if (!self.editing) {
        [self startEditing];
    }
    NSIndexPath *originIndexPath = [self iconIndexForPoint:icon.center];
    [icon setOriginIndexPath:originIndexPath];
    [self makeIconDraggable:icon];
}

- (void) performMove:(HMLauncherIcon *)icon toPoint:(CGPoint)newCenter launcherView:(HMLauncherView *)launcherView {
  
    BOOL isCurrentlyOutside = (CGRectContainsPoint(self.frame, newCenter) == NO);
    NSIndexPath *previousIndexPath = nil;
    NSIndexPath *indexPath = nil;
  
    // Get the newCenter location on the key view.
    CGPoint newCenterOnKeyView = [icon.superview convertPoint:newCenter fromView:self];
  
    // Calculate the previous position
    CGPoint previousIconPositionInTarget = [launcherView.scrollView convertPoint:icon.center
                                                                        fromView:icon.superview];
    previousIndexPath = [launcherView iconIndexForPoint:previousIconPositionInTarget];
    
  
    // And the new position
    CGPoint currentIconPositionInTarget = [launcherView.scrollView convertPoint:newCenterOnKeyView
                                                                       fromView:icon.superview];
    indexPath = [launcherView iconIndexForPoint:currentIconPositionInTarget];
  
    // Calibrate the previous and the current indexPath if
    // The icon was previously on the outside and it is inside now
    // The icon was inside and it is outside now
    // It stays outside and the `shouldRemove` flag is YES.
    if (self.targetIconIsOutside && isCurrentlyOutside == NO) {
        // going inside, make previousIndexPath nil
        self.targetIconIsOutside = NO;
        previousIndexPath = nil;
    } else if (self.targetIconIsOutside == NO && isCurrentlyOutside && self.shouldRemoveWhenDraggedOutside) {
        // going outside, make indexPath nil
        self.targetIconIsOutside = YES;
        indexPath = nil;
    } else if (isCurrentlyOutside && self.shouldRemoveWhenDraggedOutside){
        // stays outside, make both nil.
        indexPath = nil;
        previousIndexPath = nil;
    }
  
    // Move the icon itself.
    icon.center = newCenterOnKeyView;
  
    // Call the delegate if there is a chnge in the indexPath and both of them are not nil.
    if (![previousIndexPath isEqual:indexPath] && (previousIndexPath || indexPath )) {
        if ([self.delegate respondsToSelector:@selector(launcherView:willMoveIcon:fromIndex:toIndex:)]) {
            [self.delegate launcherView:self willMoveIcon:icon fromIndex:previousIndexPath toIndex:indexPath];
        }
    }
  
    [launcherView setTargetPath:indexPath];
    [launcherView setDragIcon:icon];
}

- (void) longPressMoved:(HMLauncherIcon*) icon toPoint:(CGPoint) newCenter {
    NSAssert(icon.originIndexPath != nil, @"originIndexPath must be set");
    HMLauncherView *launcherView = [self.delegate targetLauncherViewForIcon:icon];
    
    [self performMove:icon toPoint:newCenter launcherView:launcherView];
    [launcherView checkIfScrollingIsNeeded:icon];
    [launcherView layoutIconsAnimated];
}

- (void) longPressEnded:(HMLauncherIcon*) icon {
    HMLauncherView *targetLauncherView = [self.delegate targetLauncherViewForIcon:icon];
    if (targetLauncherView == nil && self.shouldRemoveWhenDraggedOutside == NO) {
        targetLauncherView = self;
        self.targetPath = nil;
    }
  
    if (targetLauncherView || self.shouldRemoveWhenDraggedOutside) {
        NSAssert((self.shouldRemoveWhenDraggedOutside || targetLauncherView.dragIcon == self.dragIcon), @"launcherView.dragIcon != self.dragIcon");
        [targetLauncherView stopScrollTimer];
      
        NSInteger pageIndex = [targetLauncherView.targetPath pageIndex];
        NSInteger iconIndex = [targetLauncherView.targetPath iconIndex];
      
        if (targetLauncherView.targetPath) {
            if (targetLauncherView == self) {
                // Only change or rearrange the position if the location actually changed.
                [self.dataSource launcherView:self moveIcon:self.dragIcon
                                       toPage:pageIndex
                                      toIndex:iconIndex];
            }
        } else if (self.targetIconIsOutside || self.shouldRemoveWhenDraggedOutside == NO) {
            NSLog(@"removing icon: %@ from launcherView: %@", self.dragIcon, self);
            [self.dataSource launcherView:self removeIcon:self.dragIcon];
            if ([self.delegate respondsToSelector:@selector(launcherView:didDeleteIcon:)]) {
                [self.delegate launcherView:self didDeleteIcon:self.dragIcon];
            }
          
            // the icon is dragged outside, if `shouldRemoveWhenDraggedOutside` is set to NO
            // should add it to the targetLauncherView and it should not be nil.
            if (self.shouldRemoveWhenDraggedOutside == NO) {
                NSAssert((targetLauncherView), @"We dont have another launcherView to move the icon into.\nDrag Icon: %@", self.dragIcon);
                NSLog(@"adding icon: %@ to launcherView: %@", self.dragIcon, targetLauncherView);
                if ([self.delegate respondsToSelector:@selector(launcherView:willAddIcon:)]) {
                  [targetLauncherView.delegate launcherView:targetLauncherView willAddIcon:self.dragIcon];
                }
                [targetLauncherView.dataSource launcherView:targetLauncherView addIcon:self.dragIcon
                                                  pageIndex:pageIndex
                                                  iconIndex:iconIndex];
            } else if (targetLauncherView == self) {
                // icon gets removed from self and is not added anywhere,
                // make the targetLauncherView nil
                targetLauncherView = nil;
            }
        }
      
        targetLauncherView.targetPath = nil;
    }
    
    [targetLauncherView makeIconNonDraggable:targetLauncherView.dragIcon 
                    sourceLauncherView:self
                    targetLauncherView:targetLauncherView
                            completion:^{
                                // Restart wobbling, so that the ex-dragging icon
                                // will wobble as well.
                                [targetLauncherView stopShaking];
                                [targetLauncherView startShaking];
                                if ([targetLauncherView.delegate launcherViewShouldStopEditingAfterDraggingEnds:targetLauncherView]) {
                                    [targetLauncherView stopEditing];
                                    if ([targetLauncherView.delegate respondsToSelector:@selector(launcherViewDidStopEditing:)]) {
                                        [targetLauncherView.delegate launcherViewDidStopEditing:targetLauncherView];
                                    }
                                }
                                [icon setOriginIndexPath:nil];
                            }];
    
    if (targetLauncherView != self) {
        self.dragIcon = nil;
        self.targetPath = nil;
        [self stopScrollTimer];
        [self layoutIconsAnimated];
    }
}

#pragma mark UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]] && self.editing == NO) {
        return NO;
    } else if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && self.editing == YES && self.shouldReceiveTapWhileEditing == NO) {
        return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

#pragma mark Paging Related

- (NSInteger) pageIndex {
  // The math for calculating this value is in `-updatePagerWithContentOffset:`.
  return self.pageControl.currentPage;
}

- (NSMutableArray *) addPage {
  // Get the newPage added to the dataSource.
  NSMutableArray *newPage = [self.dataSource addPageToLauncherView:self];
  
  // Also, try to add the backgroundView if nescessary to that added page.
  NSUInteger lastPage = [self.dataSource numberOfPagesInLauncherView:self]-1;
  [self addBackgroundViewIfNescessaryToPage:lastPage];
  
  return newPage;
}

- (void) removeEmptyPages
{
  NSIndexSet *indexSet = [self.dataSource removeEmptyPages:self];
  if (indexSet.count == 0) {
      return;
  }
  
  // Get the removedViews
  NSInteger startIndex = self.backgroundViews.count - indexSet.count;
  NSRange range = (NSRange){ startIndex, indexSet.count };
  NSArray *removedBackgroundViews = [self.backgroundViews subarrayWithRange:range];
  
  for (UIView *view in removedBackgroundViews) {
      // If there is a backgroundView on that particular page,
      // put it into the cache ivar before removing it from superview.
      [self.cachedBackgroundViews addObject:view];
      [view removeFromSuperview];
  }
  
  // Remove the removedBackgroundViews from the backgroundViews
  [self.backgroundViews removeObjectsInArray:removedBackgroundViews];
}

- (void) startEditing {
    if (editing == NO) {
        editing = YES;
      
        [self removeEmptyPages];
        [self addPage];
        [self updateTapGestureRecogniserIfNecessary];
        [self updateDeleteButtons];
        [self updateScrollViewContentSize];        
        [self updatePagerWithContentOffset:self.scrollView.contentOffset];
        [self startShaking];
        if ([self.delegate respondsToSelector:@selector(launcherViewDidStartEditing:)]) {
          [self.delegate launcherViewDidStartEditing:self];
        }
    } else {
        NSLog(@" %@: editing of was already started", persistKey);
    }
}

- (void) stopEditing {
    if (editing == YES) {
        editing = NO;
        [self stopShaking];
        [self updateDeleteButtons];
        [self removeEmptyPages];
        [self updateTapGestureRecogniserIfNecessary];
        [self updateScrollViewContentSize];    
        [self updatePagerWithContentOffset:self.scrollView.contentOffset];
        [self setTargetPath:nil];
        [self setDragIcon:nil];
        [self layoutIconsAnimated];
    } else {
        NSLog(@" %@: editing of was already stopped", persistKey);
    }
}


- (void) updateTapGestureRecogniserIfNecessary {
    BOOL shouldBeEnabled = YES;
    if (self.editing && self.shouldReceiveTapWhileEditing) {
        shouldBeEnabled = NO;
    }

    [self enumeratePagesUsingBlock:^(NSUInteger page) {
        [self enumerateIconsOfPage:page usingBlock:^(HMLauncherIcon *icon, NSUInteger idx) {
            icon.editing = self.editing;
            [self tapGestureRecogniserFor:icon enabled:shouldBeEnabled];
        }];
    }];
}


- (void) tapGestureRecogniserFor:(HMLauncherIcon *)icon enabled:(BOOL)enabled {
    // Get all of the tapGestureRecognisers in the list of recognisers.
    NSIndexSet *tapGestureRecognisers = [icon.gestureRecognizers indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return ([obj isKindOfClass:[UITapGestureRecognizer class]]);
    }];
    
    if (tapGestureRecognisers.count > 1)
    {
        // We have more than 1 tapGestureRecogniser, print out the warning why is this happening?
        NSLog(@"[Warning]Found %@ in icon: %@", tapGestureRecognisers, icon);
    }
    
    // Turn it to enable/disable depending on the parameter supplied.
    [tapGestureRecognisers enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        UITapGestureRecognizer *gestureRecogniser = icon.gestureRecognizers[idx];
        gestureRecogniser.enabled = enabled;
    }];
}


- (void) checkIfScrollingIsNeeded:(HMLauncherIcon*) launcherIcon {
    NSInteger springOffset = [self calculateSpringOffset:launcherIcon];
    if (springOffset != 0) {
        [self startScrollTimerWithOffset:springOffset];
    }
}


- (void) startScrollTimerWithOffset:(NSInteger) offset {
    if ([self.delegate targetLauncherViewForIcon:self.dragIcon] != self) {
        NSLog(@"don't start scroll");
        return;
    }
  
    NSNumber *springOffsetNumber = [NSNumber numberWithInteger:offset];
    if (self.scrollTimer != nil) {
        // check if previous timer heads the right way
        NSNumber *previousSetOffsetNumber = self.scrollTimer.userInfo;
        if (previousSetOffsetNumber.integerValue != springOffsetNumber.integerValue) {
            [self stopScrollTimer];
            // call method again with new direction  offset.
            [self startScrollTimerWithOffset:offset];
        }
    } else {
        self.scrollTimer = [NSTimer scheduledTimerWithTimeInterval:self.scrollTimerInterval
                                                            target:self
                                                          selector:@selector(executeScroll:)
                                                          userInfo:nil repeats:NO];
    }
}

- (void) stopScrollTimer {
    [self.scrollTimer invalidate], scrollTimer = nil;
}

- (void) executeScroll:(NSTimer*) timer {
    self.scrollTimer = nil;
    
    if ([self.delegate targetLauncherViewForIcon:self.dragIcon] != self) {
        NSLog(@"don't perform scroll");
        return;
    }
    
    NSInteger offset = [self calculateSpringOffset:self.dragIcon];
    CGFloat newPageX = self.scrollView.contentOffset.x + offset * self.scrollView.bounds.size.width;
    NSInteger numberOfPages = [self.dataSource numberOfPagesInLauncherView:self];
    NSUInteger currentPageIndex = [self pageIndexForPoint:self.scrollView.contentOffset];
    
    BOOL isOnLastPage = (currentPageIndex + 1) == numberOfPages;
    BOOL allowedToGoRight = offset > 0 && !isOnLastPage;
    BOOL allowedToGoLeft  = newPageX >= 0 && offset < 0;
    
    if (allowedToGoLeft || allowedToGoRight) {
        CGRect newPageRect = CGRectMake(newPageX, 0, self.scrollView.bounds.size.width, self.scrollView.bounds.size.height);
        [self.scrollView scrollRectToVisible:newPageRect animated:YES];
        [self updatePagerWithContentOffset:newPageRect.origin];
    }
}

-(void)scrollToPage:(NSInteger)pageIndex animated:(BOOL)animated
{
    CGRect newPageRect = CGRectZero;
    newPageRect.origin.x = pageIndex * self.scrollView.bounds.size.width;
    newPageRect.origin.y = 0.f;
    newPageRect.size = self.scrollView.bounds.size;
    [self.scrollView scrollRectToVisible:newPageRect animated:animated];
}

- (NSInteger) calculateSpringOffset:(HMLauncherIcon*) icon {
    CGSize iconSize = [self.dataSource buttonDimensionsInLauncherView:self];
    CGFloat springWidth = iconSize.width * kScrollingFraction;
    CGRect iconRectInLauncherView = [self convertRect:icon.frame fromView:icon.superview];
    
    CGFloat centerX = CGRectGetMidX(iconRectInLauncherView);
    BOOL goToPreviousPage = centerX < springWidth;
    BOOL goToNextPage = centerX > self.scrollView.bounds.size.width - springWidth;
    if (goToNextPage) {
        return 1;
    } 
    if (goToPreviousPage) {
        return -1;
    } else {
        return 0;
    };
}

- (void) makeIconDraggable:(HMLauncherIcon*) icon {
    NSParameterAssert(self.dragIcon == nil);
  
    self.dragIcon = icon;
    self.shouldLayoutDragButton = NO;
    self.targetIconIsOutside = NO;
    
    // add icon to the top most view, so that we can drag it anywhere.
    [[self keyView] addSubview:self.dragIcon];    
    CGPoint iconOutsideScrollView = [self.dragIcon.superview convertPoint:self.dragIcon.center 
                                                                 fromView:self.scrollView];
    [self.dragIcon setCenter:iconOutsideScrollView];
  
    CGAffineTransform transform = CGAffineTransformScale(icon.transform, self.draggedIconMagnification, self.draggedIconMagnification);
    transform = CGAffineTransformTranslate(transform, self.draggedIconOffset.x, self.draggedIconOffset.y);
    
    [UIView animateWithDuration:0.25 animations:^{
        icon.transform = transform;
        icon.alpha = self.draggedIconOpacity;
    }];
    if ([self.delegate respondsToSelector:@selector(launcherView:didStartDragging:)]) {
        [self.delegate launcherView:self didStartDragging:icon];
    }
}

- (void) makeIconNonDraggable:(HMLauncherIcon*) icon 
           sourceLauncherView:(HMLauncherView*) sourceLauncherView
           targetLauncherView:(HMLauncherView*) targetLauncherView
                   completion:(void (^) (void)) block {
    NSParameterAssert(icon != nil);
    [UIView animateWithDuration:0.25 animations:^{
        icon.transform = CGAffineTransformIdentity;
        icon.alpha = 1.0;
        self.shouldLayoutDragButton = YES;
        [self layoutIcons];
        self.shouldLayoutDragButton = NO;
    } completion:^(BOOL finished) {
        sourceLauncherView.dragIcon = nil;
        targetLauncherView.dragIcon = nil;
        if (sourceLauncherView != targetLauncherView) {
            [sourceLauncherView removeIcon:icon];
        } 
        [targetLauncherView addIcon:icon];
        [self layoutIcons];
        
        block();
        if ([self.delegate respondsToSelector:@selector(launcherView:didStopDragging:)]) {
            [self.delegate launcherView:self didStopDragging:icon];
        }
    }];

}

- (NSIndexPath*) iconIndexForPoint:(CGPoint) center {
    CGSize iconSize = [self.dataSource buttonDimensionsInLauncherView:self];
    CGPoint centerOutsideScrollView = [self convertPoint:center fromView:self.scrollView];;
    NSUInteger maxColumns = [self.dataSource numberOfColumnsInLauncherView:self];
    NSUInteger maxRows = [self.dataSource numberOfRowsInLauncherView:self];
    
    NSUInteger currentPageIndex = [self pageIndexForPoint:center];
    NSUInteger currentColumnIndex = centerOutsideScrollView.x / iconSize.width;
    NSUInteger currentRowIndex = (center.y / iconSize.height); 
    
    if (currentRowIndex >= maxRows) {
        currentRowIndex = maxRows - 1;
    }
    if (currentColumnIndex >= maxColumns) {
        currentColumnIndex = maxColumns - 1;
    }    
    
    NSUInteger currentButtonIndex = (currentRowIndex * maxColumns) + currentColumnIndex; 
    NSUInteger indexes[] = { currentPageIndex, currentButtonIndex } ;
    NSIndexPath *indexPath = [[[NSIndexPath alloc] initWithIndexes:indexes length:2]autorelease];
    return indexPath;
}

- (NSUInteger) pageIndexForPoint:(CGPoint) center {
    NSUInteger currentPageIndex = 0;
    if (self.scrollView.contentOffset.x > 0) {
        currentPageIndex = self.scrollView.contentOffset.x / self.scrollView.bounds.size.width; 
    }
    return currentPageIndex;
}

- (void) updateScrollViewContentSize {
    NSUInteger numberOfPages = [self.dataSource numberOfPagesInLauncherView:self];
    self.scrollView.contentSize = CGSizeMake(numberOfPages * CGRectGetWidth(self.scrollView.bounds),
                                             CGRectGetHeight(self.scrollView.bounds));
    
}

- (void) updateDeleteButtons {
    [self enumeratePagesUsingBlock:^(NSUInteger page) {
        [self enumerateIconsOfPage:page usingBlock:^(HMLauncherIcon *icon, NSUInteger idx) {
            if (icon.canBeDeleted) {
                BOOL hideDeleteImage = !self.editing;
                [icon setHideDeleteImage:hideDeleteImage];
                [icon setNeedsDisplay];
            }
        }];
    }];  
}

# pragma mark - enumeration
- (void) enumeratePagesUsingBlock:(void (^) (NSUInteger page)) block {
    NSUInteger numberOfPages = [self.dataSource numberOfPagesInLauncherView:self];    
    for (int page=0; page<numberOfPages;page++) {
        block(page);
    }
}

- (void) enumerateIconsOfPage:(NSUInteger) page usingBlock:(void (^) (HMLauncherIcon* icon, NSUInteger idx)) block {
    NSUInteger buttonsInPage = [self.dataSource launcherView:self numberOfIconsInPage:page];
    for (int i=0;i<buttonsInPage;i++) {
        HMLauncherIcon *icon = [self.dataSource launcherView:self iconForPage:page atIndex:i];
        block(icon,i);
    }
}

# pragma mark - shaking
- (void) startShaking {
    CGFloat rotation = (self.shakeRadian * M_PI) / 180.0;
    CGAffineTransform wobbleLeft = CGAffineTransformMakeRotation(rotation);
    CGAffineTransform wobbleRight = CGAffineTransformMakeRotation(-rotation);
    
    __block NSInteger i = 0;
    __block NSInteger nWobblyIcons = 0;
    
    [UIView animateWithDuration:self.shakeTime
                          delay:0 
                        options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                       
                       
                         [self enumeratePagesUsingBlock:^(NSUInteger page) {
                             [self enumerateIconsOfPage:page usingBlock:^(HMLauncherIcon *icon, NSUInteger idx) {
                                 if (icon != self.dragIcon && icon != self.closingIcon) {
                                     ++nWobblyIcons;
                                     if (i % 2) {
                                         icon.transform = wobbleRight;
                                     } else {
                                         icon.transform = wobbleLeft;
                                     }
                                 }
                                 ++i;
                             }];
                         }];   
                     } completion: ^(BOOL finished){
                         
                     }];
}

- (void) stopShaking {
    [self enumeratePagesUsingBlock:^(NSUInteger page) {
        [self enumerateIconsOfPage:page usingBlock:^(HMLauncherIcon *icon, NSUInteger idx) {
            [UIView animateWithDuration:self.shakeTime
                                  delay:0.0 
                                options:UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                                 icon.transform = CGAffineTransformIdentity;
                             } completion: ^(BOOL finished) {
                                 
                             }];
        }];
    }];
}

- (void)updatePagerWithContentOffset:(CGPoint) contentOffset {
    //NSLog(@"updatePagerWithContentOffset: %@", NSStringFromCGPoint(contentOffset));
    CGFloat pageWidth = self.scrollView.bounds.size.width;
    NSUInteger numberOfPages = [self.dataSource numberOfPagesInLauncherView:self];
    self.pageControl.numberOfPages = numberOfPages;
    self.pageControl.currentPage = floor((contentOffset.x - pageWidth / 2) / pageWidth) + 1;
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *) inScrollView{
    if (self.dragIcon != nil) {
        [self checkIfScrollingIsNeeded:self.dragIcon];
        HMLauncherView *launcherView = [self.delegate targetLauncherViewForIcon:self.dragIcon];
        CGPoint centerInLauncherView = [self.dragIcon.superview convertPoint:self.dragIcon.center toView:launcherView];
        [launcherView performMove:self.dragIcon toPoint:centerInLauncherView launcherView:launcherView];
    }
    [self updatePagerWithContentOffset:inScrollView.contentOffset];
}

- (void) scrollViewDidEndDecelerating:(UIScrollView *) inScrollView {
    [self updatePagerWithContentOffset:inScrollView.contentOffset];    
}

- (NSString*) description {
    return [NSString stringWithFormat:
            @"<%@: %p> - Persist Key: %@",
            NSStringFromClass(self.class),
            self,
            ([self persistKey]) ? [self persistKey] : @"Unnamed"];
}

#pragma mark - UIAlertViewDelegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger) buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex) {
        NSParameterAssert(self.closingIcon != nil);
        [self.dataSource launcherView:self removeIcon:self.closingIcon];
        [self removeIconAnimated:self.closingIcon 
                      completion:^{
                          self.closingIcon = nil;                          
                          [self stopEditing];
                          if ([self.delegate respondsToSelector:@selector(launcherViewDidStopEditing:)]) {
                              [self.delegate launcherViewDidStopEditing:self];
                          }
                      }];
    };
}

#pragma mark - lifecycle

- (void)_commonUIInit {
    self.scrollView = [[[UIScrollView alloc] initWithFrame:self.bounds] autorelease];
    [self.scrollView setDelegate:self];
    [self.scrollView setPagingEnabled:YES];
    [self.scrollView setShowsHorizontalScrollIndicator:NO];
    [self.scrollView setShowsVerticalScrollIndicator:NO];
    [self addSubview:self.scrollView];
  
    self.backgroundViews = [[[NSMutableArray alloc] init] autorelease];
    self.cachedBackgroundViews = [[[NSMutableSet alloc] init] autorelease];
  
    Class pageControlClass = [UIPageControl class];
    if (self.pageControlClassName != nil) {
      pageControlClass = NSClassFromString(self.pageControlClassName);
      NSAssert((pageControlClass != nil), @"Page control class name is provided by the class is not found.");
    }
  
    self.pageControl = [[[pageControlClass alloc]
                         initWithFrame:CGRectMake(0, 10, 10, 10)] autorelease];
    NSAssert(([self.pageControl isKindOfClass:[UIPageControl class]]),
             @"pageControl should have a type of UIPageControl or its inherittance.\nInstead it is: %@", [self.pageControl class]);
  
    [self.pageControl setHidesForSinglePage:YES];
    [self addSubview:self.pageControl];
  
    // The default pageControlLayoutBlock when layoutSubview gets called.
    if ([self pageControlLayoutBlock] == NULL)
    {
      self.pageControlLayoutBlock = ^(HMLauncherView *launcherView, UIPageControl *pageControl) {
        [self.pageControl sizeToFit];
        CGFloat pageControlHeight = CGRectGetHeight(self.pageControl.bounds);
        CGFloat pageControlY = CGRectGetHeight(self.bounds) - pageControlHeight;
        [self.pageControl setFrame:CGRectMake(0, pageControlY, CGRectGetWidth(self.bounds), pageControlHeight)];
      };
    }
}

- (void)_commonInit {
    [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth];
    [self setShouldRemoveWhenDraggedOutside:NO];
  
    // Punch in default value
    self.shakeRadian = kShakeRadians;
    self.shakeTime = kShakeTime;
    self.scrollTimerInterval = kScrollTimerInterval;
    self.longPressDuration = kLongPressDuration;
  
    self.draggedIconMagnification = 1.5f;
    self.draggedIconOpacity = 0.9f;
    self.draggedIconOffset = (CGPoint) {0.0f, 0.0f};
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self _commonUIInit];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self)
    {
      [self _commonInit];
    }
    return self;
}

- (id)initWithFrame:(CGRect) frame {
    if (self = [super initWithFrame:frame]) {
        [self _commonInit];
        [self _commonUIInit];
    }
    return self;
}

- (void) dealloc {  
    dataSource = nil;
    delegate = nil;
    [scrollTimer invalidate], scrollTimer = nil;
    [targetPath release], targetPath = nil;    
    [scrollView release], scrollView = nil;
    [pageControl release], pageControl = nil;
  
    [_pageControlClassName release], _pageControlClassName = nil;
    
    [backgroundViews release], backgroundViews = nil;
    [cachedBackgroundViews release], cachedBackgroundViews = nil;
  
    [super dealloc];
}

@end
