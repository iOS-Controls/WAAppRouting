//
//  WAAppRouteRegistrar.m
//  WAAppRouter
//
//  Created by Marian Paul on 18/08/2015.
//  Copyright (c) 2015 Wasappli. All rights reserved.
//

#import "WAAppRouteRegistrar.h"

#import "WAAppRouteEntity.h"
#import "WAAppMacros.h"

@interface WAAppRouteRegistrar ()

@property (nonatomic, strong) NSMutableDictionary *entities;
@property (nonatomic, strong) id <WAAppRouteMatcherProtocol>routeMatcher;

@end

@implementation WAAppRouteRegistrar

- (instancetype)initWithRouteMatcher:(id<WAAppRouteMatcherProtocol>)routeMatcher {
    WAAppRouterProtocolAssertion(routeMatcher, WAAppRouteMatcherProtocol);
    
    self = [super init];
    if (self) {
        self->_routeMatcher = routeMatcher;
        self->_entities     = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (instancetype)registrarWithRouteMatcher:(id<WAAppRouteMatcherProtocol>)routeMatcher {
    return [[self alloc] initWithRouteMatcher:routeMatcher];
}

#pragma - Registering

- (void)registerAppRouteEntity:(WAAppRouteEntity *)entity {
    WAAppRouterClassAssertion(entity, WAAppRouteEntity);
    WAAppRouteEntity *existingEntity = self.entities[entity.path];
    WAAssert([self.entities[entity.path] isEqual:entity] || !self.entities[entity.path], ([NSString stringWithFormat:@"You cannot add two entities for the same path: '%@'", entity.path]));
    
    if (![existingEntity isEqual:entity]) {
        self.entities[entity.path] = entity;
    } else {
        WAAppLog(@"An existing entity is already registered for %@. The one you passed is just ignored. This is a debug log to advice you that you should set any value (default or allowed params before if needed", entity.path);
    }
}

- (void)registerBlockRouteHandler:(WAAppRouteHandlerBlock)routeBlockHandler forRoute:(NSString *)route {
    WAAppRouterClassAssertion(routeBlockHandler, NSClassFromString(@"NSBlock"));
    
    WAAssert(!self.entities[route], ([NSString stringWithFormat:@"You cannot add two entities for the same path: '%@'", route]));
    self.entities[route] = [routeBlockHandler copy];
}

- (void)registerAppRoutePath:(NSString *)routePath presentingController:(UIViewController *)presentingController {
    return [self registerAppRoutePath:routePath
                 presentingController:presentingController
        defaultParametersBuilderBlock:nil
               allowedParametersBlock:nil];
}

- (void)registerAppRoutePath:(NSString *)routePath presentingController:(UIViewController *)presentingController defaultParametersBuilderBlock:(WAAppRouterDefaultParametersBuilderBlock (^)(NSString *path))defaultParametersBuilderBlock allowedParametersBlock:(NSArray* (^)(NSString *path))allowedParametersBlock {
    WAAppRouterClassAssertion(routePath, NSString);
    
    NSArray *pathComponents = [routePath componentsSeparatedByString:@"/"];
    
    NSMutableString *currentPath = nil;
    Class previousClass          = Nil;
    
    for (NSString *pathComponent in pathComponents) {
        
        // If the component is 0, break. This might be an extra slash at the end
        if ([pathComponent length] == 0) {
            break;
        }
        
        // Check if we have {} enclosure
        NSRange startBraceCharacter = [pathComponent rangeOfString:@"{"];
        NSRange endBraceCharacter   = [pathComponent rangeOfString:@"}"];
        WAAssert((startBraceCharacter.location != NSNotFound && endBraceCharacter.location != NSNotFound)
                 ||
                 (startBraceCharacter.location == NSNotFound && endBraceCharacter.location == NSNotFound), ([NSString stringWithFormat:@"You need to have the class enclosed between {ClassName} on %@", pathComponent]));
        
        // Extract infos
        NSString *urlPathComponent = nil;
        BOOL isModal               = NO;
        Class targetClass          = nil;
        
        if (startBraceCharacter.location != NSNotFound && endBraceCharacter.location != NSNotFound) {
            urlPathComponent    = [pathComponent substringToIndex:startBraceCharacter.location];
            NSString *className = [pathComponent substringWithRange:NSMakeRange(startBraceCharacter.location + 1, endBraceCharacter.location - (startBraceCharacter.location + 1))];
            targetClass         = NSClassFromString(className);
            isModal             = [pathComponent hasSuffix:@"!"];
            
            // Check class name existance
            WAAssert(targetClass != Nil, ([NSString stringWithFormat:@"The class %@ does not seems to be existing", className]));
        } else {
            urlPathComponent = pathComponent;
        }
        
        
        
        if (!currentPath) {
            currentPath = [NSMutableString stringWithString:urlPathComponent];
        }
        else {
            [currentPath appendFormat:@"/%@", urlPathComponent];
        }
        
        // Build the entity
        NSArray *allowedParameters = nil;
        if (allowedParametersBlock) {
            allowedParameters = allowedParametersBlock(currentPath);
        }
        
        WAAppRouterDefaultParametersBuilderBlock defaultParametersBuilder = nil;
        if (defaultParametersBuilderBlock) {
            defaultParametersBuilder = defaultParametersBuilderBlock(currentPath);
        }
        
        WAAppRouteEntity *routeEntity = [WAAppRouteEntity routeEntityWithName:[currentPath copy]
                                                                         path:[currentPath copy]
                                                        sourceControllerClass:previousClass
                                                        targetControllerClass:targetClass
                                                         presentingController:!isModal ? presentingController : nil
                                                     prefersModalPresentation:isModal
                                                     defaultParametersBuilder:defaultParametersBuilder
                                                            allowedParameters:allowedParameters];
        [self registerAppRouteEntity:routeEntity];
        
        if (targetClass) {
            previousClass = targetClass;
        }
    }
}

#pragma mark - Retrieving

- (WAAppRouteEntity *)entityForURL:(NSURL *)url {
    WAAssert(self.routeMatcher, @"You need to provide a route matcher on initialization");
    
    WAAppRouteEntity *foundedEntity = nil;
    
    for (NSString *pathPattern in [self.entities allKeys]) {
        WAAppRouteEntity *entity = self.entities[pathPattern];
        if ([entity isKindOfClass:NSClassFromString(@"NSBlock")]) {
            continue;
        }
        
        BOOL hasAMatch = [self.routeMatcher matchesURL:url
                                       fromPathPattern:pathPattern];
        
        if (hasAMatch) {
            foundedEntity = entity;
            break;
        }
    }
    
    return foundedEntity;
}

- (WAAppRouteHandlerBlock)blockHandlerForURL:(NSURL *)url pathPattern:(NSString *__autoreleasing *)pathPatternFound {
    WAAssert(self.routeMatcher, @"You need to provide a route matcher on initialization");
    
    WAAppRouteHandlerBlock foundedBlock = nil;
    
    for (NSString *pathPattern in [self.entities allKeys]) {
        WAAppRouteHandlerBlock block = self.entities[pathPattern];
        if ([block isKindOfClass:[WAAppRouteEntity class]]) {
            continue;
        }
        
        BOOL hasAMatch = [self.routeMatcher matchesURL:url
                                       fromPathPattern:pathPattern];
        
        if (hasAMatch) {
            foundedBlock = block;
            if (pathPattern) {
                *pathPatternFound = pathPattern;
            }
            break;
        }
    }
    
    return foundedBlock;
}

- (WAAppRouteEntity *)entityForTargetClass:(Class)targetClass {
    WAAppRouteEntity *foundedEntity = nil;
    
    for (WAAppRouteEntity *entity in [self.entities allValues]) {
        if ([entity isKindOfClass:NSClassFromString(@"NSBlock")]) {
            continue;
        }
        
        if (entity.targetControllerClass == targetClass && targetClass) {
            if (!foundedEntity) {
                foundedEntity = entity;
            }
        }
    }
    return foundedEntity;
}

@end
