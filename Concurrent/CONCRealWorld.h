//
//  PARRealWorld.h
//  Parallel
//
//  Created by Robert Widmann on 9/20/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^PARWorkBlock)(void);

@interface PARRealWorld : NSObject

+ (pthread_t)forkWithStart:(PARWorkBlock)block;
+ (pthread_t)forkOnto:(unsigned int)processor withStart:(PARWorkBlock)block;

+ (void)labelThreadWithName:(const char *)name;
+ (void)yieldThread;

+ (void)killThread:(pthread_t)thread;

+ (NSUInteger)CPUCount;

@end
