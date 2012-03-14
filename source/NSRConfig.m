//
//  NSRConfig.m
//  NSRails
//
//  Created by Dan Hassin on 1/28/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "NSRConfig.h"

#import "NSRails+SBJson.h"
#import "NSData+Additions.h"

//NSRConfigStackElement implementation

//this small helper class is used to keep track of which config is contextually relevant
//a stack is used so that -[NSRConfig use] commands can be nested
//the problem with simply adding the NSRConfig to an NSMutableArray stack is that it will act funny if it's added multiple times (since an instance can only exist once in an array) and removing is even more of a nightmare

//the stack will be comprised of this element, whose sole purpose is to point to a config, meaning it can be pushed to the stack multiple times if needed be

@interface NSRConfigStackElement : NSObject
@property (nonatomic, assign) NSRConfig *config;
@end
@implementation NSRConfigStackElement
@synthesize config;
+ (NSRConfigStackElement *) elementForConfig:(NSRConfig *)c
{
	NSRConfigStackElement *element = [[NSRConfigStackElement alloc] init];
	element.config = c;
	return element;
}
@end




//NSRConfig implementation

@interface NSRConfig (private) 

- (NSString *) makeHTTPRequestWithRequest:(NSURLRequest *)request sync:(NSError **)error orAsync:(NSRHTTPCompletionBlock)completionBlock;

@end

@implementation NSRConfig
@synthesize appURL, appUsername, appPassword, dateFormat, automaticallyUnderscoreAndCamelize;

#pragma mark -
#pragma mark Config inits

static NSMutableDictionary *configEnvironments = nil;
static NSMutableArray *overrideConfigStack = nil;
static NSString *currentEnvironment = NSRConfigEnvironmentDevelopment;

//purely for test purposes
+ (void) resetConfigs
{
	//taken from static definitions above ^
	configEnvironments = nil;
	overrideConfigStack = nil;
	currentEnvironment = NSRConfigEnvironmentDevelopment;
}

+ (NSRConfig *) configForEnvironment: (NSString *)environment
{
	NSRConfig *config = [configEnvironments objectForKey:environment];
	if (!config)
	{
		config = [[NSRConfig alloc] init];
		[self setConfig:config asDefaultForEnvironment:environment];
	}
	return config;
}

+ (NSRConfig *) defaultConfig
{
	return [self configForEnvironment:currentEnvironment];
}

+ (void) setConfig:(NSRConfig *)config asDefaultForEnvironment:(NSString *)environment
{
	if (!configEnvironments)
		configEnvironments = [[NSMutableDictionary alloc] init];
	if (config)
		[configEnvironments setObject:config forKey:environment];
}

+ (void) setConfigAsDefault:(NSRConfig *)config
{
	[self setConfig:config asDefaultForEnvironment:currentEnvironment];
}

+ (void) setCurrentEnvironment:(NSString *)environment
{
	if (!environment)
		environment = NSRConfigEnvironmentDevelopment;
	currentEnvironment = environment;
}

+ (NSString *) currentEnvironment
{
	return currentEnvironment;
}

- (id) init
{
	if ((self = [super init]))
	{
		//by default, set to accept datestring like "2012-02-01T00:56:24Z"
		//this format (ISO 8601) is default in rails
		self.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";
		automaticallyUnderscoreAndCamelize = YES;
		
		asyncOperationQueue = [[NSOperationQueue alloc] init];
		[asyncOperationQueue setMaxConcurrentOperationCount:5];
	}
	return self;
}

- (id) initWithAppURL:(NSString *)url
{
	if ((self = [self init]))
	{		
		[self setAppURL:url];
	}
	return self;
}

- (void) setAppURL:(NSString *)str
{
	if (!str)
	{
		appURL = nil;
		return;
	}
	
	//get rid of trailing / if it's there
	if (str.length > 0 && [[str substringFromIndex:str.length-1] isEqualToString:@"/"])
		str = [str substringToIndex:str.length-1];
	
	//add http:// if not included already
	NSString *http = (str.length < 7 ? nil : [str substringToIndex:7]);
	if (![http isEqualToString:@"http://"] && ![http isEqualToString:@"https:/"])
	{
		str = [@"http://" stringByAppendingString:str];
	}
	
	appURL = str;
}




#pragma mark -
#pragma mark HTTP stuff

//purpose of this method is to factor printing out an error message (if NSRLog allows) and crash (if desired)

+ (void) crashWithError:(NSError *)error
{
#if NSRLog > 0
	NSLog(@"%@",error);
	NSLog(@" ");
#endif
	
#ifdef NSRCrashOnError
	[NSException raise:[NSString stringWithFormat:@"%@ error code %d",[error domain],[error code]] format:[error localizedDescription]];
#endif
}

//Do not override this method - it includes a check to see if there's no AppURL specified
- (NSString *) resultForRequestType:(NSString *)type requestBody:(NSString *)requestStr route:(NSString *)route sync:(NSError **)error orAsync:(NSRHTTPCompletionBlock)completionBlock
{
	//make sure the app URL is set
	if (!self.appURL)
	{
		NSError *err = [NSError errorWithDomain:@"NSRails" code:0 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No server root URL specified. Set your rails app's root with +[[NSRConfig defaultConfig] setAppURL:] somewhere in your app setup. (env=%@)", currentEnvironment] forKey:NSLocalizedDescriptionKey]];
		if (error)
			*error = err;
		if (completionBlock)
			completionBlock(nil, err);
		
		[NSRConfig crashWithError:err];
		
		return nil;
	}
	
	//If you want to override handling the connection, override this method
	NSString *result = [self makeRequestType:type requestBody:requestStr route:route sync:error orAsync:completionBlock];
	return result;
}

- (void) logRequestWithBody:(NSString *)requestStr httpVerb:(NSString *)httpVerb url:(NSString *)url
{
#if NSRLog > 0
	NSLog(@" ");
	NSLog(@"%@ to %@",httpVerb,url);
#if NSRLog > 1
	NSLog(@"OUT===> %@",requestStr);
#endif
#endif
}

- (void) logResponse:(NSString *)response statusCode:(int)code
{
#if NSRLog > 1
	NSLog(@"IN<=== Code %d; %@\n\n",code,((code < 0 || code >= 400) ? @"[see ERROR]" : response));
	NSLog(@" ");
#endif
}

//Overide THIS method if necessary (for SSL etc)
- (NSString *) makeRequestType:(NSString *)type requestBody:(NSString *)requestStr route:(NSString *)route sync:(NSError **)error orAsync:(NSRHTTPCompletionBlock)completionBlock
{	
	//helper method to get an NSURLRequest object based on above params
	NSURLRequest *request = [self HTTPRequestForRequestType:type requestBody:requestStr route:route];
	
	//log relevant stuff
	[self logRequestWithBody:requestStr httpVerb:type url:[[request URL] absoluteString]];
	
	//send request using HTTP!
	NSString *result = [self makeHTTPRequestWithRequest:request sync:error orAsync:completionBlock];
	return result;
}

- (NSString *) makeHTTPRequestWithRequest:(NSURLRequest *)request sync:(NSError **)error orAsync:(NSRHTTPCompletionBlock)completionBlock
{
	//ASYNC
	if (completionBlock)
	{
		[NSURLConnection sendAsynchronousRequest:request queue:asyncOperationQueue completionHandler:
		 ^(NSURLResponse *response, NSData *data, NSError *appleError) 
		 {
			 //if there's an error from the request there must have been an issue connecting to the server.
			 if (appleError)
			 {
				 [[self class] crashWithError:appleError];

				 completionBlock(nil,appleError);
			 }
			 else
			 {
				 NSInteger code = [(NSHTTPURLResponse *)response statusCode];
				 
				 NSString *rawResult = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
				 
#ifndef NSRCompileWithARC
				 [rawResult autorelease];
#endif
				 
				 //int casting done to suppress Mac OS precision loss warnings
				 [self logResponse:rawResult statusCode:(int)code];
				 
				 //see if there's an error from this response using this helper method
				 NSError *railsError = [self errorForResponse:rawResult statusCode:code];
				 
				 if (railsError)
					 completionBlock(nil, railsError);
				 else
					 completionBlock(rawResult, nil);
			 }
		 }];
	}
	//SYNC
	else
	{
		NSError *appleError = nil;
		NSURLResponse *response = nil;
		NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&appleError];
		
		//if there's an error here there must have been an issue connecting to the server.
		if (appleError)
		{
			[[self class] crashWithError:appleError];

			if (error)
				*error = appleError;
			
			return nil;
		}
		
		NSInteger code = [(NSHTTPURLResponse *)response statusCode];

		NSString *rawResult = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
		
#ifndef NSRCompileWithARC
		[rawResult autorelease];
#endif
		
		//int casting done to suppress Mac OS precision loss warnings
		[self logResponse:rawResult statusCode:(int)code];

		//see if there's an error from this response using this helper method
		NSError *railsError = [self errorForResponse:rawResult statusCode:[(NSHTTPURLResponse *)response statusCode]];
		if (railsError)
		{
			if (error)
				*error = railsError;
			
			return nil;
		}
		return rawResult;
	}
	return nil;
}


- (NSError *) errorForResponse:(NSString *)response statusCode:(NSInteger)statusCode
{
	BOOL err = (statusCode < 0 || statusCode >= 400);
	
	if (err)
	{
#ifdef NSRSuccinctErrorMessages
		//if error message is in HTML,
		if ([response rangeOfString:@"</html>"].location != NSNotFound)
		{
			NSArray *pres = [response componentsSeparatedByString:@"<pre>"];
			if (pres.count > 1)
			{
				//get the value between <pre> and </pre>
				response = [[[pres objectAtIndex:1] componentsSeparatedByString:@"</pre"] objectAtIndex:0];
				//some weird thing rails does, will send html tags &quot; for quotes
				response = [response stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
			}
		}
#endif
		
		NSMutableDictionary *inf = [NSMutableDictionary dictionaryWithObject:response
																	  forKey:NSLocalizedDescriptionKey];
		
		//422 means there was a validation error
		if (statusCode == 422)
		{
			NSDictionary *validationErrors = [response JSONValue];
			if (validationErrors)
				[inf setObject:validationErrors forKey:NSRValidationErrorsKey];
		}
		
		NSError *statusError = [NSError errorWithDomain:@"Rails"
												   code:statusCode
											   userInfo:inf];
		
		[NSRConfig crashWithError:statusError];
		
		return statusError;
	}
	
	return nil;
}
				
- (NSURLRequest *) HTTPRequestForRequestType:(NSString *)type requestBody:(NSString *)requestStr route:(NSString *)route
{
	NSString *url = [NSString stringWithFormat:@"%@/%@",appURL,route];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	
	[request setHTTPMethod:type];
	[request setHTTPShouldHandleCookies:NO];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	
	if (self.appUsername && self.appPassword)
	{
		//add auth header encoded in base64
		NSString *authStr = [NSString stringWithFormat:@"%@:%@", self.appUsername, self.appPassword];
		NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
		NSString *authHeader = [NSString stringWithFormat:@"Basic %@", [authData base64Encoding]];
		
		[request setValue:authHeader forHTTPHeaderField:@"Authorization"]; 
	}
	
	if (requestStr)
	{
		NSData *requestData = [NSData dataWithBytes:[requestStr UTF8String] length:[requestStr length]];
		
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[request setHTTPBody: requestData];
		
		[request setValue:[NSString stringWithFormat:@"%d", [requestData length]] forHTTPHeaderField:@"Content-Length"];
 	}
	
#ifndef NSRCompileWithARC
	[request autorelease];
#endif
	
	return request;
}

#pragma mark -
#pragma mark Contextual stuff

+ (NSRConfig *) overrideConfig
{
	//return the last config on the stack (last in first out)
	//if stack is nil or empty, this will be nil, signifying that there's no overriding context
	
	return [[overrideConfigStack lastObject] config];
}

- (void) use
{
	//this will signal the beginning of a config context block
	
	if (!overrideConfigStack)
		overrideConfigStack = [[NSMutableArray alloc] init];
	
	// make a new stack element for this config (explained at top of the file)
	NSRConfigStackElement *c = [NSRConfigStackElement elementForConfig:self];
	
	[overrideConfigStack addObject:c];
}

- (void) end
{
	//start at the end of the stack
	for (NSInteger i = overrideConfigStack.count-1; i >= 0; i--)
	{
		//see if any element matches this config
		NSRConfigStackElement *c = [overrideConfigStack objectAtIndex:i];
		if (c.config == self)
		{
			[overrideConfigStack removeObjectAtIndex:i];
			break;
		}
	}
}

- (void) useIn:(void (^)(void))block
{
	[self use];
	block();
	[self end];
}

@end
