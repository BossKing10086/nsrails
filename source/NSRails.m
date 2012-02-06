//
//  NSRailsModel.m
//  NSRails
//
//  Created by Dan Hassin on 1/10/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRails.h"

#import "NSString+InflectionSupport.h"
#import <objc/runtime.h>

#import "NSData+Additions.h"


// if it's too intimidating, remember that you can navigate this file quickly in xcode with #pragma marks


//this will be the NSRailsProperties for NSRailsModel
//tie modelID to rails property id
#define NSRAILS_BASE_PROPS @"modelID=id"


@interface NSRailsModel (internal)

+ (NSMutableArray *) ivarNames;

- (void) setAttributesAsPerDictionary:(NSDictionary *)dict;

- (NSDictionary *) dictionaryOfRelevantProperties;
- (NSString *) getIvarType:(NSString *)ivar;
- (SEL) getIvarSetter:(NSString *)ivar;
- (SEL) getIvarGetter:(NSString *)ivar;

@end


@implementation NSRailsModel
@synthesize modelID, attributes, destroyOnNesting;

static NSRConfig *config = nil;

#pragma mark -
#pragma mark Meta-NSR stuff

//this will suppress the compiler warnings that come with ARC when doing performSelector
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

+ (NSString *) NSRailsProperties
{
	return NSRAILS_BASE_PROPS;
}

+ (NSString *) railsProperties
{
	NSString *base = NSRAILS_BASE_PROPS;
	
	if ([[self NSRailsProperties] rangeOfString:_NSRNoCarryFromSuper_STR].location != NSNotFound)
	{
		//always want to keep base (modelID) even if nosuper
		return [base stringByAppendingFormat:@", %@",[self NSRailsProperties]];
	}
	else
	{
		for (Class c = self; c != [NSRailsModel class]; c = [c superclass])
		{
			if ([c respondsToSelector:@selector(NSRailsProperties)])
			{
				base = [base stringByAppendingFormat:@", %@", [c NSRailsProperties]];
			}
		}
		//make sure none of the superclasses this inherited from declared a NSRNoCarryFromSuper
		//(otherwise it'll screw up the check to see if THIS class wants to do a nosuper)
		return [base stringByReplacingOccurrencesOfString:_NSRNoCarryFromSuper_STR withString:@""];
	}
}

+ (void) setClassConfig:(NSRConfig *)_config
{
	config = _config;
}

+ (NSString *) getModelName
{
	//if defined through NSRailsModelName() then use that instead
	SEL sel = @selector(NSRailsModelName);
	if ([self respondsToSelector:sel])
	{
		return [self performSelector:sel];
	}
	
	//otherwise, return name of the class
	NSString *class = NSStringFromClass(self);
	if ([class isEqualToString:@"NSRailsModel"])
		class = nil;
	
#ifdef NSRAutomaticallyUnderscoreAndCamelize
	return [class underscore];
#else
	return class;
#endif
}

+ (NSString *) getPluralModelName
{
	//if defined through NSRailsModelNameWithPlural(), use that instead
	SEL sel = @selector(NSRailsModelNameWithPlural);
	if ([self respondsToSelector:sel])
	{
		return [self performSelector:sel];
	}
	//otherwise, pluralize ModelName
	return [[self getModelName] pluralize];
}

//convenience
- (NSString *) camelizedModelName
{
	return [[[[self class] getModelName] camelize] toClassName];
}

- (id) initWithRailsifyString:(NSString *)props
{
	if ((self = [super init]))
	{
		//log on param string for testing
		//NSLog(@"found props %@",props);
		
		
		//get the config for this class
		if (!config)
		{
			if ([[self class] respondsToSelector:@selector(NSRailsSetConfigAuth)])
			{
				config = [[self class] performSelector:@selector(NSRailsSetConfigAuth)];
			}
			else if ([[self class] respondsToSelector:@selector(NSRailsSetConfig)])
			{
				config = [[self class] performSelector:@selector(NSRailsSetConfig)];
			}
			else
			{
				config = [NSRConfig defaultConfig];
			}
		}
		
		//initialize property categories
		sendableProperties = [[NSMutableArray alloc] init];
		retrievableProperties = [[NSMutableArray alloc] init];
		nestedModelProperties = [[NSMutableDictionary alloc] init];
		propertyEquivalents = [[NSMutableDictionary alloc] init];
		encodeProperties = [[NSMutableArray alloc] init];
		decodeProperties = [[NSMutableArray alloc] init];
		
		destroyOnNesting = NO;
		
		//here begins the code used for parsing the NSRailsify param string
		
		//character set that'll be used later on
		NSCharacterSet *wn = [NSCharacterSet whitespaceAndNewlineCharacterSet];
		
		//exclude array for any properties declared as -x (will later remove properties from * definition)
		NSMutableArray *exclude = [NSMutableArray array];
		
		//check to see if we should even consider *
		BOOL markedAll = ([props rangeOfString:@"*"].location != NSNotFound);
		
		//marked as NO for the first time in the loop
		//if a * appeared (markedAll is true), this will enable by the end of the loop and the whole thing will loop again, for the *
		BOOL onStarIteration = NO;
		
		do
		{
			NSMutableArray *elements;
			//if we're on the * run,
			if (onStarIteration)
			{
				//make sure we don't loop again
				onStarIteration = NO;
				markedAll = NO;
				
				NSMutableArray *relevantIvars = [NSMutableArray array];
				
				//start with the current class
				Class c = [self class];
				
				//loop going up the class hierarchy all the way up to NSRailsModel
				while (c != [NSRailsModel class])
				{
					//get the property list for that specific class
					NSString *properties = [c NSRailsProperties];
					
					//if there's a *, add all ivars from that class
					if ([properties rangeOfString:@"*"].location != NSNotFound)
						[relevantIvars addObjectsFromArray:[c ivarNames]];
					
					//if there's a NoCarryFromSuper, stop the loop right there since we don't want stuff from any more superclasses
					if ([properties rangeOfString:_NSRNoCarryFromSuper_STR].location != NSNotFound)
						break;
					
					//move up in the hierarchy for next iteration
					c = [c superclass];
				}
				
				
				elements = [NSMutableArray array];
				//go through all the ivars we found
				for (NSString *ivar in relevantIvars)
				{
					//if it hasn't been declared as -x or declared at all (from the first run), add it to the list we have to process
					if (![exclude containsObject:ivar] && ![propertyEquivalents objectForKey:ivar])
					{
						[elements addObject:ivar];
					}
				}
			}
			else
			{
				//if on the first run, split properties by commas ("username=user_name, password"=>["username=user_name","password"]
				elements = [NSMutableArray arrayWithArray:[props componentsSeparatedByString:@","]];
			}
			for (int i = 0; i < elements.count; i++)
			{
				NSString *str = [elements objectAtIndex:i];
				//remove any whitespace along with trailing NSRNoCarryFromSuper's to not screw anything up
				NSString *prop = [[str stringByTrimmingCharactersInSet:wn] stringByReplacingOccurrencesOfString:_NSRNoCarryFromSuper_STR withString:@""];
				
				if (prop.length > 0)
				{
					if ([prop rangeOfString:@"*"].location != NSNotFound)
					{
						//if there's a * in this piece, skip it (we already accounted for stars above)
						
						continue;
					}
					
					//prop can be something like "username=user_name:Class -etc"
					//find string sets between =, :, and -
					NSArray *opSplit = [prop componentsSeparatedByString:@"-"];
					NSArray *modSplit = [[opSplit objectAtIndex:0] componentsSeparatedByString:@":"];
					NSArray *eqSplit = [[modSplit objectAtIndex:0] componentsSeparatedByString:@"="];
					
					prop = [[eqSplit objectAtIndex:0] stringByTrimmingCharactersInSet:wn];
					
					NSString *options = [opSplit lastObject];
					if (opSplit.count > 1)
					{
						//if it was marked exclude, add to exclude list in case * was declared
						if ([options rangeOfString:@"x"].location != NSNotFound)
						{
							[exclude addObject:prop];
							continue;
						}
						
						//if any of these flags exist, add to appropriate category
						if ([options rangeOfString:@"s"].location != NSNotFound)
							[sendableProperties addObject:prop];
						if ([options rangeOfString:@"r"].location != NSNotFound)
							[retrievableProperties addObject:prop];
						if ([options rangeOfString:@"e"].location != NSNotFound)
							[encodeProperties addObject:prop];
						if ([options rangeOfString:@"d"].location != NSNotFound)
							[decodeProperties addObject:prop];
					}
					
					//if no options are defined or some are but neither -s nor -r are defined, by default add sendable+retrievable
					if (opSplit.count == 1 ||
						([options rangeOfString:@"s"].location == NSNotFound && [options rangeOfString:@"r"].location == NSNotFound))
					{
						[sendableProperties addObject:prop];
						[retrievableProperties addObject:prop];
					}
					
					//see if there was a : declared
					if (modSplit.count > 1)
					{
						NSString *otherModel = [[modSplit lastObject] stringByTrimmingCharactersInSet:wn];
						if (otherModel.length > 0)
						{
							//class entered is not a real class
							if (!NSClassFromString(otherModel))
							{
	#ifdef NSRLogErrors
								NSLog(@"failed to find class %@ (declared for property %@ of class %@) - please fix this. relation not set. ",otherModel,prop,[self camelizedModelName]);
	#endif
							}
							//class entered is not a subclass of NSRailsModel
							else if (![NSClassFromString(otherModel) isSubclassOfClass:[NSRailsModel class]])
							{
	#ifdef NSRLogErrors
								NSLog(@"class %@ was declared for property %@ of class %@, but %@ is not a subclass of NSRailsModel - please fix this. relation not set.",otherModel,prop,[self camelizedModelName],otherModel);
	#endif
							}
							else
								[nestedModelProperties setObject:otherModel forKey:prop];
						}
					}
					else
					{
						//if no : was declared for this property, check to see if we should link it anyway
						NSString *ivarType = [self getIvarType:prop];
						
						if ([ivarType isEqualToString:@"NSArray"] ||
							[ivarType isEqualToString:@"NSMutableArray"])
						{
	#if NSRLog > 2
							NSLog(@"warning: property '%@' in class %@ was found to be an array, but no nesting model was set. note that without knowing with which models NSR should populate the array, NSDictionaries with the retrieved rails attributes will be set. if NSDictionaries are desired, to suppress this warning, simply add a colon with nothing following to the property in NSRailsify... %@:",prop,[self camelizedModelName],str);
	#endif
						}
						else if (!([ivarType isEqualToString:@"NSString"] ||
								   [ivarType isEqualToString:@"NSMutableString"] ||
								   [ivarType isEqualToString:@"NSDictionary"] ||
								   [ivarType isEqualToString:@"NSMutableDictionary"] ||
								   [ivarType isEqualToString:@"NSNumber"]))
						{
							//must be custom obj, see if its a railsmodel, if it is, link it automatically
							Class c = NSClassFromString(ivarType);
							if (c && [c isSubclassOfClass:[NSRailsModel class]])
							{
	#if NSRLog > 2
								//uncomment the log to test if something isn't working
								//		NSLog(@"automatically linking ivar %@ in class %@ with nested railsmodel %@",prop,[self camelizedModelName],ivarType);
	#endif
								[nestedModelProperties setObject:ivarType forKey:prop];
							}
						}
					}
					
					//see if there are any = declared
					NSString *equivalent = prop;
					if (eqSplit.count > 1)
					{
						equivalent = [[eqSplit lastObject] stringByTrimmingCharactersInSet:wn];
						//if they tried to tie it to 'id', give error (but ignore if it's the first equivalence (modelID via base_rails)
						if ([equivalent isEqualToString:@"id"] && i != 0)
						{
	#ifdef NSRLogErrors
							NSLog(@"found attempt to set the rails equivalent of ivar '%@' in class %@ to 'id'. this property is reserved and should be accessed through 'modelID' from a NSRailsModel subclass - please fix this. equivalence not set.", prop, [self camelizedModelName]);
	#endif
							equivalent = prop;
						}
						//see if there's already 1 or more rails names set for this equivalency
						else if ([propertyEquivalents allKeysForObject:equivalent].count > 0)
						{
	#ifdef NSRLogErrors
							NSLog(@"found multiple instance variables tied to one rails equivalent in class %@ - please fix this. when receiving rails property %@, NSR will assign it to the first equivalence listed.",[self camelizedModelName], equivalent);
	#endif
						}
					}
	#ifdef NSRAutomaticallyUnderscoreAndCamelize
					else
					{
						//if no = was declared for this property, default by using underscore+lowercase'd version of it
						equivalent = [[prop underscore] lowercaseString];
					}
	#endif
					[propertyEquivalents setObject:equivalent forKey:prop];
				}
			}

			//if markedAll (a * was encountered somewhere), loop again one more time to add all properties not already listed (*)
			if (markedAll)
				onStarIteration = YES;
		} 
		while (onStarIteration);
		
	//	NSLog(@"-------- %@ ----------",[[self class] getModelName]);
	//	NSLog(@"list: %@",props);
	//	NSLog(@"sendable: %@",sendableProperties);
	//	NSLog(@"retrievable: %@",retrievableProperties);
	//	NSLog(@"NMP: %@",nestedModelProperties);
	//	NSLog(@"eqiuvalents: %@",propertyEquivalents);
	//	NSLog(@"\n");
	}

	return self;
}

- (id) init
{
	//read in properties defined through NSRailsProperties
	NSString *props = [[self class] railsProperties];
	
	if ((self = [self initWithRailsifyString:props]))
	{
	}
	return self;
}

#pragma mark -
#pragma mark Ivar tricks

//borrowed from code in http://x-cake.ning.com/profiles/blogs/browsing-the-objc-runtime-on , my comments
+ (NSMutableArray *) ivarNames
{
	unsigned int ivarCount;
	//copy all ivars for self (will be a Class)
	Ivar *ivars = class_copyIvarList(self, &ivarCount);
	if (ivars)
	{
		NSMutableArray *results = [NSMutableArray arrayWithCapacity:ivarCount];
		
		while (ivarCount--)
		{
			//get each ivar name and add it to the results
			const char *ivarName = ivar_getName(ivars[ivarCount]);
			[results addObject:[NSString stringWithCString:ivarName encoding:NSASCIIStringEncoding]];
		}
		
		free(ivars);	
		return results;
	}
	return nil;
}

- (NSString *) getIvarType:(NSString *)ivar
{
	//get class's ivar
	Ivar var = class_getInstanceVariable([self class], [ivar UTF8String]);
	if (!var)
		return nil;
	
	NSString *ret = [NSString stringWithCString:ivar_getTypeEncoding(var) encoding:NSUTF8StringEncoding];
	
	//ret will be like @"NSString", so strip "s and @s
	return [[ret stringByReplacingOccurrencesOfString:@"\"" withString:@""] stringByReplacingOccurrencesOfString:@"@" withString:@""];
}

- (SEL) getIvar:(NSString *)ivar attributePrefix:(NSString *)str
{
	objc_property_t property = class_getProperty([self class], [ivar UTF8String]);
	if (!property)
		return nil;
	
	NSString *atts = [NSString stringWithCString:property_getAttributes(property) encoding:NSUTF8StringEncoding];
	//this will return some garbage like "Ti,GgetFoo,SsetFoo:,Vproperty"
	//getter is prefixed by a G and setter is prefixed by an S
	//split it by attribute and return anything matching the prefix specified (would be S or G)
	for (NSString *att in [atts componentsSeparatedByString:@","])
	{
		if (att.length > 0 && [[att substringToIndex:1] isEqualToString:str])
		{
			NSString *setter = [att substringFromIndex:1];
			return NSSelectorFromString(setter);
		}
	}
	
	return nil;
}

- (SEL) getIvarGetter:(NSString *)ivar
{
	SEL s = [self getIvar:ivar attributePrefix:@"G"];
	//if no custom getter specified, return the standard "etc"
	if (!s)
	{
		s = NSSelectorFromString(ivar);
	}
	return s;
}

- (SEL) getIvarSetter:(NSString *)ivar
{
	SEL s = [self getIvar:ivar attributePrefix:@"S"];
	//if no custom setter specified, return the standard "setEtc:"
	if (!s)
	{
		s = NSSelectorFromString([NSString stringWithFormat:@"set%@:",[ivar toClassName]]);
	}
	return s;
}

#pragma mark -
#pragma mark Internal NSR stuff

- (NSString *) description
{
	return [attributes description];
}

- (NSString *) JSONRepresentation
{
	// enveloped meaning with the model name out front, {"user"=>{"name"=>"x", "password"=>"y"}}
	
	NSDictionary *enveloped = [NSDictionary dictionaryWithObject:[self dictionaryOfRelevantProperties]
														  forKey:[[self class] getModelName]];
	
	return [enveloped JSONRepresentation];
}

- (id) makeRelevantModelFromClass:(NSString *)classN basedOn:(NSDictionary *)dict
{
	//make a new class to be entered for this property/array (we can assume it subclasses RM)
	NSRailsModel *model = [[NSClassFromString(classN) alloc] init];
	if (!model)
	{
#ifdef NSRLogErrors
		NSLog(@"could not find %@ class; leaving property null.",classN);
#endif
		return nil;
	}
#ifndef NSRCompileWithARC
	[model autorelease];
#endif
	
	//populate the new class with attributes specified
	[model setAttributesAsPerDictionary:dict];
	return model;
}

- (id) objectForProperty:(NSString *)prop representation:(id)rep
{
	//if object is marked as decodable, use the decode method
	if ([decodeProperties indexOfObject:prop] != NSNotFound)
	{
		NSString *sel = [NSString stringWithFormat:@"decode%@:",[prop toClassName]];
		SEL selector = NSSelectorFromString(sel);
		if ([self respondsToSelector:selector])
		{
			id obj = [self performSelector:selector withObject:rep];
			return obj;
		}
	}
	
	//otherwise, return whatever it is
	return rep;
}

- (id) representationOfObjectForProperty:(NSString *)prop
{
	//get the value of the property
	SEL sel = [self getIvarGetter:prop];
	if ([self respondsToSelector:sel])
	{
		id val = [self performSelector:sel];
		
		//see if this property actually links to a custom NSRailsModel subclass
		if ([nestedModelProperties objectForKey:prop])
		{
			//if the ivar is an array, we need to make every element into JSON and then put them back in the array
			if ([val isKindOfClass:[NSArray class]])
			{
#ifdef NSRSendHasManyRelationAsHash
				NSMutableDictionary *new = [NSMutableDictionary dictionary];
#else
				NSMutableArray *new = [NSMutableArray arrayWithCapacity:[val count]];
#endif
				//go through every nested object in the array
				for (int i = 0; i < [val count]; i++)
				{
					//use the NSRailsModel instance method -dictionaryOfRelevantProperties to get that object back in dictionary form
					id obj = [[val objectAtIndex:i] dictionaryOfRelevantProperties];
					if (!obj)
					{
						obj = [NSNull null];
					}
#ifdef NSRSendHasManyRelationAsHash
					[new setObject:obj forKey:[NSString stringWithFormat:@"%d",i]];
#else
					[new addObject:obj];
#endif
				}
				return new;
			}
			//otherwise, make that nested object a dictionary through NSRailsModel
			return [val dictionaryOfRelevantProperties];
		}
		
		//if NOT linked property, if its declared as encodable, return encoded version
		if ([encodeProperties indexOfObject:prop] != NSNotFound)
		{
			NSString *sel = [NSString stringWithFormat:@"encode%@:",[prop toClassName]];
			SEL selector = NSSelectorFromString(sel);
			if ([self respondsToSelector:selector])
			{
				id obj = [self performSelector:selector withObject:val];
				return obj;
			}
		}
		
		return val;
	}
	return nil;
}

- (void) setAttributesAsPerDictionary:(NSDictionary *)dict
{
	attributes = dict;
	for (NSString *key in dict)
	{
		NSString *property;
		NSArray *equiv = [propertyEquivalents allKeysForObject:key];
		if (equiv.count > 0) //means its a relevant property, so lets try to set it
		{
			property = [equiv objectAtIndex:0];
			
#ifdef NSRLogErrors
			if (equiv.count > 1)
				NSLog(@"found multiple instance variables tied to one rails equivalent (%@ are all set to equal rails property '%@'). setting data for it into the first ivar listed, but please fix.",equiv,key);
#endif
			
			SEL sel = [self getIvarSetter:property];
			if ([self respondsToSelector:sel] && [retrievableProperties indexOfObject:property] != NSNotFound)
				//means its marked as retrievable and is settable through setEtc:.
			{
				id val = [dict objectForKey:key];
				val = [self objectForProperty:property representation:([val isKindOfClass:[NSNull class]] ? nil : val)];
				if (val)
				{
					NSString *nestedClass = [[nestedModelProperties objectForKey:property] toClassName];
					//instantiate it as the class specified in NSRailsProperties
					if (nestedClass)
					{
						//if the JSON conversion returned an array for the value, instantiate each element
						if ([val isKindOfClass:[NSArray class]])
						{
							NSMutableArray *array = [NSMutableArray array];
							for (NSDictionary *dict in val)
							{
								id model = [self makeRelevantModelFromClass:nestedClass basedOn:dict];
								[array addObject:model];
							}
							val = array;
						}
						else
						{
							val = [self makeRelevantModelFromClass:nestedClass basedOn:[dict objectForKey:key]];
						}
					}
					//TODO: maybe remove/enhance?
					// check to see if you're gonna enter a dictionary and ivar isn't a dict (ie custom class)
					NSString *ivarType = [self getIvarType:property];
					if ([val isKindOfClass:[NSDictionary class]]
						&& ![ivarType isEqualToString:@"NSDictionary"] && ![ivarType isEqualToString:@"NSMutableDictionary"])
					{
#ifdef NSRLogErrors
						NSLog(@"NOTE: entering NSDictionary into %@'s ivar '%@' (type = %@) -- types do not match up!!",property,ivarType,[self camelizedModelName]);
#endif
					}
					[self performSelector:sel withObject:val];
				}
				else
				{
					[self performSelector:sel withObject:nil];
				}
			}
		}
	}
}

- (NSDictionary *) dictionaryOfRelevantProperties
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	//loop through all properties marked as sendable
	for (NSString *key in sendableProperties)
	{
		NSString *property = [propertyEquivalents objectForKey:key];
		
		id val = [self representationOfObjectForProperty:key];
		BOOL null = !val;
		if (!val && ![property isEqualToString:@"id"]) //if ID is null, simply bypass it, don't stick in "null" - it could be for create
		{
			NSString *string = [self getIvarType:key];
			if ([string isEqualToString:@"NSArray"] || [string isEqualToString:@"NSMutableArray"])
			{
				//there's an array, and because the value is nil, make it an empty array (rails will get angry if you send nil)
				val = [NSArray array];
			}
			else
			{
				val = [NSNull null];
			}
		}
		if (val)
		{
			if ([nestedModelProperties objectForKey:key] && !null) //if its null/empty(for arrays), dont append _attributes
				property = [property stringByAppendingString:NSRAppendNestedModelKeyOnSend];
			[dict setObject:val forKey:property];
		}
	}
	//if object is marked as destroy for nesting, add "_destroy"=>true to hash 
	if (destroyOnNesting)
	{
		[dict setObject:[NSNumber numberWithBool:destroyOnNesting] forKey:@"_destroy"];
	}

	return dict;
}

- (BOOL) setAttributesAsPerJSON:(NSString *)json
{
	if (!json)
	{
		NSLog(@"can't set attributes to nil json");
		return NO;
	}
	
	NSDictionary *dict = [json JSONValue];
	
	if (!dict || dict.count == 0)
	{
		NSLog(@"something went wrong in json conversion!");
		return NO;
	}
	
	[self setAttributesAsPerDictionary:dict];
	
	return YES;
}

#pragma clang diagnostic pop


#pragma mark -
#pragma mark HTTP Request stuff

static NSOperationQueue *queue = nil;

+ (void) crashWithError:(NSError *)error
{
	//purpose of this method is to factor printing out an error message (if NSRLog allows) and crash if necessary
#if NSRLog > 0
	NSRLogError(error);
	NSLog(@" ");
#endif
	
#ifdef NSRCrashOnError
	[NSException raise:[NSString stringWithFormat:@"%@ error code %d",[error domain],[error code]] format:[error localizedDescription]];
#endif
}

+ (NSOperationQueue *) sharedQueue
{
	//queue used for async requests
	if (!queue)
	{
		queue = [[NSOperationQueue alloc] init];
		[queue setMaxConcurrentOperationCount:5];
	}
	return queue;
}

+ (NSString *) resultWithRequest:(NSURLResponse *)response data:(NSData *)data error:(NSError **)error
{
	int statusCode = -1;
	BOOL err;
	NSString *result;
	
	//otherwise, get the statuscode from the response (it'll be an NSHTTPURLResponse but to be safe check if it responds)
	if ([response respondsToSelector:@selector(statusCode)])
	{
		statusCode = [((NSHTTPURLResponse *)response) statusCode];
	}
	err = (statusCode == -1 || statusCode >= 400);
	
	result = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
	
#ifndef NSRCompileWithARC
	[request release];
	[result autorelease];
#endif
	
#if NSRLog > 1
	NSLog(@"IN<=== Code %d; %@\n\n",statusCode,(err ? @"[see ERROR]" : result));
	NSLog(@" ");
#endif
	
	if (err)
	{
#ifdef NSRSuccinctErrorMessages
		//if error message is in HTML,
		if ([result rangeOfString:@"</html>"].location != NSNotFound)
		{
			NSArray *pres = [result componentsSeparatedByString:@"<pre>"];
			if (pres.count > 1)
			{
				//get the value between <pre> and </pre>
				result = [[[pres objectAtIndex:1] componentsSeparatedByString:@"</pre"] objectAtIndex:0];
				//some weird thing rails does, will send html tags &quot; for quotes
				result = [result stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
			}
		}
#endif
		
		//make a new error
		NSMutableDictionary *inf = [NSMutableDictionary dictionaryWithObject:result
																	  forKey:NSLocalizedDescriptionKey];
		//means there was a validation error - the specific errors were sent in JSON
		if (statusCode == 422)
		{
			[inf setObject:[result JSONValue] forKey:NSRValidationErrorsKey];
		}
		
		NSError *statusError = [NSError errorWithDomain:@"Rails"
												   code:statusCode
											   userInfo:inf];
		
		if (error)
		{
			*error = statusError;
		}
		
		[self crashWithError:statusError];
		
		return nil;
	}
	
	return result;
}

+ (NSString *) makeRequestType:(NSString *)type requestBody:(NSString *)requestStr route:(NSString *)route sync:(NSError **)error orAsync:(void(^)(NSString *result, NSError *error))completionBlock
{
	NSString *appURL = config.appURL;
	//if there's no config specific to this class, use default
	if (!appURL)
		appURL = [[NSRConfig defaultConfig] appURL];
	
	//make sure the app URL is set
	if (!appURL)
	{
		NSError *err = [NSError errorWithDomain:@"NSRails" code:0 userInfo:[NSDictionary dictionaryWithObject:@"No server root URL specified. Set your rails app's root with +[[NSRConfig defaultConfig] setAppURL:] somewhere in your app setup." forKey:NSLocalizedDescriptionKey]];
		if (error)
			*error = err;
		if (completionBlock)
			completionBlock(nil, err);
		
		[self crashWithError:err];
		
		return nil;
	}
	
	//generate url based on base URL + route given
	NSString *url = [NSString stringWithFormat:@"%@/%@",appURL,route];
	
#ifdef NSRAutomaticallyMakeURLsLowercase
	url = [url lowercaseString];
#endif
	
	//log relevant stuff
#if NSRLog > 0
	NSLog(@" ");
	NSLog(@"%@ to %@",type,url);
#if NSRLog > 1
	NSLog(@"OUT===> %@",requestStr);
#endif
#endif
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	
	[request setHTTPMethod:type];
	[request setHTTPShouldHandleCookies:NO];
	//set for json content
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	
	//if username & password set, assume basic HTTP authentication
	if (config.appUsername && config.appPassword)
	{
		//add auth header encoded in base64
		NSString *authStr = [NSString stringWithFormat:@"%@:%@", config.appUsername, config.appPassword];
		NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
		NSString *authHeader = [NSString stringWithFormat:@"Basic %@", [authData base64Encoding]];
		
		[request setValue:authHeader forHTTPHeaderField:@"Authorization"]; 
	}
	
	//if there's an actual request, add the body
	if (requestStr)
	{
		NSData *requestData = [NSData dataWithBytes:[requestStr UTF8String] length:[requestStr length]];
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[request setHTTPBody: requestData];
		[request setValue:[NSString stringWithFormat:@"%d", [requestData length]] forHTTPHeaderField:@"Content-Length"];
 	}
	
	//send request!
	if (completionBlock)
	{
		[NSURLConnection sendAsynchronousRequest:request queue:[[self class] sharedQueue] completionHandler:
		 ^(NSURLResponse *response, NSData *data, NSError *error) 
		 {
			 if (error)
			 {
				 [self crashWithError:error];

				 completionBlock(nil,error);
			 }
			 NSError *e = nil;
			 NSString *result = [self resultWithRequest:response data:data error:&e];
		
			 if (e)
				 [self crashWithError:e];

			 completionBlock(result,e);
		 }];
		
		return nil;
	}
	else
	{
		NSError *connectionError;
		NSURLResponse *response = nil;
		NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&connectionError];
		
		//if there's an error here there must have been an issue connecting to the server.
		if (connectionError)
		{
			//if there was a dereferenced error passed in, set it to Apple's
			if (error)
				*error = connectionError;
			
			[self crashWithError:connectionError];

			return nil;
		}
		
		return [self resultWithRequest:response data:data error:error];
	}
}

- (NSString *) routeForMethod:(NSString *)method
{
	//make request on instance, so set URL to be in format "users/1"
	NSString *route = [NSString stringWithFormat:@"%@/%@",[[self class] getPluralModelName], self.modelID];
	if (method.length > 0)
	{
		//if there's a method included too,
		//make sure sure there's no / starting the method string
		if ([[method substringToIndex:1] isEqualToString:@"/"])
			method = [method substringFromIndex:1];
		
		//tack the method onto the end
		route = [route stringByAppendingFormat:@"/%@",method];
	}
	return route;
}

+ (NSString *) routeForMethod:(NSString *)method
{
	NSString *route;
	NSString *controller = [self getPluralModelName];
	if (controller)
	{
		//this means this method was called on a RailsMethod _subclass_, so appropriately point the method to its controller
		//eg, ([User makeGET:@"hello"] => myapp.com/users/hello)
		route = controller;
		if (method)
			route = [route stringByAppendingFormat:@"/%@", method];
	}
	else
	{
		//this means this method was called on NSRailsModel (to access a "root method")
		//eg, ([NSRailsModel makeGET:@"hello"] => myapp.com/hello)
		route = method;
	}
	
	return route;
}

#pragma mark Performing actions on instances

- (NSString *) makeGETRequestWithMethod:(NSString *)method error:(NSError **)error
{
	return [[self class] makeRequestType:@"GET" requestBody:nil route:[self routeForMethod:method] sync:error orAsync:nil];
}

- (void) makeGETRequestWithMethod:(NSString *)method async:(void(^)(NSString *result, NSError *error))completionBlock
{
	[[self class] makeRequestType:@"GET" requestBody:nil route:[self routeForMethod:method] sync:nil orAsync:completionBlock];
}

- (NSString *) makeRequest:(NSString *)httpVerb requestBody:(NSString *)requestStr method:(NSString *)method error:(NSError **)error
{
	return [[self class] makeRequestType:httpVerb requestBody:requestStr route:[self routeForMethod:method] sync:error orAsync:nil];
}

- (void) makeRequest:(NSString *)httpVerb requestBody:(NSString *)requestStr method:(NSString *)method async:(void(^)(NSString *result, NSError *error))block
{
	[[self class] makeRequestType:httpVerb requestBody:requestStr route:[self routeForMethod:method] sync:nil orAsync:block];
}

#pragma mark Performing actions on classes

+ (void) makeGETRequestWithMethod:(NSString *)method async:(void (^)(NSString *result, NSError *))completionBlock
{ 
	[self makeRequest:@"GET" requestBody:nil method:method async:completionBlock];
}
+ (NSString *) makeGETRequestWithMethod:(NSString *)method error:(NSError **)error
{ 
	return [self makeRequest:@"GET" requestBody:nil method:method error:error];
} 

+ (void) makeRequest:(NSString *)httpVerb requestBody:(NSString *)requestStr method:(NSString *)method async:(void (^)(NSString *result, NSError *))block
{ 
	[[self class] makeRequestType:httpVerb requestBody:requestStr route:[self routeForMethod:method] sync:nil orAsync:block];
}
+ (NSString *) makeRequest:(NSString *)httpVerb requestBody:(NSString *)requestStr method:(NSString *)method error:(NSError **)error
{ 
	return [[self class] makeRequestType:httpVerb requestBody:requestStr route:[self routeForMethod:method] sync:error orAsync:nil];
}

#pragma mark -
#pragma mark External stuff (CRUD)

- (BOOL) checkForNilID:(NSError **)error
{
	//used as a helper for update/create
	//if no ID for this model, return error.
	if (!self.modelID)
	{
		NSError *e = [NSError errorWithDomain:@"NSRails" code:0 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Attempted to update or delete an object with no ID. (Instance of %@)",NSStringFromClass([self class])] forKey:NSLocalizedDescriptionKey]];
		if (error)
			*error = e;
		
		[[self class] crashWithError:e];
		return NO;
	}

	return YES;
}

#pragma mark Create

- (BOOL) createRemote {	return [self createRemote:nil];	}
- (BOOL) createRemote:(NSError **)error
{
	NSString *json = [[self class] makeRequest:@"POST" requestBody:[self JSONRepresentation] method:nil error:error];
	
	//check to see if json exists, and if it does, set all of my attributes to it (like to add the new ID), and return if it worked
	return (json && [self setAttributesAsPerJSON:json]);
}
- (void) createRemoteAsync:(void (^)(NSError *))completionBlock
{
	[[self class] makeRequest:@"POST" requestBody:[self JSONRepresentation] method:nil async:^(NSString *result, NSError *error) 
	{
		if (result)
			[self setAttributesAsPerJSON:result];
		completionBlock(error);
	}];
}

#pragma mark Update

- (BOOL) updateRemote {	return [self updateRemote:nil];	}
- (BOOL) updateRemote:(NSError **)error
{
	if (![self checkForNilID:error])
		return NO;
	
	//makeRequest will actually return a result string, return if it's not nil (!! = not nil, nifty way to turn object to BOOL)
	return !![self makeRequest:@"PUT" requestBody:[self JSONRepresentation] method:nil error:error];
}
- (void) updateRemoteAsync:(void (^)(NSError *))completionBlock
{
	NSError *error;
	if (![self checkForNilID:&error])
	{
		completionBlock(error);
	}
	else
	{
		[self makeRequest:@"PUT" requestBody:[self JSONRepresentation] method:nil async:^(NSString *result, NSError *error) 
		{
			completionBlock(error);
		}];
	}
}

#pragma mark Destroy

- (BOOL) destroyRemote { return [self destroyRemote:nil]; }
- (BOOL) destroyRemote:(NSError **)error
{
	if (![self checkForNilID:error])
		return NO;
	
	return (!![self makeRequest:@"DELETE" requestBody:nil method:nil error:error]);
}
- (void) destroyRemoteAsync:(void (^)(NSError *))completionBlock
{
	NSError *error;
	if (![self checkForNilID:&error])
	{
		completionBlock(error);
	}
	else
	{
		[self makeRequest:@"DELETE" requestBody:nil method:nil async:^(NSString *result, NSError *error) {
			completionBlock(error);
		}];
	}
}

#pragma mark Get latest

- (BOOL) getRemoteLatest {	return [self getRemoteLatest:nil]; }
- (BOOL) getRemoteLatest:(NSError **)error
{
	NSString *json = [self makeGETRequestWithMethod:nil error:error];
	if (!json)
	{
		return NO;
	}
	return ([self setAttributesAsPerJSON:json]); //will return true/false if conversion worked
}
- (void) getRemoteLatestAsync:(void (^)(NSError *error))completionBlock
{
	[self makeGETRequestWithMethod:nil async:^(NSString *result, NSError *error) 
	{
		if (result)
			[self setAttributesAsPerJSON:result];
		completionBlock(error);
	}];
}

#pragma mark Get specific object (class-level)

+ (id) getRemoteObjectWithID:(int)mID	{ return [self getRemoteObjectWithID:mID error:nil]; }
+ (id) getRemoteObjectWithID:(int)mID error:(NSError **)error
{
	//instantiate the class
	NSRailsModel *obj = [[[self class] alloc] init];
	
	//set the ID to whatever was passed in - this will indicate where NSR should look on the server
	obj.modelID = [NSDecimalNumber numberWithInt:mID];
	
	//if the getRemote didn't work, make it nil
	if (![obj getRemoteLatest:error])
		obj = nil;
	
#ifndef NSRCompileWithARC
	[obj autorelease];
#endif

	return obj;
}
+ (void) getRemoteObjectWithID:(int)mID async:(void (^)(id object, NSError *error))completionBlock
{
	//see comments for previous method
	NSRailsModel *obj = [[[self class] alloc] init];
	obj.modelID = [NSDecimalNumber numberWithInt:mID];
	
#ifndef NSRCompileWithARC
	[obj autorelease];
#endif
	
	[obj getRemoteLatestAsync:^(NSError *error) {
		if (error)
			completionBlock(nil, error);
		else
			completionBlock(obj, error);
	}];
}

#pragma mark Get all objects (class-level)

+ (NSArray *) arrayOfModelsFromJSON:(NSString *)json error:(NSError **)error
{
	//transform result into array (via json)
	id arr = [json JSONValue];
	
	//helper method for both sync+async for getAllRemote
	if (![arr isKindOfClass:[NSArray class]])
	{
		NSError *e = [NSError errorWithDomain:@"NSRails" 
										 code:0 
									 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"getAll method (index) for %@ controller did not return an array - check your rails app.",[self getModelName]]
																		  forKey:NSLocalizedDescriptionKey]];
		
		if (error)
			*error = e;
		
		[[self class] crashWithError:e];
		
		return nil;
	}
	
	NSMutableArray *objects = [NSMutableArray array];
	
	//iterate through every object returned by Rails (as dicts)
	for (NSDictionary *dict in arr)
	{
		//make a new instance of this class for each dict,
		NSRailsModel *obj = [[[self class] alloc] init];	
		
		//and set its properties as per the dictionary defined in the json
		[obj setAttributesAsPerDictionary:dict];
		
		[objects addObject:obj];
		
#ifndef NSRCompileWithARC
		[obj release];
#endif
	}
	
	return objects;
}

+ (NSArray *) getAllRemote {	return [self getAllRemote:nil]; }
+ (NSArray *) getAllRemote:(NSError **)error
{
	//make a class GET call (so just the controller - myapp.com/users)
	NSString *json = [self makeGETRequestWithMethod:nil error:error];
	if (!json)
	{
		return nil;
	}
	return [self arrayOfModelsFromJSON:json error:error];
}

+ (void) getAllRemoteAsync:(void (^)(NSArray *, NSError *))completionBlock
{
	[self makeGETRequestWithMethod:nil async:^(NSString *result, NSError *error) 
	{
		if (error || !result)
		{
			completionBlock(nil, error);
		}
		else
		{
			//make an array from the result returned async, and we can reuse the same error dereference (since we know it's nil)
			NSArray *array = [self arrayOfModelsFromJSON:result error:&error];
			completionBlock(array,error);
		}
	}];
}

#pragma mark -
#pragma mark Dealloc for non-ARC
#ifndef NSRCompileWithARC

- (void) dealloc
{
	[modelID release];
	[attributes release];
	
	[sendableProperties release];
	[retrievableProperties release];
	[encodeProperties release];
	[decodeProperties release];
	[nestedModelProperties release];
	[propertyEquivalents release];
	
	[super dealloc];
}

#endif

@end
