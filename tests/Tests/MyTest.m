//
//  MyTest.m
//  NSRails
//
//  Created by Dan Hassin on 1/29/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <GHUnitIOS/GHUnit.h> 
#import "NSRConfig.h"

@interface MyTest : GHTestCase { }
@end

@implementation MyTest

- (void) testAddition3
{
	GHAssertTrue(1+1==2, @"yep");
}

@end