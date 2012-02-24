//
//  NSRailsModel.m
//  NSRails
//
//  Created by Dan Hassin on 1/10/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRails.h"

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


//this will be the NSRailsSync for NSRailsModel, basis for all subclasses
//use modelID as equivalent for rails property id
#define NSRAILS_BASE_PROPS @"modelID=id"

//this is the marker for the propertyEquivalents dictionary if there's no explicit equivalence set
#define NSRNoEquivalentMarker @""

//this will be the marker for any property that has the "-b flag"
//this gonna go in the nestedModelProperties (properties can never have a comma/space in them so we're safe from any conflicts)
#define NSRBelongsToKeyForProperty(prop) [prop stringByAppendingString:@", belongs_to"]

@interface NSRailsModel (internal)

+ (NSRConfig *) getRelevantConfig;

+ (NSString *) railsProperties;
+ (NSString *) getModelName;
+ (NSString *) getPluralModelName;

@end

@interface NSRConfig (access)

+ (NSRConfig *) overrideConfig;
+ (void) crashWithError:(NSError *)error;
- (NSString *) resultForRequestType:(NSString *)type requestBody:(NSString *)requestStr route:(NSString *)route sync:(NSError **)error orAsync:(NSRHTTPCompletionBlock)completionBlock;

@end


@implementation NSRailsModel
@synthesize modelID, destroyOnNesting, railsAttributes;



#pragma mark -
#pragma mark Meta-NSR stuff

//this will suppress the compiler warnings that come with ARC when doing performSelector
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"


+ (NSString *) NSRailsSync
{
	return NSRAILS_BASE_PROPS;
}

+ (NSString *) railsProperties
{
	//start it off with the NSRails base ("modelID=id")
	NSString *finalProperties = NSRAILS_BASE_PROPS;
	
	BOOL stopInheriting = NO;
	
	//go up the class hierarchy, starting at self, adding the property list from each class
	for (Class c = self; (c != [NSRailsModel class] && !stopInheriting); c = [c superclass])
	{
		if ([c respondsToSelector:@selector(NSRailsSync)])
		{			
			NSString *syncString = [c NSRailsSync];
			
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
			
			finalProperties = [finalProperties stringByAppendingFormat:@", %@", syncString];
		}
	}
	
	return finalProperties;
}

//purely for testing purposes - never used otherwise
- (NSString *) listOfSendableProperties
{
	NSMutableString *str = [NSMutableString string];
	for (NSString *property in sendableProperties)
	{
		[str appendFormat:@"%@, ",property];
	}
	return [str substringToIndex:str.length-2];
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

- (void) addPropertyAsSendable:(NSString *)prop equivalent:(NSString *)equivalent
{
	//for sendable, we can only have ONE property which per Rails attribute which is marked as sendable
	//  (otherwise, which property's value should we stick in the json?)
	
	//so, see if there are any other properties defined so far with the same Rails equivalent that are marked as sendable
	NSArray *objs = [propertyEquivalents allKeysForObject:equivalent];
	NSMutableArray *sendables = [NSMutableArray arrayWithObject:prop];
	for (NSString *sendable in objs)
	{
		if ([sendableProperties indexOfObject:sendable] != NSNotFound)
			[sendables addObject:sendable];
	}
	//greater than 1 cause we're including this property
	if (equivalent && sendables.count > 1)
	{
		if ([equivalent isEqualToString:@"id"])
		{
#ifdef NSRLogErrors
			NSLog(@"NSR Warning: Obj-C property %@ (class %@) found to set equivalence with 'id'. This is fine for retrieving but should not be marked as sendable. Ignoring this property on send.", prop, NSStringFromClass([self class]));
#endif
		}
		else
		{
#ifdef NSRLogErrors
			NSLog(@"NSR Warning: Multiple Obj-C properties marked as sendable (%@) found pointing to the same Rails attribute ('%@'). Only using data from the first Obj-C property listed. Please fix by only having one sendable property per Rails attribute (you can make the others retrieve-only with the -r flag).", sendables, equivalent);
#endif
		}
	}
	else
	{
		[sendableProperties addObject:prop];
	}
}

- (id) initWithRailsSyncProperties:(NSString *)props
{
	if ((self = [super init]))
	{
		//if was called manually and doesn't include the NSRails base sync properties, add them now
		if ([props rangeOfString:NSRAILS_BASE_PROPS].location == NSNotFound)
		{
			props = [NSRAILS_BASE_PROPS stringByAppendingFormat:@", %@",props];
		}
		
		//log on param string for testing
		//NSLog(@"found props %@",props);
		
		//initialize property categories
		sendableProperties = [[NSMutableArray alloc] init];
		retrievableProperties = [[NSMutableArray alloc] init];
		nestedModelProperties = [[NSMutableDictionary alloc] init];
		propertyEquivalents = [[NSMutableDictionary alloc] init];
		encodeProperties = [[NSMutableArray alloc] init];
		decodeProperties = [[NSMutableArray alloc] init];
		
		destroyOnNesting = NO;
		
		//here begins the code used for parsing the NSRailsSync param string
		
		NSCharacterSet *wn = [NSCharacterSet whitespaceAndNewlineCharacterSet];
		
		//exclusion array for any properties declared as -x (will later remove properties from * definition)
		NSMutableArray *exclude = [NSMutableArray array];
		
		//check to see if we should even consider *
		BOOL markedAll = ([props rangeOfString:@"*"].location != NSNotFound);
		
		//marked as NO for the first time in the loop
		//if a * appeared (markedAll is true), this will enable by the end of the loop and the whole thing will loop again, for the *
		BOOL onStarIteration = NO;
		
		do
		{
			NSMutableArray *elements;

			if (onStarIteration)
			{
				//make sure we don't loop again
				onStarIteration = NO;
				markedAll = NO;
				
				NSMutableArray *relevantIvars = [NSMutableArray array];
				
				//go up the class hierarchy
				Class c = [self class];				
				while (c != [NSRailsModel class])
				{
					NSString *properties = [c NSRailsSync];
					
					//if there's a *, add all ivars from that class
					if ([properties rangeOfString:@"*"].location != NSNotFound)
						[relevantIvars addObjectsFromArray:[c classPropertyNames]];
					
					//if there's a NoCarryFromSuper, stop the loop right there since we don't want stuff from any more superclasses
					if ([properties rangeOfString:_NSRNoCarryFromSuper_STR].location != NSNotFound)
						break;
					
					c = [c superclass];
				}
				
				
				elements = [NSMutableArray array];
				//go through all the ivars we found
				for (NSString *ivar in relevantIvars)
				{
					//if it hasn't been previously declared (from the first run), add it to the list we have to process
					if (![propertyEquivalents objectForKey:ivar])
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
				NSString *element = [[elements objectAtIndex:i] stringByTrimmingCharactersInSet:wn];
				
				//skip if there's no NSRailsSync definition (ie, it just inherited NSRailsModel's, so it's not the first time through but it's the same thing as NSRailsModel's)
				if ([element isEqualToString:NSRAILS_BASE_PROPS] && i != 0)
				{
					continue;
				}
				
				//remove any NSRNoCarryFromSuper's to not screw anything up
				NSString *prop = [element stringByReplacingOccurrencesOfString:_NSRNoCarryFromSuper_STR withString:@""];
				
				if (prop.length > 0)
				{
					if ([prop rangeOfString:@"*"].location != NSNotFound)
					{
						//if there's a * in this piece, skip it (we already accounted for stars above)
						continue;
					}
					
					if ([exclude containsObject:prop])
					{
						//if it's been marked with '-x' flag previously, ignore it
						continue;
					}
					
					//prop can be something like "username=user_name:Class -etc"
					//find string sets between =, :, and -
					NSArray *opSplit = [prop componentsSeparatedByString:@"-"];
					NSArray *modSplit = [[opSplit objectAtIndex:0] componentsSeparatedByString:@":"];
					NSArray *eqSplit = [[modSplit objectAtIndex:0] componentsSeparatedByString:@"="];
					
					prop = [[eqSplit objectAtIndex:0] stringByTrimmingCharactersInSet:wn];
					
					//check to see if a class is redefining modelID (modelID from NSRailsModel is the first property checked - if it's not the first, give a warning)
					if ([prop isEqualToString:@"modelID"] && i != 0)
					{
#ifdef NSRLogErrors
						NSLog(@"NSR Warning: Found attempt to define 'modelID' in NSRailsSync for class %@. This property is reserved by the NSRailsModel superclass and should not be modified. Please fix this; element ignored.", NSStringFromClass([self class]));
#endif
						continue;
					}
					
					NSString *options = [opSplit lastObject];
					//if it was marked exclude, add to exclude list in case * was declared, and skip over anything else
					if (opSplit.count > 1 && [options rangeOfString:@"x"].location != NSNotFound)
					{
						[exclude addObject:prop];
						continue;
					}
					
					//check to see if the listed property even exists
					NSString *ivarType = [self getPropertyType:prop];
					if (!ivarType)
					{
#ifdef NSRLogErrors
						NSLog(@"NSR Warning: Property '%@' declared in NSRailsSync for class %@ was not found in this class or in superclasses. Maybe you forgot to @synthesize it? Element ignored.", prop, NSStringFromClass([self class]));
#endif
						continue;
					}
					
					//make sure that the property type is not a primitive
					NSString *primitive = [self propertyIsPrimitive:prop];
					if (primitive)
					{
#ifdef NSRLogErrors
						NSLog(@"NSR Warning: Property '%@' declared in NSRailsSync for class %@ was found to be of primitive type '%@' - please use NSNumber*. Element ignored.", prop, NSStringFromClass([self class]), primitive);
#endif
						continue;
					}
					
					//see if there are any = declared
					NSString *equivalent = nil;
					if (eqSplit.count > 1)
					{
						//set the equivalence to the last element after the =
						equivalent = [[eqSplit lastObject] stringByTrimmingCharactersInSet:wn];
						
						[propertyEquivalents setObject:equivalent forKey:prop];
					}
					else
					{
						//if no property explicitly set, make it NSRNoEquivalentMarker
						//later on we'll see if automaticallyCamelize is on for the config and get the equivalence accordingly
						[propertyEquivalents setObject:NSRNoEquivalentMarker forKey:prop];
					}
					
					if (opSplit.count > 1)
					{
						if ([options rangeOfString:@"r"].location != NSNotFound)
							[retrievableProperties addObject:prop];
						
						if ([options rangeOfString:@"s"].location != NSNotFound)
							[self addPropertyAsSendable:prop equivalent:equivalent];
						
						if ([options rangeOfString:@"e"].location != NSNotFound)
							[encodeProperties addObject:prop];
						
						if ([options rangeOfString:@"d"].location != NSNotFound)
							[decodeProperties addObject:prop];
						
						//add a special marker in nestedModelProperties dict
						if ([options rangeOfString:@"b"].location != NSNotFound)
							[nestedModelProperties setObject:[NSNumber numberWithBool:YES] forKey:NSRBelongsToKeyForProperty(prop)];
					}
					
					//if no options are defined or some are but neither -s nor -r are defined, by default add sendable+retrievable
					if (opSplit.count == 1 ||
						([options rangeOfString:@"s"].location == NSNotFound && [options rangeOfString:@"r"].location == NSNotFound))
					{
						[self addPropertyAsSendable:prop equivalent:equivalent];
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
								NSLog(@"NSR Warning: Failed to find class '%@', declared as class for nested property '%@' of class '%@'. Nesting relation not set - will still send any NSRailsModel subclasses correctly but will always retrieve as NSDictionaries. ",otherModel,prop,NSStringFromClass([self class]));
#endif
							}
							//class entered is not a subclass of NSRailsModel
							else if (![NSClassFromString(otherModel) isSubclassOfClass:[NSRailsModel class]])
							{
#ifdef NSRLogErrors
								NSLog(@"NSR Warning: '%@' was declared as the class for the nested property '%@' of class '%@', but '%@' is not a subclass of NSRailsModel. Nesting relation not set - won't be able to send or retrieve this property.",otherModel,prop, NSStringFromClass([self class]),otherModel);
#endif
							}
							else
							{
								[nestedModelProperties setObject:otherModel forKey:prop];
							}
						}
					}
					else
					{
						//if no : was declared for this property, check to see if we should link it anyway
						
						if ([ivarType isEqualToString:@"NSArray"] ||
							[ivarType isEqualToString:@"NSMutableArray"])
						{
#ifdef NSRLogErrors
							NSLog(@"NSR Warning: Property '%@' in class %@ was found to be an array, but no nesting model was set. Note that without knowing with which models NSR should populate the array, NSDictionaries with the retrieved Rails attributes will be set. If NSDictionaries are desired, to suppress this warning, simply add a colon with nothing following to the property in NSRailsSync... '%@:'",prop,NSStringFromClass([self class]),element);
#endif
						}
						else if (!([ivarType isEqualToString:@"NSString"] ||
								   [ivarType isEqualToString:@"NSMutableString"] ||
								   [ivarType isEqualToString:@"NSDictionary"] ||
								   [ivarType isEqualToString:@"NSMutableDictionary"] ||
								   [ivarType isEqualToString:@"NSNumber"] ||
								   [ivarType isEqualToString:@"NSDate"]))
						{
							//must be custom obj, see if its a railsmodel, if it is, link it automatically
							Class c = NSClassFromString(ivarType);
							if (c && [c isSubclassOfClass:[NSRailsModel class]])
							{
								//automatically link that ivar type (ie, Pet) for that property (ie, pets)
								[nestedModelProperties setObject:ivarType forKey:prop];
							}
						}
					}
				}
			}
			
			//if markedAll (a * was encountered somewhere), loop again one more time to add all properties not already listed (*)
			if (markedAll)
				onStarIteration = YES;
		} 
		while (onStarIteration);
		
		// for testing's sake
		//		NSLog(@"-------- %@ ----------",[[self class] getModelName]);
		//		NSLog(@"list: %@",props);
		//		NSLog(@"sendable: %@",sendableProperties);
		//		NSLog(@"retrievable: %@",retrievableProperties);
		//		NSLog(@"NMP: %@",nestedModelProperties);
		//		NSLog(@"eqiuvalents: %@",propertyEquivalents);
		//		NSLog(@"\n");
	}
	
	return self;
}

- (id) init
{
	NSString *props = [[self class] railsProperties];
	
	if ((self = [self initWithRailsSyncProperties:props]))
	{
		//nothing special...
	}
	return self;
}





#pragma mark -
#pragma mark Internal NSR stuff

//overload NSObject's description method to be a bit more, hm... descriptive
//will return the latest Rails dictionary (hash) retrieved
- (NSString *) description
{
	if (railsAttributes)
		return [railsAttributes description];
	return [super description];
}

- (NSString *) railsJSONRepresentation:(NSError **)e
{
	// enveloped meaning with the model name out front, {"user"=>{"name"=>"x", "password"=>"y"}}
	
	NSDictionary *enveloped = [NSDictionary dictionaryWithObject:[self dictionaryOfRailsRelevantProperties]
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
- (NSString *) railsJSONRepresentation
{
	return [self railsJSONRepresentation:nil];
}

- (id) makeRelevantModelFromClass:(NSString *)classN basedOn:(NSDictionary *)dict
{
	//make a new class to be entered for this property/array (we can assume it subclasses NSRailsModel)
	NSRailsModel *model = [[NSClassFromString(classN) alloc] initWithRailsAttributesDictionary:dict];
	
#ifndef NSRCompileWithARC
	[model autorelease];
#endif
	
	return model;
}

- (id) getCustomEnDecoding:(BOOL)YESforEncodingNOforDecoding forProperty:(NSString *)prop value:(id)val
{
	BOOL isArray = ([[self getPropertyType:prop] isEqualToString:@"NSArray"] || 
					[[self getPropertyType:prop] isEqualToString:@"NSMutableArray"]);
	
	//if prop is an array, add "Element", so it'll be encodeArrayElement: , otherwise, encodeWhatever:
	NSString *sel = [NSString stringWithFormat:@"%@%@%@:",YESforEncodingNOforDecoding ? @"encode" : @"decode",[prop toClassName], isArray ? @"Element" : @""];
	
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
	if ([decodeProperties indexOfObject:prop] != NSNotFound)
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
	else if ([[self getPropertyType:prop] isEqualToString:@"NSDate"] && [rep isKindOfClass:[NSString class]])
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
	SEL sel = [self getPropertyGetter:prop];
	if ([self respondsToSelector:sel])
	{
		BOOL encodable = [encodeProperties indexOfObject:prop] != NSNotFound;
		
		id val = [self performSelector:sel];
		BOOL isArray = [val isKindOfClass:[NSArray class]];
		
		//see if this property actually links to a custom NSRailsModel subclass, or it WASN'T declared, but is an array
		if ([nestedModelProperties objectForKey:prop] || isArray)
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
					//otherwise, use the NSRailsModel dictionaryOfRailsRelevantProperties method to get that object in dictionary form
					if (!encodable || !encodedObj)
					{
						//but first make sure it's an NSRailsModel subclass
						if (![element isKindOfClass:[NSRailsModel class]])
							continue;
						
						encodedObj = [element dictionaryOfRailsRelevantProperties];
					}
					
					[new addObject:encodedObj];
				}
				return new;
			}
			
			//otherwise, make that nested object a dictionary through NSRailsModel
			//first make sure it's an NSRailsModel subclass
			if (![val isKindOfClass:[NSRailsModel class]])
				return nil;
			
			return [val dictionaryOfRailsRelevantProperties];
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

- (id) initWithRailsAttributesDictionary:(NSDictionary *)railsDict
{
	if ((self = [self init]))
	{
		[self setAttributesAsPerRailsDictionary:railsDict];
	}
	return self;
}

- (void) setAttributesAsPerRailsDictionary:(NSDictionary *)dict
{
	railsAttributes = dict;
	
	for (NSString *objcProperty in retrievableProperties)
	{
		NSString *railsEquivalent = [propertyEquivalents objectForKey:objcProperty];
		if ([railsEquivalent isEqualToString:NSRNoEquivalentMarker])
		{
			//means there was no equivalence defined.
			//if config supports underscoring and camelizing, guess the rails equivalent by underscoring
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
		SEL sel = [self getPropertySetter:objcProperty];
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
				NSString *nestedClass = [[nestedModelProperties objectForKey:objcProperty] toClassName];
				//instantiate it as the class specified in NSRailsSync if it hadn't already been custom-decoded
				if (nestedClass && [decodeProperties indexOfObject:objcProperty] == NSNotFound)
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

- (NSDictionary *) dictionaryOfRailsRelevantProperties
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];

	for (NSString *objcProperty in sendableProperties)
	{
		NSString *railsEquivalent = [propertyEquivalents objectForKey:objcProperty];
		
		//check to see if we should auto_underscore if no equivalence set
		if ([railsEquivalent isEqualToString:NSRNoEquivalentMarker])
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
			NSString *string = [self getPropertyType:objcProperty];
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
			//if "-b" declared and it's not NSNull and the relation's modelID exists, THEN, we should use _id instead of _attributes

			if (!isArray && 
				[nestedModelProperties objectForKey:NSRBelongsToKeyForProperty(objcProperty)] && 
				!null &&
				[val objectForKey:@"id"])
			{				
				railsEquivalent = [railsEquivalent stringByAppendingString:@"_id"];
				
				//set the value to be the actual ID
				val = [val objectForKey:@"id"];
			}
			
			//otherwise, if it's included in nestedModelProperties OR it's an array, use "_attributes" if not null (/empty for arrays)
			else if (([nestedModelProperties objectForKey:objcProperty] || isArray) && !null)
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

	if (destroyOnNesting)
	{
		[dict setObject:[NSNumber numberWithBool:destroyOnNesting] forKey:@"_destroy"];
	}
	
	return dict;
}

- (BOOL) setAttributesAsPerRailsJSON:(NSString *)json
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
	
	[self setAttributesAsPerRailsDictionary:dict];
	
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
	if (!self.modelID)
	{
		NSError *e = [NSError errorWithDomain:@"NSRails" code:0 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Attempted to update or delete an object with no ID. (Instance of %@)",NSStringFromClass([self class])] forKey:NSLocalizedDescriptionKey]];
		if (error)
			*error = e;
		
		[NSRConfig crashWithError:e];
		return nil;
	}
	
	//make request on an instance, so make route "id", or "id/route" if there's an additional route included (1/edit)
	NSString *idAndMethod = [NSString stringWithFormat:@"%@%@",self.modelID,(route ? [@"/" stringByAppendingString:route] : @"")];
	
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
	NSString *json = [self railsJSONRepresentation:error];
	if (json)
		return [self remoteMakeRequest:httpVerb requestBody:json route:route error:error];
	return nil;
}

- (void) remoteMakeRequestSendingSelf:(NSString *)httpVerb route:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	NSError *e;
	NSString *json = [self railsJSONRepresentation:&e];
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
	NSString *json = [obj railsJSONRepresentation:error];
	if (json)
		return [self remoteMakeRequest:httpVerb requestBody:json route:route error:error];
	return nil;
}

+ (void) remoteMakeRequest:(NSString *)httpVerb sendObject:(NSRailsModel *)obj route:(NSString *)route async:(NSRHTTPCompletionBlock)completionBlock
{
	NSError *e;
	NSString *json = [obj railsJSONRepresentation:&e];
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
	
	//check to see if json exists, and if it does, set obj's attributes to it (ie, set modelID), and return if it worked
	return (jsonResponse && [self setAttributesAsPerRailsJSON:jsonResponse]);
}
- (void) remoteCreateAsync:(NSRBasicCompletionBlock)completionBlock
{
	[[self class] remoteMakeRequest:@"POST" sendObject:self route:nil async:
	 
	 ^(NSString *result, NSError *error) {
		 if (result)
			 [self setAttributesAsPerRailsJSON:result];
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
	return (json && [self setAttributesAsPerRailsJSON:json]); //will return true/false if conversion worked
}
- (void) remoteGetLatestAsync:(NSRBasicCompletionBlock)completionBlock
{
	[self remoteMakeGETRequestWithRoute:nil async:
	 
	 ^(NSString *result, NSError *error) 
	 {
		 if (result)
			 [self setAttributesAsPerRailsJSON:result];
		 completionBlock(error);
	 }];
}

#pragma mark Get specific object (class-level)

+ (id) remoteObjectWithID:(NSInteger)mID	{ return [self remoteObjectWithID:mID error:nil]; }
+ (id) remoteObjectWithID:(NSInteger)mID error:(NSError **)error
{
	NSRailsModel *obj = [[[self class] alloc] init];
	obj.modelID = [NSDecimalNumber numberWithInteger:mID];
	
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
	obj.modelID = [NSDecimalNumber numberWithInteger:mID];
	
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
		NSRailsModel *obj = [[[self class] alloc] initWithRailsAttributesDictionary:dict];	
		
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
#pragma mark Dealloc for non-ARC
#ifndef NSRCompileWithARC

- (void) dealloc
{
	[modelID release];
	[railsAttributes release];
	
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
