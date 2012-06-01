//
//  Inheritance.m
//  NSRails
//
//  Created by Dan Hassin on 1/29/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRAsserts.h"

@interface Parent : NSRRemoteObject
@property (nonatomic, strong) id parentAttr;
@property (nonatomic, strong) id parentAttr2;
@end
@implementation Parent
@synthesize parentAttr, parentAttr2;
NSRMap (*, parentAttr2 -x)
NSRUseModelName(@"parent", @"parentS")
@end

	@interface Child : Parent
	@property (nonatomic, strong) id childAttr1;
	@property (nonatomic, strong) id childAttr2;
	@end
	@implementation Child
	@synthesize childAttr1, childAttr2;
	NSRMap (childAttr1, parentAttr2) //absent NSRNoCarryFromSuper -> will inherit from parent
	NSRUseModelName(@"parent", @"parentS")
	@end

		@interface Grandchild : Child
		@property (nonatomic, strong) id gchildAttr;
		@end
		@implementation Grandchild
		@synthesize gchildAttr;
		NSRMap(*, parentAttr2 -x) //absent NSRNoCarryFromSuper -> will inherit from parent, but ignored parentAttr2 as test
		@end

		@interface RebelliousGrandchild : Child
		@property (nonatomic, strong) id r_gchildAttr;
		@end
		@implementation RebelliousGrandchild
		@synthesize r_gchildAttr;
		NSRMapNoInheritance(*) //NSRNoCarryFromSuper present -> won't inherit anything
		NSRUseModelName(@"r_gchild")
		@end

	@interface RebelliousChild : Parent
	@property (nonatomic, strong) id r_childAttr;
	@end
	@implementation RebelliousChild
	@synthesize r_childAttr;
	NSRMapNoInheritance(*) //NSRNoCarryFromSuper present -> won't inherit anything
	NSRUseModelName(@"r_child")
	@end

		@interface GrandchildOfRebellious : RebelliousChild
		@property (nonatomic, strong) id gchild_rAttr;
		@end
		@implementation GrandchildOfRebellious
		@synthesize gchild_rAttr;
		// * -> //absent NSRNoCarryFromSuper -> will inherit from r.child, BUT inheritance will stop @ R.Child 
		@end

		@interface RebelliousGrandchildOfRebellious : RebelliousChild
		@property (nonatomic, strong) id r_gchild_rAttr;
		@end
		@implementation RebelliousGrandchildOfRebellious
		@synthesize r_gchild_rAttr;
		NSRMapNoInheritance(*) //NSRNoCarryFromSuper present -> won't inherit anything
		NSRUseModelName(@"r_gchild_r", @"r_gchild_rS")
		@end


#define NSRAssertClassConfig(class, teststring) NSRAssertEqualConfigs([class getRelevantConfig], teststring, @"%@ config failed", NSStringFromClass(class))

#define NSRAssertInstanceConfig(class, teststring) NSRAssertEqualConfigs([[[class alloc] init] getRelevantConfig], teststring, @"%@ config failed", NSStringFromClass(class))

#define NSRAssertClassAndInstanceConfig(class, teststring) NSRAssertInstanceConfig(class, teststring); NSRAssertClassConfig(class, teststring)


#define NSRAssertClassProperties(class, ...) NSRAssertEqualArraysNoOrderNoBlanks([[class propertyCollection] properties].allKeys, NSRArray(__VA_ARGS__))

#define NSRAssertInstanceProperties(class, ...) NSRAssertEqualArraysNoOrderNoBlanks([[[[class alloc] init] propertyCollection] properties].allKeys, NSRArray(__VA_ARGS__))

#define NSRAssertClassAndInstanceProperties(class, ...) NSRAssertClassProperties(class, __VA_ARGS__); NSRAssertInstanceProperties(class, __VA_ARGS__)

@interface TInheritance : SenTestCase
@end

@implementation TInheritance

- (void) test_model_name_inheritance
{
	//was explicitly set to "parent"
	NSRAssertClassModelName(@"parent", [Parent class]);
	NSRAssertClassPluralName(@"parentS", [Parent class]);
	
	
	//was explicitly set to "parent" (test that even identical implementations are marked different)
	NSRAssertClassModelName(@"parent", [Child class]);
	NSRAssertClassPluralName(@"parentS", [Child class]); //explicit plural set
	
	NSRAssertClassModelName(@"grandchild", [Grandchild class]);
	NSRAssertClassPluralName(@"grandchilds", [Grandchild class]);
	
	//explicit set
	NSRAssertClassModelName(@"r_gchild", [RebelliousGrandchild class]);
	NSRAssertClassPluralName(@"r_gchilds", [RebelliousGrandchild class]); //no explicit plural set
	
	
	//explicit set
	NSRAssertClassModelName(@"r_child", [RebelliousChild class]);
	NSRAssertClassPluralName(@"r_childs", [RebelliousChild class]); //default plural set
	
	NSRAssertClassModelName(@"grandchild_of_rebellious", [GrandchildOfRebellious class]);
	NSRAssertClassPluralName(@"grandchild_of_rebelliouses", [GrandchildOfRebellious class]); //inherits default
	
	//explicit set
	NSRAssertClassModelName(@"r_gchild_r", [RebelliousGrandchildOfRebellious class]);
	NSRAssertClassPluralName(@"r_gchild_rS", [RebelliousGrandchildOfRebellious class]); //explicitly set
}

- (void) test_property_inheritance
{
	//this is just normal
	NSRAssertClassAndInstanceProperties([Parent class], @"parentAttr", @"remoteID");
	
	//complacent child
	//is complacent (doesn't explicitly define NSRNoCarryFromSuper), so will inherit parent's attributes too
	//this is simultaneously a test that the "*" from Parent isn't carried over - child has 2 properties and only one is defined
	//this will also test to see if syncing "parentAttr2" is allowed (attribute in parent class not synced by parent class)
	NSRAssertClassAndInstanceProperties([Child class], @"remoteID", @"childAttr1", @"parentAttr2", @"parentAttr");
	
	//is complacent, so should inherit everything! (parent+child), as well as its own
	//however, excludes parentAttr2 as a test
	NSRAssertClassAndInstanceProperties([Grandchild class], @"remoteID", @"childAttr1", @"gchildAttr", @"parentAttr");
	
	//is rebellious, so should inherit nothing! (only its own)
	NSRAssertClassAndInstanceProperties([RebelliousGrandchild class], @"remoteID", @"r_gchildAttr");
	
	
	//rebellious child
	//is rebellious, so should inherit nothing (only be using whatever attributes defined by itself)
	NSRAssertClassAndInstanceProperties([RebelliousChild class], @"remoteID", @"r_childAttr");
	
	//is complacent, so should inherit everything until it sees the _NSR_NO_SUPER_ (which it omits), meaning won't inherit Parent
	NSRAssertClassAndInstanceProperties([GrandchildOfRebellious class], @"remoteID", @"gchild_rAttr", @"r_childAttr");
	
	//is rebellious, so should inherit nothing (only be using whatever attributes defined by itself)
	NSRAssertClassAndInstanceProperties([RebelliousGrandchildOfRebellious class], @"remoteID", @"r_gchild_rAttr");
}

@end
