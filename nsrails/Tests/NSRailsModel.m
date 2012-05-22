//
//  NSRailsModel.m
//  NSRails
//
//  Created by Dan Hassin on 1/29/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRAsserts.h"

@interface PickySender : NSRailsModel
@property (nonatomic, strong) NSString *local, *retrieveOnly, *sendOnly, *shared, *sharedExplicit, *undefined;
@end

@implementation PickySender
@synthesize local, retrieveOnly, shared, sharedExplicit, sendOnly, undefined;
NSRailsSync(local -x, retrieveOnly -r, shared, sharedExplicit -rs, sendOnly -s)
@end

@interface PropertyTester : NSRailsModel
@property (nonatomic, strong) id propertyTester;
@end 

@implementation PropertyTester
@synthesize propertyTester;
@end

@interface BadCoder : NSRailsModel
@end

@implementation BadCoder
NSRailsSync(thing -e)
@end

@interface PickyCoderComponent : NSRailsModel
@property (nonatomic, strong) NSString *componentName;
@end

@implementation PickyCoderComponent
@synthesize componentName;
@end

@interface PickyCoder : NSRailsModel

@property (nonatomic) BOOL encodeNonJSON;
@property (nonatomic, strong) NSURL *locallyURL;
@property (nonatomic, strong) NSString *locallyLowercase, *remotelyUppercase, *codeToNil;
@property (nonatomic, strong) PickyCoderComponent *componentWithFlippingName;
@property (nonatomic, strong) NSDate *dateOverrideSend, *dateOverrideRet;

@end

@implementation PickyCoder
@synthesize locallyURL, locallyLowercase, remotelyUppercase, componentWithFlippingName, codeToNil, encodeNonJSON, dateOverrideSend, dateOverrideRet;
NSRailsSync(locallyURL=locally_url -ed, locallyLowercase -d, remotelyUppercase -e, remoteOnly -se, codeToNil -ed, componentWithFlippingName=component -de, dateOverrideSend -e, dateOverrideRet -d);

- (id) encodeRemoteOnly
{
	if (encodeNonJSON)
	{
		return [[NSScanner alloc] init];
	}
	return @"remote";
}

- (id) encodeDateOverrideSend
{
	return @"override!";
}

- (id) decodeDateOverrideRet:(NSString *)json
{
	return [NSDate dateWithTimeIntervalSince1970:0];
}

- (NSString *) decodeCodeToNil:(NSString *)str
{
	return nil;
}

- (NSString *) encodeCodeToNil:(NSString *)input
{
	return nil;
}

- (NSURL *) decodeLocallyURL:(NSString *)remoteUrl
{
	return [NSURL URLWithString:remoteUrl];
}

- (NSString *) decodeLocallyLowercase:(NSString *)remote
{
	return [remote lowercaseString];
}

- (PickyCoderComponent *) decodeComponentWithFlippingName:(NSDictionary *)remoteDict
{
	PickyCoderComponent *new = [[PickyCoderComponent alloc] initWithRemoteDictionary:remoteDict];
	new.componentName = [new.componentName lowercaseString];
	
	return new;
}

- (id) encodeComponentWithFlippingName
{
	componentWithFlippingName.componentName = [componentWithFlippingName.componentName uppercaseString];
	return [componentWithFlippingName remoteDictionaryRepresentationWrapped:YES];
}

- (NSString *) encodeLocallyURL
{
	NSString *ret = [locallyURL description];
	return ret;
}

- (id) encodeRemotelyUppercase
{
	return [remotelyUppercase uppercaseString];
}

@end

@interface NoSyncStringTester : NSRailsModel
@property (nonatomic, strong) NSString *property1;
@end
@implementation NoSyncStringTester
@synthesize property1;
@end

@interface SyncStringTester : NSRailsModel
@property (nonatomic, strong) NSString *property1, *property2, *property3;
@end

@implementation SyncStringTester
@synthesize property1, property2, property3;
NSRailsSync(property1, property2, property3)
@end

@interface SyncStringTesterChild : NSRailsModel
@property (nonatomic, strong) NSString *childProperty1, *childProperty2;
@end

@implementation SyncStringTesterChild
@synthesize childProperty1, childProperty2;
NSRailsSync(childProperty1, childProperty2)
@end

@interface Empty : NSRailsModel
@end

@implementation Empty
@end

@interface DictionaryNester : NSRailsModel
@property (nonatomic, strong) NSArray *dictionaries;
@end

@implementation DictionaryNester
@synthesize dictionaries;
NSRailsSync(dictionaries -m);
@end

@interface LadiesMan : NSRailsModel
@property (nonatomic, strong) NSArray *lotsOfDates;
@end

@implementation LadiesMan
@synthesize lotsOfDates;
NSRailsSync(lotsOfDates:NSDate);

@end

@interface CustomGuy : NSRailsModel
@end

@implementation CustomGuy
NSRailsUseConfig(@"url", @"user", @"pass");
NSRailsSync(something);
@end

@implementation MockServer (pickys)

+ (NSDictionary *) newPickyCoder
{
	return NSRDictionary(@"LoweRCasE?",@"locally_lowercase",@"upper",@"remotely_uppercase",@"http://nsrails.com",@"locally_url",@"invisible",@"remote_only",@"something",@"code_to_nil",@"2012-05-07T04:41:52Z",@"date_override_send",@"afsofauh",@"date_override_ret",NSRDictionary(@"COMP LOWERCASE?", @"component_name"),@"component");
}

+ (NSDictionary *) newPickySender
{
	return NSRDictionary(@"retrieve", @"retrieve_only",@"send",@"send_only",@"shared",@"shared", @"shared explicit",@"shared_explicit", @"x",@"undefined");
}

+ (NSDictionary *) newDictionaryNester
{
	return NSRDictionary(NSRArray(NSRDictionary(@"im",@"so"),NSRDictionary(@"hip",@"!")), @"dictionaries");
}

+ (NSDictionary *) newLadiesMan
{
	return NSRDictionary(NSRArray(@"2012-05-07T04:41:52Z",@"2012-05-07T04:41:52Z",@"2012-05-07T04:41:52Z"), @"lots_of_dates");
}

@end

@interface TNSRailsModel : SenTestCase
@end

#define NSRAssertEqualSyncStrings(a,b,reason) \
NSRAssertEqualArraysNoOrderNoBlanks([a componentsSeparatedByString:@","],[b componentsSeparatedByString:@","])

@implementation TNSRailsModel

- (void) test_nsrailssync
{
	NSRAssertEqualSyncStrings([Empty masterNSRailsSync], @"remoteID=id", @"failed default (no NSRS) being * AND empty");
	
	NSRAssertEqualSyncStrings([NoSyncStringTester masterNSRailsSync], @"property1, remoteID=id", @"failed default (no NSRS) being *");
	
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSync], @"property1, property2, property3, remoteID=id", @"default (no override) failed");
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSyncWithOverrideString:@"property1, property2, property3"], @"property1, property2, property3, remoteID=id", @"override failed");
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSyncWithOverrideString:@"*"], @"property3, property2, property1, remoteID=id", @"* failed");
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSyncWithOverrideString:@"*, property1 -x"], @"property1 -x, property3, property2, property1, remoteID=id", @"* with extraneous failed");
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSyncWithOverrideString:@"*, property1 -x, remoteID -x"], @"property1 -x, remoteID -x, property3, property2, property1, remoteID=id", @"* with extraneous failed");
	
	// Inheritance
	
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSyncWithOverrideString:@"NSRNoCarryFromSuper"], @"remoteID=id", @"should be blank if nothing declared and nothing inherited");
	NSRAssertEqualSyncStrings([SyncStringTester masterNSRailsSyncWithOverrideString:@"NSRNoCarryFromSuper *"], @"property3, property2, property1, remoteID=id", @"should be only my properties if * declared and nothing inherited");
}

- (void) test_custom_requests
{
	// Root
	
	STAssertEqualObjects([NSRailsModel routeForControllerMethod:nil], @"", @"Root route failed");	
	STAssertEqualObjects([NSRailsModel routeForControllerMethod:@"action"], @"action", @"Root route failed");	
	
	// Controller (class)
	STAssertEqualObjects([Empty routeForControllerMethod:nil], @"empties", @"Nil controller route failed");	
	STAssertEqualObjects([Empty routeForControllerMethod:@"action"], @"empties/action", @"Controller route failed");
	
	// Instance
	
	Empty *smth = [[Empty alloc] init];
	STAssertThrowsSpecificNamed([smth routeForInstanceMethod:nil], NSException, NSRailsNullRemoteIDException, @"Should have been an exception getting instance route if nil remoteID");
	
	smth.remoteID = [NSNumber numberWithInt:1];
	STAssertEqualObjects([smth routeForInstanceMethod:nil], @"empties/1", @"Nil instance route failed");
	STAssertEqualObjects([smth routeForInstanceMethod:@"action"], @"empties/1/action", @"Instance route failed");
}

- (void) test_encode_decode
{
	BadCoder *b = [[BadCoder alloc] init];
	STAssertThrows([b remoteDictionaryRepresentationWrapped:NO], @"Should throw unrecognized selector for encode:");
	
	PickyCoder *p = [[PickyCoder alloc] initWithRemoteDictionary:[MockServer newPickyCoder]];
	p.encodeNonJSON = NO;
	
	STAssertTrue([p.locallyURL isKindOfClass:[NSURL class]], @"Should've decoded into a URL");
	STAssertTrue([p.dateOverrideSend isKindOfClass:[NSDate class]], @"Should've decoded into an NSDate");
	STAssertTrue([p.dateOverrideRet isEqualToDate:[NSDate dateWithTimeIntervalSince1970:0]], @"Should've used custom decode");
	STAssertNil(p.codeToNil, @"Should've decoded codeToNil into nil");
	STAssertEqualObjects([p.locallyURL description], @"http://nsrails.com", @"Should've decoded into URL & retain content");
	STAssertEqualObjects(p.locallyLowercase, @"lowercase?", @"Should've decoded into lowercase");
	STAssertEqualObjects(p.remotelyUppercase, @"upper", @"Should've kept the same");
	STAssertEqualObjects(p.componentWithFlippingName.componentName, @"comp lowercase?", @"Should've decoded comp name into lowercase");
	
	p.codeToNil = @"Something";
	
	NSDictionary *sendDict = [p remoteDictionaryRepresentationWrapped:NO];
	STAssertTrue([[sendDict objectForKey:@"locally_url"] isKindOfClass:[NSString class]],@"Should've encoded NSURL -> string");
	STAssertTrue([[sendDict objectForKey:@"code_to_nil"] isKindOfClass:[NSNull class]], @"Should've encoded codeToNil into NSNull");
	STAssertEqualObjects([sendDict objectForKey:@"locally_url"], @"http://nsrails.com", @"Should've encoded into string & retain content");
	STAssertEqualObjects([sendDict objectForKey:@"locally_lowercase"], @"lowercase?", @"Should've kept as lowercase");
	STAssertEqualObjects([sendDict objectForKey:@"remotely_uppercase"], @"UPPER", @"Should've encoded to uppercase");
	STAssertEqualObjects([sendDict objectForKey:@"date_override_send"], @"override!", @"Should've overriden NSDate encode");
	STAssertEqualObjects([sendDict objectForKey:@"date_override_ret"], @"1969-12-31T19:00:00Z", @"Should've overriden NSDate decode");
	STAssertEqualObjects(p.componentWithFlippingName.componentName, @"COMP LOWERCASE?", @"Should've encoded comp name into uppercase");
	
	STAssertEqualObjects([sendDict objectForKey:@"remote_only"], @"remote", @"Should've captured remoteOnly!");
	
	p.encodeNonJSON = YES;
	
	STAssertThrowsSpecificNamed([p remoteDictionaryRepresentationWrapped:NO], NSException, NSRailsJSONParsingException, @"Encoding into non-JSON for sendable dict - where's the error?");
}

- (void) test_send_retrieve
{
	PickySender *p = [[PickySender alloc] init];
	p.local = @"local";
	p.sendOnly = @"send--local";
	p.undefined = @"local";
	[p setPropertiesUsingRemoteDictionary:[MockServer newPickySender]];
	
	STAssertEqualObjects(p.local, @"local", @"Should've kept local... -x");
	STAssertEqualObjects(p.sendOnly, @"send--local", @"Should've kept send... -s");
	STAssertEqualObjects(p.retrieveOnly, @"retrieve", @"Should've set retrieve... -r");
	STAssertEqualObjects(p.shared, @"shared", @"Should've set shared... blank");
	STAssertEqualObjects(p.sharedExplicit, @"shared explicit", @"Should've set sharedExplicit... -rs");
	STAssertEqualObjects(p.undefined, @"local", @"Shouldn't have set undefined... not in NSRS");
	
	NSDictionary *sendDict = [p remoteDictionaryRepresentationWrapped:NO];
	STAssertNil([sendDict objectForKey:@"retrieve_only"], @"Shouldn't send retrieve-only... -r");
	STAssertNil([sendDict objectForKey:@"local"], @"Shouldn't send local-only... -x");
	STAssertNil([sendDict objectForKey:@"undefined"], @"Shouldn't send undefined... not in NSRS");
	STAssertEqualObjects([sendDict objectForKey:@"send_only"], @"send--local", @"Should've sent send... -s");
	STAssertEqualObjects([sendDict objectForKey:@"shared"], @"shared", @"Should've sent shared... blank");
	STAssertEqualObjects([sendDict objectForKey:@"shared_explicit"], @"shared explicit", @"Should've sent sharedExplicit... -rs");
}

- (void) test_nesting_dictionaries
{
	DictionaryNester *nester = [[DictionaryNester alloc] initWithRemoteDictionary:[MockServer newDictionaryNester]];
	STAssertNotNil(nester.dictionaries, @"Dictionaries shouldn't be nil after JSON set");
	STAssertTrue(nester.dictionaries.count == 2, @"Dictionaries should have 2 elements");
	STAssertTrue([[nester.dictionaries objectAtIndex:0] isKindOfClass:[NSDictionary class]], @"Dictionaries obj should be of type NSDictionary");
	STAssertEqualObjects([[nester.dictionaries objectAtIndex:0] objectForKey:@"so"], @"im", @"Dict elements should've been set");
	
	nester.dictionaries = [NSArray arrayWithObjects:[NSDictionary dictionaryWithObject:@"obj" forKey:@"key"], [NSDictionary dictionaryWithObject:@"obj2" forKey:@"key2"], nil];
	
	NSDictionary *send = [nester remoteDictionaryRepresentationWrapped:NO];
	
	STAssertNotNil(send, @"Dictionaries shouldn't be nil after trying to make it");
	STAssertTrue([[send objectForKey:@"dictionaries_attributes"] count] == 2, @"Dictionaries should have 2 elements");
	STAssertTrue([[[send objectForKey:@"dictionaries_attributes"] objectAtIndex:0] isKindOfClass:[NSDictionary class]], @"Dictionaries obj should be of type NSDictionary");
	STAssertEqualObjects([[[send objectForKey:@"dictionaries_attributes"] objectAtIndex:0] objectForKey:@"key"], @"obj", @"Dict elements should've been set");
}

- (void) test_array_of_dates
{
	LadiesMan *guy = [[LadiesMan alloc] initWithRemoteDictionary:[MockServer newLadiesMan]];
	STAssertNotNil(guy.lotsOfDates, @"Dates shouldn't be nil after JSON set");
	STAssertTrue(guy.lotsOfDates.count == 3, @"Should have 3 dates");
	STAssertTrue([[guy.lotsOfDates objectAtIndex:0] isKindOfClass:[NSDate class]], @"Date obj should be of type NSDate");
	
	NSDictionary *send = [guy remoteDictionaryRepresentationWrapped:NO];
	
	STAssertNotNil([send objectForKey:@"lots_of_dates_attributes"], @"Dates shouldn't be nil after remote dict");
	STAssertTrue([[send objectForKey:@"lots_of_dates_attributes"] count] == 3, @"Send should have 3 dates");
	STAssertTrue([[[send objectForKey:@"lots_of_dates_attributes"] lastObject] isKindOfClass:[NSString class]], @"Date obj should be of type NSString on send");
	STAssertEqualObjects([[send objectForKey:@"lots_of_dates_attributes"] lastObject], @"2012-05-07T04:41:52Z", @"Converted date should be equal to original val");
}

- (void) test_set_properties
{
	//This also makes sure it doesn't confuse the property_tester model key and property_tester attribute
	
	PropertyTester *t = [[PropertyTester alloc] init];
	STAssertNil(t.remoteAttributes, @"Shouldn't have any remoteAttributes on first init");
	
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:@"test", @"property_tester", nil];
	
	BOOL ch = [t setPropertiesUsingRemoteDictionary:dict];
	STAssertEqualObjects(t.propertyTester, @"test", @"");
	STAssertTrue(ch, @"Should've been changes first time around");
	STAssertNil(t.remoteAttributes, @"Shouldn't have any remoteAttributes after setting props");
	
	BOOL ch2 = [t setPropertiesUsingRemoteDictionary:dict];
	STAssertFalse(ch2, @"Should've been no changes when setting to no dict");
	
	t.propertyTester = nil;
	
	NSDictionary *dictEnveloped = [[NSDictionary alloc] initWithObjectsAndKeys:[[NSDictionary alloc] initWithObjectsAndKeys:@"test",@"property_tester", nil], @"property_tester", nil];
	BOOL ch3 = [t setPropertiesUsingRemoteDictionary:dictEnveloped];
	STAssertEqualObjects(t.propertyTester, @"test", @"");
	STAssertFalse(ch2, @"Should've been no changes when setting to inner dict");
	
	BOOL b;
	STAssertNoThrow(b = [t setPropertiesUsingRemoteDictionary:nil], @"Shouldn't blow up on setting to nil dictionary");
	STAssertFalse(b, @"Shouldn't be a change if nil JSON");

	STAssertNoThrow([t setPropertiesUsingRemoteDictionary:NSRDictionary([NSNull null], @"property_tester")], @"Shouldn't blow up, just issue a warning");
	STAssertNoThrow([t setPropertiesUsingRemoteDictionary:NSRDictionary(NSRDictionary([NSNull null], @"property1"), @"property_tester")], @"Shouldn't blow up on setting to a null JSON value");
	
	STAssertNil(t.propertyTester, @"propertyTester should be nil after setting from JSON");

	t.propertyTester = [[NSScanner alloc] init];
	STAssertNoThrow([t remoteDictionaryRepresentationWrapped:NO], @"Shouldn't blow up on making a DICT");
	STAssertThrows([t remoteCreate:nil], @"Should blow up on making bad JSON");
	STAssertNil(t.remoteAttributes, @"Shouldn't have any remoteAttributes, even after failed remoteCreate");
}


- (void) test_serialization
{
	NSString *file = [NSHomeDirectory() stringByAppendingPathComponent:@"test.dat"];
	
	Empty *e = [[Empty alloc] init];
	e.remoteID = [NSNumber numberWithInt:5];
	BOOL s = [NSKeyedArchiver archiveRootObject:e toFile:file];
	
	STAssertTrue(s, @"Archiving should've worked (serialize)");
	
	Empty *eRetrieve = [NSKeyedUnarchiver unarchiveObjectWithFile:file];
	STAssertEqualObjects(e.remoteID, eRetrieve.remoteID, @"Should've carried over remoteID");
	

	Empty *eCustomSync = [[Empty alloc] initWithCustomSyncProperties:@"custom"];
	s = [NSKeyedArchiver archiveRootObject:eCustomSync toFile:file];
	
	STAssertTrue(s, @"Archiving should've worked (serialize)");
	
	Empty *eCustomSyncRetrieve = [NSKeyedUnarchiver unarchiveObjectWithFile:file];
	NSRAssertEqualArraysNoOrder(eCustomSyncRetrieve.propertyCollection.properties.allKeys, NSRArray(@"custom", @"remoteID"));

	Empty *eCustomSyncConfig = [[Empty alloc] initWithCustomSyncProperties:@"custom" customConfig:[[NSRConfig alloc] initWithAppURL:@"URL"]];
	s = [NSKeyedArchiver archiveRootObject:eCustomSyncConfig toFile:file];
	
	STAssertTrue(s, @"Archiving should've worked (serialize)");
	
	Empty *eCustomSyncConfigRetrieve = [NSKeyedUnarchiver unarchiveObjectWithFile:file];
	STAssertEqualObjects(eCustomSyncConfigRetrieve.propertyCollection.customConfig.appURL, @"URL", @"Config should carry over");

	
	CustomGuy *guy = [[CustomGuy alloc] init];
	s = [NSKeyedArchiver archiveRootObject:guy toFile:file];
	
	STAssertTrue(s, @"Archiving should've worked (serialize)");
	
	CustomGuy *guyRetrieve = [NSKeyedUnarchiver unarchiveObjectWithFile:file];
	NSRAssertEqualArraysNoOrder(guyRetrieve.propertyCollection.properties.allKeys, NSRArray(@"something", @"remoteID"));
	STAssertEqualObjects(guyRetrieve.propertyCollection.customConfig.appURL, @"url", @"Config should carry over");
	STAssertEqualObjects(guyRetrieve.propertyCollection.customConfig.appUsername, @"user", @"Config should carry over");
	STAssertEqualObjects(guyRetrieve.propertyCollection.customConfig.appPassword, @"pass", @"Config should carry over");
}

- (void)setUpClass
{
	// Run at start of all tests in the class
}

- (void)tearDownClass {
	// Run at end of all tests in the class
}

- (void)setUp
{
	// Run before each test method
}

- (void)tearDown {
	// Run after each test method
}

@end