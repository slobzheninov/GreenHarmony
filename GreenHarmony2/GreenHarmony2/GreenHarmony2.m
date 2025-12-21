//
//  GreenHarmony2.m
//  GreenHarmony2
//
//  Created by Rainer Erich Scheichelbauer on 21.12.25.
//
//

#import "GreenHarmony2.h"

@implementation GreenHarmony2
@synthesize controller;

- (instancetype)init {
	self = [super init];
	return self;
}

- (NSUInteger)interfaceVersion {
	// Distinguishes the API version the plugin was built for. Return 1.
	return 2;
}

- (NSString *)title {
	// Return the name of the tool as it will appear in the menu.
	return @"Green Harmony";
}

- (NSString *)keyEquivalent {
	// The key together with Cmd+Shift will be the shortcut for the filter.
	// Return nil if you do not want to set a shortcut.
	// Users can set their own shortcuts in System Prefs.
	return nil;
}

- (void)processFont:(GSFont *)font withArguments:(NSArray *)arguments {
    // Process ALL glyphs in first master (simple version, no glyph filtering)
    if (!font || font.glyphs.count == 0) return;
    
    GSFontMaster *firstMaster = font.fontMasters.firstObject;
    if (!firstMaster) return;
    
    NSString *masterId = firstMaster.id;
    
    for (GSGlyph *glyph in font.glyphs) {
        GSLayer *layer = [glyph layerForId:masterId];
        if (layer) {
            [self processLayer:layer options:@{@"inEditView": @NO}];
        }
    }
}
//
- (BOOL)runFilterWithLayer:(GSLayer *)layer error:(out NSError *__autoreleasing *)error { 
    [self processLayer:layer];
    return YES;
}


- (BOOL)runFilterWithLayers:(NSArray *)layers error:(out NSError *__autoreleasing *)error { 
    for (GSLayer *layer in layers) {
        [self processLayer: layer];
    }
    return YES;
}


- (NSError *)setup {
    return nil;
}


- (void)processLayer:(GSLayer *)layer {
    [self processLayer:layer options:@{ @"inEditView": @NO }];
}

- (void)processLayer:(GSLayer *)layer
             options:(NSDictionary *)options {

    BOOL inEditView = [options[@"inEditView"] boolValue];

//    NSEventModifierFlags keysPressed = [NSEvent modifierFlags];
//    BOOL optionKeyPressedInEditView =
//        inEditView &&
//        ((keysPressed & NSEventModifierFlagOption) == NSEventModifierFlagOption);

    BOOL selectionCounts = inEditView && (layer.selection.count > 0);
//    NSLog(@"Processing layer %@, shapes: %lu, selection: %lu", layer.name, (unsigned long)layer.shapes.count, (unsigned long)layer.selection.count);
    
    if (layer.shapes.count == 0) {
        return;
    }

    for (NSInteger i = 0; i < layer.shapes.count; i++) {
        GSPath *shape = (GSPath *)layer.shapes[i];
        if (![shape isKindOfClass:[GSPath class]]) {
            continue;
        }
        
        for (NSUInteger j = 0; j < shape.countOfNodes; j++) {
            GSNode *node = [shape nodeAtIndex:j];
            
            if (selectionCounts && ![layer.selection containsObject:node]) {
                continue;
            }
            
            if (node.type == CURVE && node.isSmooth) {
                GSNode *N = [self nextNodeOfPath:shape nodeIndex:(NSInteger)j];
                GSNode *P = [self prevNodeOfPath:shape nodeIndex:(NSInteger)j];
                
                if (N && P && N.type == OFFCURVE && P.type == OFFCURVE) {
//                    NSLog(@"Found smooth CURVE node %lu in shape %ld", (unsigned long)j, (long)i);
                    GreenHarmonyHarmonize(layer, i, j, self);
                }
            }
        }
    }
}

- (GSNode *)prevNodeOfPath:(GSPath *)path nodeIndex:(NSInteger)nodeIndex {
    NSUInteger nodeCount = path.countOfNodes;
    if (nodeCount == 0) return nil;
    
    NSUInteger prevIdx = (nodeIndex + nodeCount - 1) % nodeCount;
    return [path nodeAtIndex:prevIdx];
}

- (GSNode *)nextNodeOfPath:(GSPath *)path nodeIndex:(NSInteger)nodeIndex {
    NSUInteger nodeCount = path.countOfNodes;
    if (nodeCount == 0) return nil;
    
    NSUInteger nextIdx = (nodeIndex + 1) % nodeCount;
    return [path nodeAtIndex:nextIdx];
}

static inline NSPoint GreenHarmonyGetIntersection(CGFloat x1, CGFloat y1,
                                                  CGFloat x2, CGFloat y2,
                                                  CGFloat x3, CGFloat y3,
                                                  CGFloat x4, CGFloat y4) {
    CGFloat denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom == 0.0) {
        return NSMakePoint(0.0, 0.0); // or some fallback
    }

    CGFloat px = ((x1 * y2 - y1 * x2) * (x3 - x4)
                  - (x1 - x2) * (x3 * y4 - y3 * x4)) / denom;
    CGFloat py = ((x1 * y2 - y1 * x2) * (y3 - y4)
                  - (y1 - y2) * (x3 * y4 - y3 * x4)) / denom;

    return NSMakePoint(px, py);
}

static inline CGFloat GreenHarmonyGetDistPoints(NSPoint a, NSPoint b) {
    CGFloat dx = b.x - a.x;
    CGFloat dy = b.y - a.y;
    return sqrt(dx * dx + dy * dy);
}

static inline CGFloat GreenHarmonyRemap(CGFloat oldValue, CGFloat oldMin, CGFloat oldMax, CGFloat newMin, CGFloat newMax) {    CGFloat oldRange = oldMax - oldMin;
    if (oldRange == 0.0) {
        return newMin; // or some other fallback
    }
    CGFloat newRange = newMax - newMin;
    CGFloat newValue = (((oldValue - oldMin) * newRange) / oldRange) + newMin;
    return newValue;
}

static void GreenHarmonyHarmonize(GSLayer *layer, NSInteger shapeIndex, NSInteger nodeIndex, GreenHarmony2 *self) {
    if (shapeIndex < 0 || shapeIndex >= layer.shapes.count) return;
    
    id shapeObj = layer.shapes[shapeIndex];
    if (![shapeObj isKindOfClass:[GSPath class]]) return;
    GSPath *path = (GSPath *)shapeObj;
    
    NSUInteger nodeCount = path.countOfNodes;
    if (nodeCount < 4) return;
    
    if (nodeIndex < 0 || nodeIndex >= nodeCount) return;
    
    GSNode *node = [path nodeAtIndex:nodeIndex];
    if (![node isKindOfClass:[GSNode class]]) return;
    
    GSNode *N  = [self nextNodeOfPath:path nodeIndex:nodeIndex];
    GSNode *P  = [self prevNodeOfPath:path nodeIndex:nodeIndex];
//    NSLog(@"Harmonizing node %ld in shape %ld: N=%@ P=%@", (long)nodeIndex, (long)shapeIndex,
//          NSStringFromPoint(N.position), NSStringFromPoint(P.position));
    if (!N || !P || N.type != OFFCURVE || P.type != OFFCURVE) return;
    
    NSInteger nnIdx = [path indexOfNode:N];
    NSInteger ppIdx = [path indexOfNode:P];
    GSNode *NN = [self nextNodeOfPath:path nodeIndex:nnIdx];
    GSNode *PP = [self prevNodeOfPath:path nodeIndex:ppIdx];
    if (!NN || !PP) return;
    
    NSPoint intersection = GreenHarmonyGetIntersection(
        N.position.x,  N.position.y,
        NN.position.x, NN.position.y,
        P.position.x,  P.position.y,
        PP.position.x, PP.position.y
    );
    
    CGFloat r0 = GreenHarmonyGetDistPoints(NN.position, N.position) /
                 GreenHarmonyGetDistPoints(N.position, intersection);
    CGFloat r1 = GreenHarmonyGetDistPoints(intersection, P.position) /
                 GreenHarmonyGetDistPoints(P.position, PP.position);
    
    CGFloat ratio = sqrt(r0 * r1);
    CGFloat t = ratio / (ratio + 1.0);
    
    node.position = NSMakePoint(
        GreenHarmonyRemap(t, 0.0, 1.0, N.position.x, P.position.x),
        GreenHarmonyRemap(t, 0.0, 1.0, N.position.y, P.position.y)
    );
}

@end
