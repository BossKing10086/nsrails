//
//  NSRailsModel.m
//  NSRails
//
//  Created by Dan Hassin on 1/10/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRails.h"

#import "NSRPropertyCollection.h"

#import "NSString+InflectionSupport.h"
#import "NSData+Additions.h"
#import "NSObject+Properties.h"

  ///////////////////////////////////////////////////////////////

     ///   //   //////   //////      /////   //  //      //////
    ////  //  //        //   //    //   //  //  //     //
   // // //    ////    //////     //   //  //  //       ////
  //  ////       //   //  //     ///////  //  //          //
 //   ///   /////    //    ///  //   //  //  /////// /////

/////////////////////////////////////////////////////////////

/* 
    If this file is too intimidating, 
 remember that you can navigate it
 quickly in Xcode using #pragma marks.
								    	*/


@interface NSRailsModel (internal)

+ (NSRConfig *) getRelevantConfig;

+ (NSString *) railsProperties;
+ (NSString *) getModelName;
+ (NSString *) getPluralModelName;

+ (NSRPropertyCollection *) propertyCollection;

@end

@interface NSRConfig (access)

+ (NSRConfig *) overrideConfig;
+ (void) crashWithError:(NSError *)error;
- (NSString *) resultForRequestType:(NSString *)type requestBody:(NSString *)requestStr route:(NSString *)route sync:(NSError **)error orAsync:(NSRHTTPCompletionBlock)completionBlock;

@end


@implementation NSRailsModel
@synthesize remoteID, remoteDestroyOnNesting, remoteAttributes;

static NSMutableDictionary *propertyCollections = nil;

#pragma mark -
#pragma mark Meta-NSR stuff

//this will suppress the compiler warnings that come with ARC when doing performSelector
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"


+ (NSString *) NSRailsSync
{
	return NSRAILS_BASE_PROPS;
}

+ (NSRPropertyCollection *) propertyCollection
{
	if (!propertyCollections)
		propertyCollections = [[NSMutableDictionary alloc] init];
	
	NSString *class = NSStringFromClass(self);
	NSRPropertyCollection *collection = [propertyCollections objectForKey:class];
	if (!collection)
	{
		collection = [[NSRPropertyCollection alloc] initWithClass:self];
		[propertyCollections setObject:collection forKey:class];
		
#ifndef NSRCompileWithARC
		[collection release];
#endif
	}
	
	return collection;
}

- (NSRPropertyCollection *) propertyCollection
{
	if (customProperties)
		return customProperties;
	
	return [[self class] propertyCollection];
}

+ (NSString *) railsPropertiesWithCustomString:(NSString *)custom
{
	//start it off with the NSRails base ("remoteID=id")
	NSMutableString *finalProperties = [NSMutableString stringWithString:NSRAILS_BASE_PROPS];
	
	BOOL stopInheriting = NO;
	
	//go up the class hierarchy, starting at self, adding the property list from each class
	for (Class c = self; (c != [NSRailsModel class] && !stopInheriting); c = [c superclass])
	{
		NSString *syncString = [NSString string];
		if (c == self && custom)
		{
			syncString = custom;
		}
		else if ([c respondsToSelector:@selector(NSRailsSync)])
		{
			syncString = [c NSRailsSync];
			
			//if that class defines NSRNoCarryFromSuper, mark that we should stop rising classes
			if ([syncString rangeOfString:_NSRNoCarryFromSuper_STR].location != NSNotFound)
			{
				stopInheriting = YES;
				
				//we strip the flag so that later on, we'll know exactly WHICH class defined the flag.
				//	otherwise, it'd be tacked on to every subclass.
				//this is why if this class is evaluating itself here, it shouldn't strip it, to signify that IT defined it
				if (c != self)
				{
					syncString = [syncString stringByReplacingOccurrencesOfString:_NSRNoCarryFromSuper_STR withString:@""];
				}
			}
		}
		[finalProperties appendFormat:@", %@", syncString];
	}
	
	return finalProperties;
}

+ (NSString *) railsProperties
{
	return [self railsPropertiesWithCustomString:nil];
}

+ (NSString *) getModelName
{
	SEL sel = @selector(NSRailsUseModelName);
	
	//check to see if mname defined manually, then check to see if not nil (nil signifies that it's a UseDefault definition)
	if ([self respondsToSelector:sel] && [self performSelector:sel])
	{
		return [self performSelector:sel];
	}
	
	//otherwise, return name of the class
	NSString *class = NSStringFromClass(self);
	if ([class isEqualToString:@"NSRailsModel"])
		class = nil;
	
	if ([self getRelevantConfig].automaticallyUnderscoreAndCamelize)
		return [[class underscore] lowercaseString];
	else
		return class;
}

+ (NSString *) getPluralModelName
{
	//if defined through NSRailsUseModelName as second parameter, use that instead
	SEL sel = @selector(NSRailsUsePluralName);
	if ([self respondsToSelector:sel] && [self performSelector:sel])
	{
		return [self performSelector:sel];
	}
	//otherwise, pluralize ModelName
	return [[self getModelName] pluralize];
}

+ (NSRConfig *) getRelevantConfig
{
	//get the config for this class
	
	//if there's an overriding config in this context (an -[NSRConfig use] was called (explicitly or implicity via a block))
	//use the overrider
	if ([NSRConfig overrideConfig])
	{
		return [NSRConfig overrideConfig];
	}
	
	//if this class defines NSRailsUseConfig, use it over the default
	//could also be return the defaultConfig
	else if ([[self class] respondsToSelector:@selector(NSRailsUseConfig)])
	{
		return [[self class] performSelector:@selector(NSRailsUseConfig)];
	} 
	
	//otherwise, use the default config
	else
	{
		return [NSRConfig defaultConfig];
	}
}


- (id) initWithCustomSyncProperties:(NSString *)str
{
	if ((self = [super init]))
	{
		//inheritance rules etc still apply
		str = [[self class] railsPropertiesWithCustomString:str];
		customProperties = [[NSRPropertyCollection alloc] initWithClass:[self class] properties:str];
	}
	return self;
}




#pragma mark -
#pragma mark Internal NSR stuff

//overload NSObject's description method to be a bit more, hm... descriptive
//will return the latest Rails dictionary (hash) retrieved
- (NSString *) description
{
	if (remoteAttributes)
		return [remoteAttributes description];
	return [super description];
}

- (NSString *) remoteJSONRepresentation:(NSError **)e
{
	// enveloped meaning with the model name out front, {"user"=>{"name"=>"x", "password"=>"y"}}
	
	NSDictionary *enveloped = [NSDictionary dictionaryWithObject:[self dictionaryOfRemoteProperties]
														  forKey:[[self class] getModelName]];
	
	NSError *error;
	NSString *json = [enveloped JSONRepresentation:&error];
	if (!json)
	{
		if (e)
			*e = error;
		[NSRConfig crashWithError:error];
	}
	return json;
}


//will turn it into a JSON string
//includes any nested models (which the json framework can't do)
- (NSString *) remoteJSONRepresentation
{
	return [self remoteJSONRepresentation:nil];
}

- (id) makeRelevantModelFromClass:(NSString *)classN basedOn:(NSDictionary *)dict
{
	//make a new class to be entered for this property/array (we can assume it subclasses NSRailsModel)
	NSRailsModel *model = [[NSClassFromString(classN) alloc] initWithRemoteAttributesDictionary:dict];
	
#ifndef NSRCompileWithARC
	[model autorelease];
#endif
	
	return model;
}

- (id) getCustomEnDecoding:(BOOL)YESforEncodingNOforDecoding forProperty:(NSString *)prop value:(id)val
{
	BOOL isArray = ([[[self class] getPropertyType:prop] isEqualToString:@"NSArray"] || 
					[[[self class] getPropertyType:prop] isEqualToString:@"NSMutableArray"]);
	
	//format: 1st %@ = "encode"/"decode"
	//        2nd %@ = "Property"
	//        3rd %@ = "Element" (if array)
	//        4th %@ = ":" (if decoding - encoding has no parameter)

	NSString *sel = [NSString stringWithFormat:@"%@%@%@%@",YESforEncodingNOforDecoding ? @"encode" : @"decode",[prop toClassName], isArray ? @"Element" : @"", YESforEncodingNOforDecoding ? @"" : @":"];
	
	SEL selector = NSSelectorFromString(sel);
	if ([self respondsToSelector:selector])
	{
		id obj = [self performSelector:selector withObject:val];
		
		if (YESforEncodingNOforDecoding)
		{
			//if encoding, make sure that the result is a JSON PARSE-ABLE!
			if (![obj isKindOfClass:[NSArray class]] &&
				![obj isKindOfClass:[NSDictionary class]] &&
				![obj isKindOfClass:[NSString class]] &&
				![obj isKindOfClass:[NSNumber class]])
			{
#ifdef NSRLogErrors
				NSLog(@"NSR Warning: Trying to encode property '%@' in class '%@', but the result from %@ was not JSON-parsable. Please make sure you return an NSDictionary, NSArray, NSString, or NSNumber here. Remember, these are the values you want to send in the JSON to Rails. Also, defining this encoder method will override the automatic NSDate translation.",prop, NSStringFromClass([self class]),sel);
#endif
			}
		}
		
		//only send back an NSNull object instead of nil if it's on ENcode, since we'll be ENcoding it into JSON, where that's relevant
		if (!obj && YESforEncodingNOforDecoding)
		{
			return [NSNull null];
		}
		return obj;
	}
	else
	{
		//try a "did you mean" without the plurality - maybe user mistyped
		NSString *didYouMean = [NSString stringWithFormat:@"%@%@%@:",YESforEncodingNOforDecoding ? @"encode" : @"decode",[[prop toClassName] substringToIndex:prop.length-1], isArray ? @"Element" : @""];
		if ([self respondsToSelector:NSSelectorFromString(didYouMean)])
		{
#ifdef NSRLogErrors
			NSLog(@"NSR Warning: Trying to %@code property '%@' in class '%@'. Found selector %@ but this isn't the right format. Make sure it's exactly \"%@code\"+\"property name ('%@')\" + \"Element:\", ie, proper format is %@. Please fix.",YESforEncodingNOforDecoding ? @"en" : @"de", prop, NSStringFromClass([self class]),didYouMean,YESforEncodingNOforDecoding ? @"en" : @"de",prop,sel);
#endif
		}
	}
	return nil;
}

- (id) objectForProperty:(NSString *)prop representation:(id)rep
{
	//if object is marked as decodable, use the decode method
	if ([[self propertyCollection].decodeProperties indexOfObject:prop] != NSNotFound)
	{
		//if object is an array, go through each and do decodable
		if ([rep isKindOfClass:[NSArray class]])
		{
			NSMutableArray *newArray = [NSMutableArray array];
			for (id object in rep)
			{
				id decodedElement = [self getCustomEnDecoding:NO forProperty:prop value:object];
				if (decodedElement)
					[newArray addObject:decodedElement];
			}
			return newArray;
		}
		//otherwise, return whatever is in decodable
		else
		{
			return [self getCustomEnDecoding:NO forProperty:prop value:rep];
		}
	}
	//if the object is of class NSDate and the representation in JSON is a string, automatically convert it to string
	else if ([[[self class] getPropertyType:prop] isEqualToString:@"NSDate"] && [rep isKindOfClass:[NSString class]])
	{
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		
		//format to whatever date format is defined in the config
		NSString *format = [[self class] getRelevantConfig].dateFormat;
		[formatter setDateFormat:format];
		
		NSDate *date = [formatter dateFromString:rep];
		
		if (!date)
		{
#ifdef NSRLogErrors
			NSLog(@"NSR Warning: Attempted to convert date string returned by Rails (\"%@\") into an NSDate* object for the property '%@' in class %@, but conversion failed. Please check your config's dateFormat (used format \"%@\" for this operation).",rep,prop,NSStringFromClass([self class]),format);
#endif
		}
		
#ifndef NSRCompileWithARC
		[formatter release];
#endif
		return date;
	}
	
	//otherwise, return whatever it is
	return rep;
}

- (id) representationOfObjectForProperty:(NSString *)prop
{
	SEL sel = [[self class] getPropertyGetter:prop];
	if ([self respondsToSelector:sel])
	{
		BOOL encodable = [[self propertyCollection].encodeProperties indexOfObject:prop] != NSNotFound;
		
		id val = [self performSelector:sel];
		BOOL isArray = [val isKindOfClass:[NSArray class]];
		
		//see if this property actually links to a custom NSRailsModel subclass, or it WASN'T declared, but is an array
		if ([[self propertyCollection].nestedModelProperties objectForKey:prop] || isArray)
		{
			//if the ivar is an array, we need to make every element into JSON and then put them back in the array
			if (isArray)
			{
				NSMutableArray *new = [NSMutableArray arrayWithCapacity:[val count]];

				for (int i = 0; i < [val count]; i++)
				{
					id element = [val objectAtIndex:i];
					
					id encodedObj;
					//if array is defined as encodable, encode each element
					if (encodable)
					{
						encodedObj = [self getCustomEnDecoding:YES forProperty:prop value:element];
					}
					//otherwise, use the NSRailsModel dictionaryOfRemoteProperties method to get that object in dictionary form
					if (!encodable || !encodedObj)
					{
						//but first make sure it's an NSRailsModel subclass
						if (![element isKindOfClass:[NSRailsModel class]])
							continue;
						
						encodedObj = [element dictionaryOfRemoteProperties];
					}
					
					[new addObject:encodedObj];
				}
				return new;
			}
			
			//otherwise, make that nested object a dictionary through NSRailsModel
			//first make sure it's an NSRailsModel subclass
			if (![val isKindOfClass:[NSRailsModel class]])
				return nil;
			
			return [val dictionaryOfRemoteProperties];
		}
		
		//if NOT linked property, if its declared as encodable, return encoded version
		if (encodable)
		{
			id obj = [self getCustomEnDecoding:YES forProperty:prop value:val];
			if (obj)
				return obj;
		}
		//if the object is of class NSDate, we need to automatically convert it to string for the JSON framework to handle correctly
		else if ([val isKindOfClass:[NSDate class]])
		{
			NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
			
			//format to whatever date format is defined in the config
			[formatter setDateFormat:[[self class] getRelevantConfig].dateFormat];
			
			NSString *dateValue = [formatter stringFromDate:val];
			
#ifndef NSRCompileWithARC
			[formatter release];
#endif
			return dateValue;
		}
		
		return val;
	}
	return nil;
}

- (id) initWithRemoteAttributesDictionary:(NSDictionary *)railsDict
{
	if ((self = [self init]))
	{
		[self setAttributesAsPerRemoteDictionary:railsDict];
	}
	return self;
}

- (void) setAttributesAsPerRemoteDictionary:(NSDictionary *)dict
{
	remoteAttributes = dict;
	
	for (NSString *objcProperty in [self propertyCollection].retrievableProperties)
	{
		NSString *railsEquivalent = [[self propertyCollection] equivalenceForProperty:objcProperty];
		if (!railsEquivalent)
		{
			//check to see if we should auto_underscore if no equivalence set
			if ([[self class] getRelevantConfig].automaticallyUnderscoreAndCamelize)
			{
				railsEquivalent = [objcProperty underscore];
			}
			//otherwise, assume that the rails equivalent is precisely how it's defined in obj-c
			else
			{
				railsEquivalent = objcProperty;
			}
		}
		SEL sel = [[self class] getPropertySetter:objcProperty];
		if ([self respondsToSelector:sel])
			//means its marked as retrievable and is settable through setEtc:.
		{
			id val = [dict objectForKey:railsEquivalent];
			//skip if the key doesn't exist (we probably guessed wrong above (or if the explicit equivalence was wrong))
			if (!val)
				continue;
			
			//get the intended value
			val = [self objectForProperty:objcProperty representation:([val isKindOfClass:[NSNull class]] ? nil : val)];
			if (val)
			{
				NSString *nestedClass = [[self propertyCollection].nestedModelProperties objectForKey:objcProperty];
				//instantiate it as the class specified in NSRailsSync if it hadn't already been custom-decoded
				if (nestedClass && [[self propertyCollection].decodeProperties indexOfObject:objcProperty] == NSNotFound)
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
					//if it's not an array and just a dict, make a new class based on that dict
					else
					{
						val = [self makeRelevantModelFromClass:nestedClass basedOn:[dict objectForKey:railsEquivalent]];
					}
				}
				//if there was no nested class specified, simply give it what JSON decoded (in the case of a nested model, it will be a dictionary, or, an array of dictionaries. don't worry, the user got ample warning)
				[self performSelector:sel withObject:val];
			}
			else
			{
				[self performSelector:sel withObject:nil];
			}
		}
	}
}

- (NSDictionary *) dictionaryOfRemoteProperties
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];

	for (NSString *objcProperty in [self propertyCollection].sendableProperties)
	{
		NSString *railsEquivalent = [[self propertyCollection] equivalenceForProperty:objcProperty];
		
		//check to see if we should auto_underscore if no equivalence set
		if (!railsEquivalent)
		{
			if ([[self class] getRelevantConfig].automaticallyUnderscoreAndCamelize)
			{
				railsEquivalent = [[objcProperty underscore] lowercaseString];
			}
			else
			{			
				railsEquivalent = objcProperty;
			}
		}
		
		id val = [self representationOfObjectForProperty:objcProperty];
		
		BOOL null = !val;
		
		//if we got back nil, we want to change that to the [NSNull null] object so it'll show up in the JSON
		//but only do it for non-ID properties - we want to omit ID if it's null (could be for create)
		if (!val && ![railsEquivalent isEqualToString:@"id"])
		{
			NSString *string = [[self class] getPropertyType:objcProperty];
			if ([string isEqualToString:@"NSArray"] || [string isEqualToString:@"NSMutableArray"])
			{
				//there's an array, and because the value is nil, make it an empty array (rails will get angry if you send null)
				val = [NSArray array];
			}
			else
			{
				val = [NSNull null];
			}
		}
		if (val)
		{
			BOOL isArray = [val isKindOfClass:[NSArray class]];
			
			//if it's an array, remove any null values (wouldn't make sense in the array)
			if (isArray)
			{
				for (int i = 0; i < [val count]; i++)
				{
					if ([[val objectAtIndex:i] isKindOfClass:[NSNull class]])
					{
						[val removeObjectAtIndex:i];
						i--;
					}
				}
			}
			
			//this is the belongs_to trick
			//if "-b" declared and it's not NSNull and the relation's remoteID exists, THEN, we should use _id instead of _attributes

			if (!isArray && 
				[[self propertyCollection] propertyIsMarkedBelongsTo:objcProperty] && 
				!null &&
				[val objectForKey:@"id"])
			{				
				railsEquivalent = [railsEquivalent stringByAppendingString:@"_id"];
				
				//set the value to be the actual ID
				val = [val objectForKey:@"id"];
			}
			
			//otherwise, if it's associative, use "_attributes" if not null (/empty for arrays)
			else if (([[self propertyCollection].nestedModelProperties objectForKey:objcProperty] || isArray) && !null)
			{
				railsEquivalent = [railsEquivalent stringByAppendingString:@"_attributes"];
			}
			
			//check to see if it was already set (ie, ignore if there are multiple properties pointing to the same rails attr)
			if (![dict objectForKey:railsEquivalent])
			{
				[dict setObject:val forKey:railsEquivalent];
			}
		}
	}

	if (remoteDestroyOnNesting)
	{
		[dict setObject:[NSNumber numberWithBool:remoteDestroyOnNesting] forKey:@"_destroy"];
	}
	
	return dict;
}

- (BOOL) setAttributesAsPerRemoteJSON:(NSString *)json
{
	if (!json)
	{
		NSLog(@"NSR Warning: Can't set attributes to nil JSON.");
		return NO;
	}
	
	NSError *e;
	NSDictionary *dict = [json JSONValue:&e];
	
	if (!dict)
	{
		[NSRConfig crashWithError:e];
		return NO;
	}
	
	[self setAttributesAsPerRemoteDictionary:dict];
	
	return YES;
}

//pop the warning suppressor defined above (for calling performSelector's in ARC)
#pragma clang diagnostic pop




#pragma mark -
#pragma mark HTTP Request stuff

+ (NSString *) routeForControllerRoute:(NSString *)route
{
	NSString *controller = [self getPluralModelName];
	if (controller)
	{
		//this means this method was called on an NSRailsMethod _subclass_, so appropriately point the method to its controller
		//eg, ([User makeGET:@"hello"] => myapp.com/users/hello)
		route = [NSString stringWithFormat:@"%@%@",controller, (route ? [@"/" stringByAppendingString:route] : @"")];
		
		//otherwise, if it was called on NSRailsModel (to access a "root method"), don't modify the route:
		//eg, ([NSRailsModel makeGET:@"hello"] => myapp.com/hello)
	}
	return route;
}

- (NSString *) routeForInstanceRoute:(NSString *)route error:(NSError **)error
{
	if (!self.remoteID)
	{
		NSError *e = [NSError errorWithDomain:@"NSRails" code:0 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Attempted to update or delete an object with no ID. (Instance of %@)",NSStringFromClass([self class])] forKey:NSLocalizedDescriptionKey]];
		if (error)
			*error = e;
		
		[NSRConfig crashWithError:e];
		return nil;
	}
	
	//make request on an instance, so make route "id", or "id/route" if there's an additional route included (1/edit)
	NSString *idAndMethod = [NSString stringWithFormat:@"%@%@",self.remoteID,(route ? [@"/" stringByAppendingString:route] : @"")];
	
	return [[self class] routeForControllerRoute:idAndMethod];
}


#pragma mark Performing actions on instances


- (NSString *) remoteMakeRequest:(NSString *)httpVerb requestBody:(NSString *)body route:(NSString *)route error:(NSError **)error
{
	route = [self routeForInstanceRoute:route error:error];
	if (route)
		return [[[self class] getRelevantConfig] resultForRequestType:httpVerb requestBody:body route:route sync:error orAsync:nil];
	return nil;
}

- (void) remoteMakeRequest:(NSString *)httpVerb requestBody:(NSString *)body route:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	NSError *error;
	route = [self routeForInstanceRoute:route error:&error];
	if (route)
		[[[self class] getRelevantConfig] resultForRequestType:httpVerb requestBody:body route:route sync:nil orAsync:completionBlock];
	else
		completionBlock(nil, error);
}

//these are really just convenience methods that'll call the above method sending the object data as request body

- (NSString *) remoteMakeRequestSendingSelf:(NSString *)httpVerb route:(NSString *)route error:(NSError **)error
{
	NSString *json = [self remoteJSONRepresentation:error];
	if (json)
		return [self remoteMakeRequest:httpVerb requestBody:json route:route error:error];
	return nil;
}

- (void) remoteMakeRequestSendingSelf:(NSString *)httpVerb route:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	NSError *e;
	NSString *json = [self remoteJSONRepresentation:&e];
	if (json)
		[self remoteMakeRequest:httpVerb requestBody:json route:route async:completionBlock];
	else
		completionBlock(nil, e);
}

//these are really just convenience methods that'll call the above method with pre-built "GET" and no body

- (NSString *) remoteMakeGETRequestWithRoute:(NSString *)route error:(NSError **)error
{
	return [self remoteMakeRequest:@"GET" requestBody:nil route:route error:error];
}

- (void) remoteMakeGETRequestWithRoute:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	[self remoteMakeRequest:@"GET" requestBody:nil route:route async:completionBlock];
}


#pragma mark Performing actions on classes


+ (NSString *)	remoteMakeRequest:(NSString *)httpVerb requestBody:(NSString *)body route:(NSString *)route error:(NSError **)error
{
	route = [self routeForControllerRoute:route];
	return [[[self class] getRelevantConfig] resultForRequestType:httpVerb requestBody:body route:route sync:error orAsync:nil];
}

+ (void) remoteMakeRequest:(NSString *)httpVerb requestBody:(NSString *)body route:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	route = [self routeForControllerRoute:route];
	[[[self class] getRelevantConfig] resultForRequestType:httpVerb requestBody:body route:route sync:nil orAsync:completionBlock];
}

//these are really just convenience methods that'll call the above method with the JSON representation of the object

+ (NSString *) remoteMakeRequest:(NSString *)httpVerb sendObject:(NSRailsModel *)obj route:(NSString *)route error:(NSError **)error
{
	NSString *json = [obj remoteJSONRepresentation:error];
	if (json)
		return [self remoteMakeRequest:httpVerb requestBody:json route:route error:error];
	return nil;
}

+ (void) remoteMakeRequest:(NSString *)httpVerb sendObject:(NSRailsModel *)obj route:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	NSError *e;
	NSString *json = [obj remoteJSONRepresentation:&e];
	if (json)
		[self remoteMakeRequest:httpVerb requestBody:json route:route async:completionBlock];
	else
		completionBlock(nil, e);
}

//these are really just convenience methods that'll call the above method with pre-built "GET" and no body

+ (NSString *) remoteMakeGETRequestWithRoute:(NSString *)route error:(NSError **)error
{
	return [self remoteMakeRequest:@"GET" requestBody:nil route:route error:error];
}

+ (void) remoteMakeGETRequestWithRoute:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	[self remoteMakeRequest:@"GET" requestBody:nil route:route async:completionBlock];
}



#pragma mark -
#pragma mark External stuff (CRUD)

#pragma mark Create

- (BOOL) remoteCreate {	return [self remoteCreate:nil];	}
- (BOOL) remoteCreate:(NSError **)error
{
	NSString *jsonResponse = [[self class] remoteMakeRequest:@"POST" sendObject:self route:nil error:error];
	
	//check to see if json exists, and if it does, set obj's attributes to it (ie, set remoteID), and return if it worked
	return (jsonResponse && [self setAttributesAsPerRemoteJSON:jsonResponse]);
}
- (void) remoteCreateAsync:(NSRBasicCompletionBlock)completionBlock
{
	[[self class] remoteMakeRequest:@"POST" sendObject:self route:nil async:
	 
	 ^(NSString *result, NSError *error) {
		 if (result)
			 [self setAttributesAsPerRemoteJSON:result];
		 completionBlock(error);
	 }];
}

#pragma mark Update

- (BOOL) remoteUpdate {	return [self remoteUpdate:nil];	}
- (BOOL) remoteUpdate:(NSError **)error
{
	//makeRequest will actually return a result string, so return if it's not nil (!! = not nil, nifty way to turn object to BOOL)
	return !![self remoteMakeRequestSendingSelf:@"PUT" route:nil error:error];
}
- (void) remoteUpdateAsync:(NSRBasicCompletionBlock)completionBlock
{
	[self remoteMakeRequestSendingSelf:@"PUT" route:nil async:
	 
	 ^(NSString *result, NSError *error) {
		 completionBlock(error);
	 }];
}

#pragma mark Destroy

- (BOOL) remoteDestroy { return [self remoteDestroy:nil]; }
- (BOOL) remoteDestroy:(NSError **)error
{
	return (!![self remoteMakeRequest:@"DELETE" requestBody:nil route:nil error:error]);
}
- (void) remoteDestroyAsync:(NSRBasicCompletionBlock)completionBlock
{
	[self remoteMakeRequest:@"DELETE" requestBody:nil route:nil async:
	 
	 ^(NSString *result, NSError *error) {
		completionBlock(error);
	}];
}

#pragma mark Get latest

- (BOOL) remoteGetLatest {	return [self remoteGetLatest:nil]; }
- (BOOL) remoteGetLatest:(NSError **)error
{
	NSString *json = [self remoteMakeGETRequestWithRoute:nil error:error];
	return (json && [self setAttributesAsPerRemoteJSON:json]); //will return true/false if conversion worked
}
- (void) remoteGetLatestAsync:(NSRBasicCompletionBlock)completionBlock
{
	[self remoteMakeGETRequestWithRoute:nil async:
	 
	 ^(NSString *result, NSError *error) 
	 {
		 if (result)
			 [self setAttributesAsPerRemoteJSON:result];
		 completionBlock(error);
	 }];
}

#pragma mark Get specific object (class-level)

+ (id) remoteObjectWithID:(NSInteger)mID	{ return [self remoteObjectWithID:mID error:nil]; }
+ (id) remoteObjectWithID:(NSInteger)mID error:(NSError **)error
{
	NSRailsModel *obj = [[[self class] alloc] init];
	obj.remoteID = [NSDecimalNumber numberWithInteger:mID];
	
	if (![obj remoteGetLatest:error])
		obj = nil;
	
#ifndef NSRCompileWithARC
	[obj autorelease];
#endif
	
	return obj;
}
+ (void) remoteObjectWithID:(NSInteger)mID async:(NSRGetObjectCompletionBlock)completionBlock
{
	//see comments for previous method
	NSRailsModel *obj = [[[self class] alloc] init];
	obj.remoteID = [NSDecimalNumber numberWithInteger:mID];
	
#ifndef NSRCompileWithARC
	[obj autorelease];
#endif
	
	[obj remoteGetLatestAsync:
	 
	 ^(NSError *error) {
		if (error)
			completionBlock(nil, error);
		else
			completionBlock(obj, error);
	}];
}

#pragma mark Get all objects (class-level)

//helper method for both sync+async for remoteAll
+ (NSArray *) arrayOfModelsFromJSON:(NSString *)json error:(NSError **)error
{
	NSError *jsonError;
	
	//transform result into array (via json)
	id arr = [json JSONValue:&jsonError];
	
	if (!arr)
	{
		*error = jsonError;
		return nil;
	}
	
	if (![arr isKindOfClass:[NSArray class]])
	{
		NSError *e = [NSError errorWithDomain:@"NSRails" 
										 code:0 
									 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"getAll method (index) for %@ controller did not return an array - check your rails app.",[self getPluralModelName]]
																		  forKey:NSLocalizedDescriptionKey]];
		
		if (error)
			*error = e;
		
		[NSRConfig crashWithError:e];
		
		return nil;
	}
	
	//here comes actually making the array to return
	
	NSMutableArray *objects = [NSMutableArray array];
	
	//iterate through every object returned by Rails (as dicts)
	for (NSDictionary *dict in arr)
	{
		NSRailsModel *obj = [[[self class] alloc] initWithRemoteAttributesDictionary:dict];	
		
		[objects addObject:obj];
		
#ifndef NSRCompileWithARC
		[obj release];
#endif
	}
	
	return objects;
}

+ (NSArray *) remoteAll {	return [self remoteAll:nil]; }
+ (NSArray *) remoteAll:(NSError **)error
{
	//make a class GET call (so just the controller - myapp.com/users)
	NSString *json = [self remoteMakeGETRequestWithRoute:nil error:error];
	if (!json)
	{
		return nil;
	}
	return [self arrayOfModelsFromJSON:json error:error];
}

+ (void) remoteAllAsync:(NSRGetAllCompletionBlock)completionBlock
{
	[self remoteMakeGETRequestWithRoute:nil async:
	 ^(NSString *result, NSError *error) 
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
#pragma mark NSCoding

- (id) initWithCoder:(NSCoder *)aDecoder
{
	if (self = [super init])
	{
		self.remoteID = [aDecoder decodeObjectForKey:@"remoteID"];
		remoteAttributes = [aDecoder decodeObjectForKey:@"remoteAttributes"];
		self.remoteDestroyOnNesting = [aDecoder decodeBoolForKey:@"remoteDestroyOnNesting"];
		
		customProperties = [aDecoder decodeObjectForKey:@"customProperties"];
	}
	return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:remoteID forKey:@"remoteID"];
	[aCoder encodeObject:remoteAttributes forKey:@"remoteAttributes"];
	[aCoder encodeBool:remoteDestroyOnNesting forKey:@"remoteDestroyOnNesting"];
	
	[aCoder encodeObject:customProperties forKey:@"customProperties"];
}

#pragma mark -
#pragma mark Dealloc for non-ARC
#ifndef NSRCompileWithARC

- (void) dealloc
{
	[remoteID release];
	[remoteAttributes release];
	[customProperties release];
	
	[super dealloc];
}

#endif

@end
