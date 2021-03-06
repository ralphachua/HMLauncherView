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

#import "HMLauncherData.h"

@implementation HMLauncherData
@synthesize maxRows;
@synthesize maxColumns;
@synthesize persistKey;
@synthesize launcherIconPages;

- (void) addIcon:(HMLauncherIcon *)icon {
    NSParameterAssert(icon != nil);    
    NSParameterAssert(maxRows > 0);
    NSParameterAssert(maxColumns > 0);
    
    // Go to last page    
    NSInteger lastPageIndex = [self.launcherIconPages count] - 1;
    NSMutableArray *targetPage = nil;
    
    if (lastPageIndex == -1) {
        targetPage = [self addPage];
    } else {
        targetPage = [self.launcherIconPages objectAtIndex:lastPageIndex];
        NSUInteger numberOfIconsOnPage = [targetPage count];
        NSUInteger maxIcons = self.maxRows * self.maxColumns;
        if (numberOfIconsOnPage == maxIcons) {
            // Target page is full, so create new page
            targetPage = [self addPage];
        }
    }
    [targetPage addObject:icon];
}

- (void) removeIcon:(HMLauncherIcon *) icon {
    NSParameterAssert(icon != nil);
    NSMutableArray *page = [self pageOfIcon:icon];
    [page removeObject:icon];
}

- (void)      addIcon:(HMLauncherIcon*) icon
            pageIndex:(NSUInteger) pageIndex
            iconIndex:(NSUInteger) iconIndex {
    NSParameterAssert(icon != nil);
    NSParameterAssert(pageIndex < 5000);
    NSParameterAssert(iconIndex < 5000);
    
    [self addIcon:icon];
    [self moveIcon:icon toPage:pageIndex toIndex:iconIndex];
}

- (void)     moveIcon: (HMLauncherIcon*) icon 
               toPage: (NSUInteger) pageIndex
              toIndex: (NSUInteger) iconIndex {
    NSParameterAssert(icon != nil);
    NSParameterAssert(pageIndex < 5000);
    NSParameterAssert(iconIndex < 5000);
    
    // Remove from old position
    NSMutableArray *previousPage = [self pageOfIcon:icon];
    NSMutableArray *page = nil;
    [previousPage removeObject:icon];
    
    // Put icon into new position
    if (pageIndex < [self.launcherIconPages count]) { 
        page = [self.launcherIconPages objectAtIndex:pageIndex];
    } else {
        page = [NSMutableArray array];
        [self.launcherIconPages addObject:page];
    }
    if (iconIndex >= [page count]) {
        [page addObject:icon];
    } else {
        [page insertObject:icon atIndex:iconIndex];        
    }
    
    // Check for overflow
    NSUInteger maxIcons = self.maxColumns * self.maxRows;
    
    if ([page count] > maxIcons) {
        HMLauncherIcon *overflowIcon = [page objectAtIndex:maxIcons];
        NSUInteger targetPageIndexForOverflowIcon = pageIndex + 1;

        if (targetPageIndexForOverflowIcon == [self.launcherIconPages count]) {
            // We are at the last page, so add a new page.
            [self addPage];
        }
        [self moveIcon:overflowIcon toPage:targetPageIndexForOverflowIcon toIndex:0];
    }
}


- (NSMutableArray*) addPage {
    NSMutableArray *freshPage = [NSMutableArray array];
    [self.launcherIconPages addObject:freshPage];
    return freshPage;
}

- (NSIndexSet*) removeEmptyPages {
    NSMutableIndexSet *deletedPageIndexes = [[NSMutableIndexSet alloc] init];
    for (NSUInteger i=0; i<self.launcherIconPages.count; i++) {
        NSArray *page = self.launcherIconPages[i];
        if ([page count] == 0) {
            [deletedPageIndexes addIndex:i];
        }
    }
  
    [self.launcherIconPages removeObjectsAtIndexes:deletedPageIndexes];
    return [deletedPageIndexes autorelease];
}


- (NSArray*) findIconsByIdentifier:(NSString*) identifier {
    NSParameterAssert(identifier != nil);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:2];
    for (NSMutableArray* page in launcherIconPages) {
        for (HMLauncherIcon *icon in page) {
            NSParameterAssert(icon.identifier != nil);
            if ([icon.identifier isEqualToString:identifier]){
                [result addObject:icon];
            }
        }
    }
    return result;
}

- (NSMutableArray*) pageOfIcon:(HMLauncherIcon*) icon {
    NSParameterAssert(icon != nil);
    for (NSMutableArray* page in launcherIconPages) {
        if ([page containsObject:icon]) {
            return page;
        }
    }
    return nil;
}

- (NSString*) description {
    return [NSString stringWithFormat:@"%@, maxRows:%ld, maxColumns:%ld, [launcherIconPages count]:%lu",
            persistKey, (long)maxRows, (long)maxColumns, (unsigned long)[launcherIconPages count]];
}

- (NSUInteger) iconCount {
    NSUInteger icons = 0;
    for (NSMutableArray* page in launcherIconPages) {
        icons += [page count];
    }
    return icons;
}

- (NSUInteger) pageCount {
    return [self.launcherIconPages count];
}

- (id) init {
    if (self = [super init]) {
        self.launcherIconPages = [NSMutableArray arrayWithCapacity:10];
    }
    return self;
}

- (void) dealloc {
    [persistKey release], persistKey = nil;
    [launcherIconPages release], launcherIconPages = nil;
    [super dealloc];
}
@end
