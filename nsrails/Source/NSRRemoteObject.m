/*
 
 _|_|_|    _|_|  _|_|  _|_|  _|  _|      _|_|           
 _|  _|  _|_|    _|    _|_|  _|  _|_|  _|_| 
 
 NSRRemoteObject.m
 
 Copyright (c) 2012 Dan Hassin.
 
 Permission is hereby granted, free of charge, to any person obtaining
 a copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

#import "NSRRemoteObject.h"

#import "NSRails.h"

#import "NSString+Inflection.h"
#import <objc/runtime.h>


////////////////////////////////////////////////////////////////////////////////////////////////////

@interface NSRRemoteObject (private)

- (NSDictionary *) remoteDictionaryRepresentationWrapped:(BOOL)wrapped fromNesting:(BOOL)nesting;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////


@implementation NSRRemoteObject
@synthesize remoteDestroyOnNesting, remoteAttributes;

#ifdef NSR_USE_COREDATA
@dynamic remoteID;
#else
@synthesize remoteID;
#endif

#pragma mark - Overrides

#pragma mark - Private

- (void) nsr_setValue:(id)value forKey:(NSString *)key
{
	[self setValue:value forKey:key];
}

- (id) nsr_valueForKey:(NSString *)key
{
	return [self valueForKey:key];
}

#pragma mark Encouraged

+ (NSString *) remoteModelName
{
	if (self == [NSRRemoteObject class])
		return nil;
	
	//Default behavior is to return name of this class
	
	NSString *class = NSStringFromClass(self);
	
	if ([NSRConfig relevantConfigForClass:self].autoinflectsClassNames)
	{
		return [class nsr_stringByUnderscoringIgnoringPrefix:[NSRConfig relevantConfigForClass:self].ignoresClassPrefixes];
	}
	else
	{
		return class;
	}
}

+ (NSString *) remoteControllerName
{
	NSString *singular = [self remoteModelName];
	
	//Default behavior is to return pluralized model name
	
	//Arbitrary pluralization - should probably support more
	if ([singular isEqualToString:@"person"])
		return @"people";
	
	if ([singular isEqualToString:@"Person"])
		return @"People";
	
	if ([singular hasSuffix:@"y"] && ![singular hasSuffix:@"ey"])
		return [[singular substringToIndex:singular.length-1] stringByAppendingString:@"ies"];
	
	if ([singular hasSuffix:@"s"])
		return [singular stringByAppendingString:@"es"];
	
	return [singular stringByAppendingString:@"s"];
}

- (BOOL) propertyIsDate:(NSString *)property
{
	NSString *type = [self.class typeForProperty:property];
	return [type isEqualToString:@"@\"NSDate\""];
}

+ (NSString *) typeForProperty:(NSString *)prop
{
	objc_property_t property = class_getProperty(self, [prop UTF8String]);
	if (!property)
		return nil;
	
	// This will return some garbage like "Ti,GgetFoo,SsetFoo:,Vproperty"
	// See https://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html
	
	NSString *atts = [NSString stringWithCString:property_getAttributes(property) encoding:NSUTF8StringEncoding];
	
	for (NSString *att in [atts componentsSeparatedByString:@","])
		if ([att hasPrefix:@"T"])
			return [att substringFromIndex:1];
	
	return nil;
}

+ (NSMutableArray *) remotePropertiesForClass:(Class)c
{
	unsigned int propertyCount;
	
	objc_property_t *properties = class_copyPropertyList(c, &propertyCount);
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:propertyCount];
	
	if (properties)
	{
		while (propertyCount--)
		{
			NSString *name = [NSString stringWithCString:property_getName(properties[propertyCount]) encoding:NSASCIIStringEncoding];
			
			// makes sure it's not primitive
			if ([[self typeForProperty:name] rangeOfString:@"@"].location != NSNotFound)
 			{
				[results addObject:name];
			}
		}
		
		free(properties);
	}
	
	if (c == [NSRRemoteObject class])
	{
		return results;
	}
	else
	{
		NSMutableArray *superProps = [self remotePropertiesForClass:c.superclass];
		[superProps addObjectsFromArray:results];
		return superProps;
	}
}

- (NSMutableArray *) remoteProperties
{
	NSMutableArray *master = [self.class remotePropertiesForClass:self.class];
	[master removeObject:@"remoteAttributes"];
	return master;
}

- (NSRRemoteObject *) objectUsedToPrefixRequest:(NSRRequest *)verb
{
	return nil;
}

- (NSRRelationship *) relationshipForProperty:(NSString *)property
{
	if (self.managedObjectContext)
	{
		NSRelationshipDescription *cdRelation = [[self.entity relationshipsByName] objectForKey:property];
		if (cdRelation)
		{
			Class class = NSClassFromString(cdRelation.destinationEntity.name);
			if (cdRelation.isToMany)
				return [NSRRelationship hasMany:class];
			if (cdRelation.maxCount == 1)
				return [NSRRelationship hasOne:class];
		}
	}
	
	NSString *propType = [[[self.class typeForProperty:property] stringByReplacingOccurrencesOfString:@"\"" withString:@""] stringByReplacingOccurrencesOfString:@"@" withString:@""];

	Class class = NSClassFromString(propType);
	if ([class isSubclassOfClass:[NSRRemoteObject class]])
	{
		return [NSRRelationship hasOne:class];
	}
	
	return nil;
}

- (id) encodeValueForProperty:(NSString *)property remoteKey:(NSString **)remoteKey
{	
	if ([property isEqualToString:@"remoteID"])
		*remoteKey = @"id";
	
	NSRRelationship *relationship = [self relationshipForProperty:property];
		
	id val = [self nsr_valueForKey:property];

	if (relationship)
	{
		//if it's belongs_to, only return the ID
		if (relationship.isBelongsTo)
		{			
			*remoteKey = [*remoteKey stringByAppendingString:@"_id"];
			return [val remoteID];
		}
		
		*remoteKey = [*remoteKey stringByAppendingString:@"_attributes"];
		
		if (relationship.isToMany)
		{
			NSMutableArray *new = [NSMutableArray arrayWithCapacity:[val count]];
			
			for (id element in val)
			{
				id encodedObj = [element remoteDictionaryRepresentationWrapped:NO fromNesting:YES];
				[new addObject:encodedObj];
			}
			
			return new;
		}
		
		return [val remoteDictionaryRepresentationWrapped:NO fromNesting:YES];
	}

	if ([val isKindOfClass:[NSDate class]])
	{
		return [[NSRConfig relevantConfigForClass:self.class] stringFromDate:val];
	}

	return val;
}

- (NSString *) propertyForRemoteKey:(NSString *)remoteKey
{
	NSString *property = remoteKey;
	
	if ([NSRConfig defaultConfig].autoinflectsPropertyNames)
		property = [property nsr_stringByCamelizing];
	
	if ([remoteKey isEqualToString:@"id"])
		property = @"remoteID";
	
	if (![self.remoteProperties containsObject:property])
		return nil;
	
	return property;
}

- (void) decodeRemoteValue:(id)railsObject forRemoteKey:(NSString *)remoteKey change:(BOOL *)change
{
	NSString *property = [self propertyForRemoteKey:remoteKey];
	
	if (!property)
		return;

	NSRRelationship *relationship = [self relationshipForProperty:property];
	
	id previousVal = [self nsr_valueForKey:property];
	id decodedObj = nil;
	
	BOOL changes = -1;
	
	if (railsObject)
	{
		if (relationship.isToMany)
		{
			changes = NO;
			
			BOOL checkForChange = ([railsObject count] == [previousVal count]);
			if (!checkForChange)
				changes = YES;
			
			if (self.entity)
			{
				BOOL ordered = [[[self.entity propertiesByName] objectForKey:property] isOrdered];
				
				if (ordered)
					decodedObj = [[NSMutableOrderedSet alloc] init];
				else
					decodedObj = [[NSMutableSet alloc] init];
			}
			else
			{
				decodedObj = [[NSMutableArray alloc] init];
			}
			
			//array of NSRRemoteObjects is tricky, we need to go through each existing element, see if it needs an update (or delete), and then add any new ones
			
			id previousArray = ([previousVal isKindOfClass:[NSSet class]] ? 
								[previousVal allObjects] :
								[previousVal isKindOfClass:[NSOrderedSet class]] ?
								[previousVal array] :
								previousVal);
			
			for (id railsElement in railsObject)
			{
				id decodedElement;
				
				//see if there's a nester that matches this ID - we'd just have to update it w/this dict
				NSNumber *railsID = [railsElement objectForKey:@"id"];
				id existing = nil;
				
				if (railsID)
					existing = [[previousArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"remoteID == %@",railsID]] lastObject];
				
				if (!existing)
				{
					//didn't previously exist - make a new one
					decodedElement = [relationship.nestedClass objectWithRemoteDictionary:railsElement];
					
					changes = YES;
				}
				else
				{
					//existed - simply update that one (recursively)
					decodedElement = existing;
					BOOL neededChange = [decodedElement setPropertiesUsingRemoteDictionary:railsElement];
					
					if (neededChange)
						changes = YES;
				}
				
				[decodedObj addObject:decodedElement];
			}
		}
		else if ([self propertyIsDate:property])
		{
			decodedObj = [[NSRConfig relevantConfigForClass:self.class] dateFromString:railsObject];
			
			//account for any discrepancies between NSDate object and a string (which doesn't include milliseconds) 
			CGFloat diff = fabs([decodedObj timeIntervalSinceDate:previousVal]);
			changes = (!previousVal || (diff > 1.25));
		}
		else if (relationship)
		{
			//if the nested object didn't exist before, make it & set it
			if (!previousVal)
			{
				decodedObj = [relationship.nestedClass objectWithRemoteDictionary:railsObject];
			}
			//otherwise, keep the old object & only mark as change if its properties changed (recursive)
			else
			{
				decodedObj = previousVal;
				
				changes = [decodedObj setPropertiesUsingRemoteDictionary:railsObject];
			}
		}
		//otherwise, if not nested or anything, just use what we got (number, string, dictionary, array)
		else
		{
			decodedObj = railsObject;
		}
	}
	
	//means we should check for straight equality (no *change was set)
	if (changes == -1)
	{
		changes = NO;

		//if it existed before but now nil, mark change
		if (!decodedObj && previousVal)
		{
			changes = YES;
		}
		else if (decodedObj)
		{
			changes = ![decodedObj isEqual:previousVal];
		}
	}
	
	*change = changes;
	
	[self nsr_setValue:decodedObj forKey:property];
}

- (BOOL) shouldSendProperty:(NSString *)property whenNested:(BOOL)nested
{
	//don't include id if it's nil or on the main object (nested guys need their IDs)
	if ([property isEqualToString:@"remoteID"] && (!self.remoteID || !nested))
		return NO;
	
	//don't include updated_at or created_at
	if ([property isEqualToString:@"createdAt"] || [property isEqualToString:@"updatedAt"])
		return NO;
	
	NSRRelationship *relationship = [self relationshipForProperty:property];
	
	if (relationship && !relationship.isBelongsTo)
	{
		if (nested)
		{
			//this is recursion-protection. we don't want to include every nested class in this class because one of those nested class could nest us, causing infinite loop
			//  we are safe to include all nestedclasses on top-level (if not from within nesting)
			//  if we are a class being nested, we have to be careful - only inlude nestedclass attrs that were defined with -n
			//     except if belongs-to, since then attrs aren't being included - just "_id"

			return NO;
		}
		
		id val = [self nsr_valueForKey:property];
		
		//it's an _attributes. don't send if there's no val or empty (is okay on belongs_to bc we send a null id)
		if (!val || (relationship.isToMany && [val count] == 0))
		{
			return NO;
		}
	}
	
	return YES;
}

#pragma mark - Internal NSR stuff

- (BOOL) setPropertiesUsingRemoteDictionary:(NSDictionary *)dict
{
	remoteAttributes = dict;
	
	//support JSON that comes in like {"post"=>{"something":"something"}}
	NSDictionary *innerDict = [dict objectForKey:[self.class remoteModelName]];
	if (dict.count == 1 && [innerDict isKindOfClass:[NSDictionary class]])
	{
		dict = innerDict;
	}
	
	BOOL changes = NO;
	
	for (NSString *remoteKey in dict)
	{
		id remoteObject = [dict objectForKey:remoteKey];
		if (remoteObject == [NSNull null])
			remoteObject = nil;

		BOOL change = NO;
		[self decodeRemoteValue:remoteObject forRemoteKey:remoteKey change:&change];

		if (change)
			changes = YES;
	}
	
	if (changes)
		[self saveContext];
	
	return changes;
}

- (NSDictionary *) remoteDictionaryRepresentationWrapped:(BOOL)wrapped
{
	return [self remoteDictionaryRepresentationWrapped:wrapped fromNesting:NO];
}

- (NSDictionary *) remoteDictionaryRepresentationWrapped:(BOOL)wrapped fromNesting:(BOOL)nesting
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	
	for (NSString *objcProperty in [self remoteProperties])
	{
		if (![self shouldSendProperty:objcProperty whenNested:nesting])
			continue;
		
		NSString *remoteKey = objcProperty;
		if ([NSRConfig defaultConfig].autoinflectsPropertyNames)
			remoteKey = [remoteKey nsr_stringByUnderscoring];
		
		id remoteRep = [self encodeValueForProperty:objcProperty remoteKey:&remoteKey];
		if (!remoteRep)
			remoteRep = [NSNull null];
		
		BOOL JSONParsable = ([remoteRep isKindOfClass:[NSArray class]] ||
							 [remoteRep isKindOfClass:[NSDictionary class]] ||
							 [remoteRep isKindOfClass:[NSString class]] ||
							 [remoteRep isKindOfClass:[NSNumber class]] ||
							 [remoteRep isKindOfClass:[NSNull class]]);
		
		if (!JSONParsable)
		{
			[NSException raise:NSRJSONParsingException format:@"Trying to encode property '%@' in class '%@', but the result (%@) was not JSON-parsable. Override -[NSRRemoteObject encodeValueForProperty:remoteKey:] if you want to encode a property that's not NSDictionary, NSArray, NSString, NSNumber, or NSNull. Remember to call super if it doesn't need custom encoding.",objcProperty, self.class, remoteRep];
		}
		
		
		[dict setObject:remoteRep forKey:remoteKey];
	}
	
	if (remoteDestroyOnNesting)
	{
		[dict setObject:[NSNumber numberWithBool:YES] forKey:@"_destroy"];
	}
	
	if (wrapped)
		return [NSDictionary dictionaryWithObject:dict forKey:[self.class remoteModelName]];
	
	return dict;
}


+ (id) objectWithRemoteDictionary:(NSDictionary *)dict
{
	NSRRemoteObject *obj = nil;
	
#ifdef NSR_USE_COREDATA
	NSNumber *objID = [dict objectForKey:@"id"];

	if (objID)
		obj = [self findObjectWithRemoteID:objID];
	
	if (!obj)
		obj = [[self alloc] initInserted];
#else
	obj = [[self alloc] init];
#endif
	
	[obj setPropertiesUsingRemoteDictionary:dict];

	return obj;
}

#pragma mark - CoreData

- (NSManagedObjectContext *) managedObjectContext
{
#ifdef NSR_USE_COREDATA
	return [super managedObjectContext];
#else	
	return nil;
#endif
}

- (NSEntityDescription *) entity
{
#ifdef NSR_USE_COREDATA
	return [super entity];
#else	
	return nil;
#endif
}

+ (NSString *) entityName
{
	return [self description];
}

- (BOOL) saveContext 
{
	if (!self.managedObjectContext)
		return NO;
	
	NSError *error = nil;
	if (![self.managedObjectContext save:&error])
	{
		//TODO
		// maybe notify a client delegate to handle this error?
		// raise exception?
		
		NSLog(@"NSR Warning: Failed to save CoreData context with error %@", error);
	}
	
	return !error;
}

+ (id) findObjectWithRemoteID:(NSNumber *)rID
{
	if ([self class] == [NSRRemoteObject class])
	{
		[NSException raise:NSRCoreDataException format:@"Attempt to call %@ on NSRRemoteObject. Call this on your subclass!",NSStringFromSelector(_cmd)];
	}
	
	return [self findFirstObjectByAttribute:@"remoteID" 
								  withValue:rID
								  inContext:[self getGlobalManagedObjectContextFromCmd:_cmd]];
}

+ (id) findFirstObjectByAttribute:(NSString *)attrName withValue:(id)value inContext:(NSManagedObjectContext *)context
{
	NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:self.entityName];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K == %@", attrName, value];
	fetch.predicate = predicate;
	fetch.fetchLimit = 1;
	
	NSError *error = nil;
	NSArray *results = [context executeFetchRequest:fetch error:&error];
	if (results.count > 0) 
	{
		return [results objectAtIndex:0];
	}
	return nil;
}

+ (NSManagedObjectContext *) getGlobalManagedObjectContextFromCmd:(SEL)cmd
{
	NSManagedObjectContext *ctx = [NSRConfig relevantConfigForClass:self].managedObjectContext;
	if (!ctx)
	{
		[NSException raise:NSRCoreDataException format:@"-[%@ %@] called when the current config's managedObjectContext is nil. A vaild managedObjectContext is necessary when using CoreData. Set your managed object context like so: [[NSRConfig defaultConfig] setManagedObjectContext:<#your moc#>].", self.class, NSStringFromSelector(cmd)];
	}
	return ctx;
}

- (id) initInserted
{
	if (![self isKindOfClass:[NSManagedObject class]])
	{
		[NSException raise:NSRCoreDataException format:@"Trying to use NSRails with CoreData? Go in NSRails.h and uncomment `#define NSR_CORE_DATA`. You can also add NSR_USE_COREDATA to \"Preprocessor Macros Not Used in Precompiled Headers\" in your target's build settings."];
	}
	
	NSManagedObjectContext *context = [[self class] getGlobalManagedObjectContextFromCmd:_cmd];
	self = [NSEntityDescription insertNewObjectForEntityForName:[self.class entityName]
										 inManagedObjectContext:context];
	
	return self;
}

- (BOOL) validateRemoteID:(id *)value error:(NSError **)error 
{
	if ([*value intValue] == 0)
		return YES;
	
	NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:self.class.entityName];
	fetch.includesPropertyValues = NO;
	fetch.fetchLimit = 1;
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(remoteID == %@) && (self != %@)", *value, self];
	fetch.predicate = predicate;
	
	NSArray *results = [[(id)self managedObjectContext] executeFetchRequest:fetch error:NULL];
	
	if (results.count > 0)
	{
		*error = [NSError errorWithDomain:NSRCoreDataException 
									 code:0
								 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@ with remoteID %@ already exists",self.class,*value] forKey:NSLocalizedDescriptionKey]];
		
		return NO;
	}
	else
	{
		return YES;
	}
}

#pragma mark - Create

- (BOOL) remoteCreate:(NSError **)error
{
	NSDictionary *jsonResponse = [[NSRRequest requestToCreateObject:self] sendSynchronous:error];

	if (jsonResponse)
		[self setPropertiesUsingRemoteDictionary:jsonResponse];
	
	return !!jsonResponse;
}

- (void) remoteCreateAsync:(NSRBasicCompletionBlock)completionBlock
{
	[[NSRRequest requestToCreateObject:self] sendAsynchronous:
	 ^(id result, NSError *error) 
	 {
		 if (result)
			 [self setPropertiesUsingRemoteDictionary:result];
		 
		 completionBlock(error);
	 }];
}


#pragma mark Update

- (BOOL) remoteUpdate:(NSError **)error
{
	if (![[NSRRequest requestToUpdateObject:self] sendSynchronous:error])
		return NO;
	
	[self saveContext];
	return YES;
}

- (void) remoteUpdateAsync:(NSRBasicCompletionBlock)completionBlock
{
	[[NSRRequest requestToUpdateObject:self] sendAsynchronous:
	 ^(id result, NSError *error) 
	 {
		 if (!error)
			 [self saveContext];
		 
		 completionBlock(error);
	 }];
}

#pragma mark Replace

- (BOOL) remoteReplace:(NSError **)error
{
	if (![[NSRRequest requestToReplaceObject:self] sendSynchronous:error])
		return NO;
	
	[self saveContext];
	return YES;
}

- (void) remoteReplaceAsync:(NSRBasicCompletionBlock)completionBlock
{
	[[NSRRequest requestToReplaceObject:self] sendAsynchronous:
	 ^(id result, NSError *error) 
	 {
		 if (!error)
			 [self saveContext];
		 
		 completionBlock(error);
	 }];
}

#pragma mark Destroy

- (BOOL) remoteDestroy:(NSError **)error
{
	if (![[NSRRequest requestToDestroyObject:self] sendSynchronous:error])
		return NO;
	
	[self.managedObjectContext deleteObject:(id)self];
	[self saveContext];
	return YES;
}

- (void) remoteDestroyAsync:(NSRBasicCompletionBlock)completionBlock
{
	[[NSRRequest requestToDestroyObject:self] sendAsynchronous:
	 ^(id result, NSError *error) 
	 {
		 if (!error)
		 {
			 [self.managedObjectContext deleteObject:(id)self];
			 [self saveContext];
		 }
		 completionBlock(error);
	 }];
}

#pragma mark Get latest

- (BOOL) remoteFetch:(NSError **)error changes:(BOOL *)changesPtr
{
	NSDictionary *jsonResponse = [[NSRRequest requestToFetchObject:self] sendSynchronous:error];
	
	if (!jsonResponse)
	{
		if (changesPtr)
			*changesPtr = NO;
		return NO;
	}
	
	BOOL changes = [self setPropertiesUsingRemoteDictionary:jsonResponse];
	if (changesPtr)
		*changesPtr = changes;
	
	return YES;
}

- (BOOL) remoteFetch:(NSError **)error
{
	return [self remoteFetch:error changes:NULL];
}

- (void) remoteFetchAsync:(NSRFetchCompletionBlock)completionBlock
{
	[[NSRRequest requestToFetchObject:self] sendAsynchronous:
	 ^(id jsonRep, NSError *error) 
	 {
		 BOOL change = NO;
		 if (jsonRep)
			 change = [self setPropertiesUsingRemoteDictionary:jsonRep];
		 completionBlock(change, error);
	 }];
}

#pragma mark Get specific object (class-level)

+ (id) remoteObjectWithID:(NSNumber *)mID error:(NSError **)error
{
	NSDictionary *objData = [[NSRRequest requestToFetchObjectWithID:mID ofClass:self] sendSynchronous:error];
	
	if (objData)
	{
		return [[self class] objectWithRemoteDictionary:objData];
	}
	
	return nil;
}

+ (void) remoteObjectWithID:(NSNumber *)mID async:(NSRFetchObjectCompletionBlock)completionBlock
{
	[[NSRRequest requestToFetchObjectWithID:mID ofClass:self] sendAsynchronous:
	 ^(id jsonRep, NSError *error) 
	 {
		 if (!jsonRep)
		 {
			 completionBlock(nil, error);
		 }
		 else
		 {
			 id obj = [[self class] objectWithRemoteDictionary:jsonRep];
			 completionBlock(obj, nil);
		 }
	 }];
}

#pragma mark Get all objects (class-level)

+ (NSArray *) remoteAll:(NSError **)error
{
	return [self remoteAllViaObject:nil error:error];
}

+ (NSArray *) remoteAllViaObject:(NSRRemoteObject *)obj error:(NSError **)error
{
    id json = [[NSRRequest requestToFetchAllObjectsOfClass:self viaObject:obj] sendSynchronous:error];
    if (!json)
		return nil;
	
	[json translateRemoteDictionariesIntoInstancesOfClass:self.class];
    
    return json;
}

+ (void) remoteAllAsync:(NSRFetchAllCompletionBlock)completionBlock
{
	[self remoteAllViaObject:nil async:completionBlock];
}

+ (void) remoteAllViaObject:(NSRRemoteObject *)obj async:(NSRFetchAllCompletionBlock)completionBlock
{
    [[NSRRequest requestToFetchAllObjectsOfClass:self viaObject:obj] sendAsynchronous:
	 ^(id result, NSError *error) 
	 {
		 if (result)
			 [result translateRemoteDictionariesIntoInstancesOfClass:[self class]];

		 completionBlock(result,error);
	 }];
}

#pragma mark - NSCoding

- (id) initWithCoder:(NSCoder *)aDecoder
{
	if (self = [super init])
	{
		self.remoteID = [aDecoder decodeObjectForKey:@"remoteID"];
		remoteAttributes = [aDecoder decodeObjectForKey:@"remoteAttributes"];
		self.remoteDestroyOnNesting = [aDecoder decodeBoolForKey:@"remoteDestroyOnNesting"];
	}
	return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:self.remoteID forKey:@"remoteID"];
	[aCoder encodeObject:remoteAttributes forKey:@"remoteAttributes"];
	[aCoder encodeBool:remoteDestroyOnNesting forKey:@"remoteDestroyOnNesting"];
}

@end

