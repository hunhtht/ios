//
//  RouteModel.m
//  CycleStreets
//
//  Created by neil on 22/03/2011.
//  Copyright 2011 CycleStreets Ltd. All rights reserved.
//

#import "RouteManager.h"
#import "BUNetworkOperation.h"
#import "GlobalUtilities.h"
#import "CycleStreets.h"
#import "AppConstants.h"
#import "Files.h"
#import "RouteParser.h"
#import "HudManager.h"
#import "ValidationVO.h"
#import "BUNetworkOperation.h"
#import "SettingsManager.h"
#import "SavedRoutesManager.h"
#import "RouteVO.h"
#import <MapKit/MapKit.h>
#import "UserLocationManager.h"
#import "WayPointVO.h"
#import "ApplicationXMLParser.h"
#import "BUDataSourceManager.h"

static NSString *const LOCATIONSUBSCRIBERID=@"RouteManager";


@interface RouteManager()



@end

static NSString *useDom = @"1";


@implementation RouteManager
SYNTHESIZE_SINGLETON_FOR_CLASS(RouteManager);


//=========================================================== 
// - (id)init
//
//=========================================================== 
- (instancetype)init
{
    self = [super init];
    if (self) {
        self.routes = [[NSMutableDictionary alloc]init];
		self.activeRouteDir=OLDROUTEARCHIVEPATH;
		[self evalRouteArchiveState];
    }
    return self;
}




//
/***********************************************
 * @description		NOTIFICATIONS
 ***********************************************/
//

-(void)listNotificationInterests{
	
	BetterLog(@"");
	
	[notifications addObject:REQUESTDIDCOMPLETEFROMSERVER];
	[notifications addObject:DATAREQUESTFAILED];
	[notifications addObject:REMOTEFILEFAILED];
	
	[notifications addObject:GPSLOCATIONCOMPLETE];
	[notifications addObject:GPSLOCATIONUPDATE];
	[notifications addObject:GPSLOCATIONFAILED];
	
	
	[self addRequestID:CALCULATEROUTE];
	[self addRequestID:RETRIEVEROUTEBYID];
	[self addRequestID:UPDATEROUTE];
	
	[super listNotificationInterests];
	
}

-(void)didReceiveNotification:(NSNotification*)notification{
	
	[super didReceiveNotification:notification];
	NSDictionary	*dict=[notification userInfo];
	BUNetworkOperation		*response=[dict objectForKey:RESPONSE];
	
	NSString	*dataid=response.dataid;
	BetterLog(@"response.dataid=%@",response.dataid);
	
	if([self isRegisteredForRequest:dataid]){
		
		if([notification.name isEqualToString:REQUESTDIDCOMPLETEFROMSERVER]){
			
			if ([response.dataid isEqualToString:CALCULATEROUTE]) {
				
				[self loadRouteForEndPointsResponse:response.dataProvider];
				
			}else if ([response.dataid isEqualToString:RETRIEVEROUTEBYID]) {
				
				[self loadRouteForRouteIdResponse:response.dataProvider];
				
			}else if ([response.dataid isEqualToString:UPDATEROUTE]) {
				
				[self updateRouteResponse:response.dataProvider];
				
			}
			
		}
		
	}
	
	if([[UserLocationManager sharedInstance] hasSubscriber:LOCATIONSUBSCRIBERID ]){
		
		if([notification.name isEqualToString:GPSLOCATIONCOMPLETE]){
			[self locationDidComplete:notification];
		}
		
		if([notification.name isEqualToString:GPSLOCATIONFAILED]){
			[self locationDidFail:notification];
		}
		
	}
	
	
	
	if([notification.name isEqualToString:REMOTEFILEFAILED] || [notification.name isEqualToString:DATAREQUESTFAILED]){
		[[HudManager sharedInstance] removeHUD];
	}
	
	
}


//
/***********************************************
 * @description			LOCATION SUPPORT
 ***********************************************/
//

-(void)locationDidFail:(NSNotification*)notification{
	
	[[UserLocationManager sharedInstance] stopUpdatingLocationForSubscriber:LOCATIONSUBSCRIBERID];
	
	[self queryFailureMessage: @"Could not plan valid route for selected waypoints."];
	
}

-(void)locationDidComplete:(NSNotification*)notification{
	
	[[UserLocationManager sharedInstance] stopUpdatingLocationForSubscriber:LOCATIONSUBSCRIBERID];
	
	CLLocation *location=(CLLocation*)[notification object];
	
	MKMapItem *source=_mapRoutingRequest.source;
	MKMapItem *destination=_mapRoutingRequest.destination;
	
	CLLocationCoordinate2D fromcoordinate=source.placemark.coordinate;
	CLLocationCoordinate2D tocoordinate=destination.placemark.coordinate;
	
	if(fromcoordinate.latitude==0.0 && fromcoordinate.longitude==0.0){
		
		[self loadRouteForCoordinates:location.coordinate to:tocoordinate];
		
	}else if(tocoordinate.latitude==0.0 && tocoordinate.longitude==0.0){
		
		[self loadRouteForCoordinates:fromcoordinate to:location.coordinate];
		
	}else{
		[self loadRouteForCoordinates:fromcoordinate to:tocoordinate];
	}
		
		
	
	
}




//
/***********************************************
 * @description			NEW NETWORK METHODS
 ***********************************************/
//



-(void)loadRouteForEndPoints:(CLLocation*)fromlocation to:(CLLocation*)tolocation{
    
	[self loadRouteForCoordinates:fromlocation.coordinate to:tolocation.coordinate];
    
}


-(void)loadRouteForCoordinates:(CLLocationCoordinate2D)fromcoordinate to:(CLLocationCoordinate2D)tocoordinate{
	
	
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
    SettingsVO *settingsdp = [SettingsManager sharedInstance].dataProvider;
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
									 
									 [NSString stringWithFormat:@"%@,%@|%@,%@",BOX_FLOAT(fromcoordinate.longitude),BOX_FLOAT(fromcoordinate.latitude),BOX_FLOAT(tocoordinate.longitude),BOX_FLOAT(tocoordinate.latitude)],@"itinerarypoints",
                                     useDom,@"useDom",
                                     settingsdp.plan,@"plan",
                                     [settingsdp returnKilometerSpeedValue],@"speed",
                                     cycleStreets.files.clientid,@"clientid",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=CALCULATEROUTE;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
	
	request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self loadRouteForEndPointsResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:@"Obtaining route from CycleStreets.net" andMessage:nil];
	
}

-(void)loadRouteForWaypoints:(NSMutableArray*)waypoints{
	
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
    SettingsVO *settingsdp = [SettingsManager sharedInstance].dataProvider;
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
									 
									 [self convertWaypointArrayforRequest:waypoints],@"itinerarypoints",
                                     useDom,@"useDom",
                                     settingsdp.plan,@"plan",
                                     [settingsdp returnKilometerSpeedValue],@"speed",
                                     cycleStreets.files.clientid,@"clientid",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=CALCULATEROUTE;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
	request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self loadRouteForEndPointsResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
    
    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:@"Obtaining route from CycleStreets.net" andMessage:nil];
	
	
	
}

//
/***********************************************
 * @description			converts array to lat,long|lat,long... formatted string
 ***********************************************/
//
-(NSString*)convertWaypointArrayforRequest:(NSMutableArray*)waypoints{
	
	NSMutableArray *cooordarray=[NSMutableArray array];
	
	for(int i=0;i<waypoints.count;i++){
		
		WayPointVO *waypoint=waypoints[i];
		
		[cooordarray addObject:waypoint.coordinateString];
		
	}
	
	return [cooordarray componentsJoinedByString:@"|"];
	
}







-(void)loadRouteForEndPointsResponse:(BUNetworkOperation*)response{
	
	BetterLog(@"");
    
    
    switch(response.validationStatus){
        
        case ValidationCalculateRouteSuccess:
		{  
			RouteVO *newroute = response.dataProvider;
            
            [[SavedRoutesManager sharedInstance] addRoute:newroute toDataProvider:SAVEDROUTE_RECENTS];
                
            [self warnOnFirstRoute];
            [self selectRoute:newroute];
			[self saveRoute:_selectedRoute];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:CALCULATEROUTERESPONSE object:nil];
            
            [[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, added path to map" andMessage:nil];
        }
        break;
            
            
        case ValidationCalculateRouteFailed:
            
            [self queryFailureMessage:@"Routing error: Could not plan valid route for selected waypoints."];
            
        break;
			
		
		case ValidationCalculateRouteFailedOffNetwork:
            
            [self queryFailureMessage:@"Routing error: not all waypoints are on known cycle routes."];
            
		break;
			
		default:
			break;
        
        
    }
    

    
}


-(void)loadRouteForRouteId:(NSString*)routeid{
    
	
    SettingsVO *settingsdp = [SettingsManager sharedInstance].dataProvider;
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
                                     useDom,@"useDom",
                                     settingsdp.plan,@"plan",
                                     routeid,@"itinerary",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=RETRIEVEROUTEBYID;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
    request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self loadRouteForRouteIdResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
	// format routeid to decimal style ie xx,xxx,xxx
	NSNumberFormatter *currencyformatter=[[NSNumberFormatter alloc]init];
	[currencyformatter setNumberStyle:NSNumberFormatterDecimalStyle];
	NSString *result=[currencyformatter stringFromNumber:[NSNumber numberWithInt:[routeid intValue]]];

    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:[NSString stringWithFormat:@"Loading route %@ on CycleStreets",result] andMessage:nil];
}

-(void)loadRouteForRouteId:(NSString*)routeid withPlan:(NSString*)plan{
	
	
	BOOL found=[[SavedRoutesManager sharedInstance] findRouteWithId:routeid andPlan:plan];
	
	if(found==YES){
		
		RouteVO *route=[self loadRouteForFileID:[NSString stringWithFormat:@"%@_%@",routeid,plan]];
		
		[self selectRoute:route];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:NEWROUTEBYIDRESPONSE object:nil];
		
		[[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, this route is now selected." andMessage:nil];
		
	}else{
		
		NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
										 useDom,@"useDom",
										 plan,@"plan",
										 routeid,@"itinerary",
										 nil];
		
		BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
		request.dataid=RETRIEVEROUTEBYID;
		request.requestid=ZERO;
		request.parameters=parameters;
		request.source=DataSourceRequestCacheTypeUseNetwork;
		
		request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
			
			[self loadRouteForRouteIdResponse:operation];
			
		};
		
		[[BUDataSourceManager sharedInstance] processDataRequest:request];
		
		[[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:[NSString stringWithFormat:@"Searching for %@ route %@ on CycleStreets",[plan capitalizedString], routeid] andMessage:nil];
		
	}
    
	
    
}


-(void)loadRouteForRouteIdResponse:(BUNetworkOperation*)response{
    
	BetterLog(@"");
    
    switch(response.validationStatus){
            
        case ValidationCalculateRouteSuccess:
        {    
            RouteVO *newroute=response.dataProvider;
            
            [[SavedRoutesManager sharedInstance] addRoute:newroute toDataProvider:SAVEDROUTE_RECENTS];
            
            [self selectRoute:newroute];
			[self saveRoute:_selectedRoute ];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:NEWROUTEBYIDRESPONSE object:nil];
            
            [[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, this route is now selected." andMessage:nil];
		}   
            break;
            
            
        case ValidationCalculateRouteFailed:
            
            [self queryFailureMessage:@"Unable to find a route with this number."];
            
			break;
			
		default:
			break;
            
            
    }
    
    
}


#pragma mark Route Updating
//
/***********************************************
 * @description			ROUTE UPDATING FOR LEGACY ROUTES
 ***********************************************/
//

-(void)updateRoute:(RouteVO*)route{
    
	BetterLog(@"");
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
                                     useDom,@"useDom",
                                     route.plan,@"plan",
                                     route.routeid,@"itinerary",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=UPDATEROUTE;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
    request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self updateRouteResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
	// format routeid to decimal style ie xx,xxx,xxx
	NSNumberFormatter *currencyformatter=[[NSNumberFormatter alloc]init];
	[currencyformatter setNumberStyle:NSNumberFormatterDecimalStyle];
	NSString *result=[currencyformatter stringFromNumber:[NSNumber numberWithInt:[route.routeid intValue]]];
	
    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:[NSString stringWithFormat:@"Updating route %@",result] andMessage:nil];
}


-(void)updateRouteResponse:(BUNetworkOperation*)response{
    
	BetterLog(@"");
    
    switch(response.validationStatus){
            
        case ValidationCalculateRouteSuccess:
        {
           RouteVO *newroute=response.dataProvider;
            
			[[SavedRoutesManager sharedInstance] updateRouteWithRoute:newroute];
            
            
            [[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:nil andMessage:nil];
		}
            break;
            
            
        case ValidationCalculateRouteFailed:
            
            [self queryFailureMessage:@"Unable to find a route with this number."];
            
		break;
			
		default:
			break;
            
            
    }
    
    
}


//
/***********************************************
 * @description			OS6 Routing request support
 ***********************************************/
//

-(void)loadRouteForRouting:(MKDirectionsRequest*)routingrequest{
	
	MKMapItem *source=routingrequest.source;
	MKMapItem *destination=routingrequest.destination;
	
	CLLocationCoordinate2D fromlocation=source.placemark.coordinate;
	CLLocationCoordinate2D tolocation=destination.placemark.coordinate;
	
	// if a user has currentLocation as one of their pins
	// MKDirectionsRequest will return 0,0 for it
	// so we have to do another lookup in app to correct this!
	if(fromlocation.latitude==0.0 || tolocation.latitude==0.0){ 
		
		self.mapRoutingRequest=routingrequest;
		
		[[UserLocationManager sharedInstance] startUpdatingLocationForSubscriber:LOCATIONSUBSCRIBERID];
		
		
	}else{
		
		[self loadRouteForCoordinates:fromlocation to:tolocation];
		
	}
	
	
}



//
/***********************************************
 * @description			Old Route>New Route conversion evaluation
 ***********************************************/
//

-(void)evalRouteArchiveState{
	
	
	// do we have a old route folder
	NSFileManager* fileManager = [NSFileManager defaultManager];
	
	[self createRoutesDir];
	
	
	BOOL isDirectory;
	BOOL doesDirExist=[fileManager fileExistsAtPath:[self oldroutesDirectory] isDirectory:&isDirectory];
	
					   
	if(doesDirExist==YES && isDirectory==YES){
		
		self.legacyRoutes=[NSMutableArray array];
		
		NSError *error=nil;
		NSURL *url = [[NSURL alloc] initFileURLWithPath:[self oldroutesDirectory] isDirectory:YES ];
		NSArray *properties = [NSArray arrayWithObjects: NSURLLocalizedNameKey, nil];
		
		NSArray *oldroutes = [fileManager
						  contentsOfDirectoryAtURL:url
						  includingPropertiesForKeys:properties
						  options:(NSDirectoryEnumerationSkipsPackageDescendants |
								   NSDirectoryEnumerationSkipsHiddenFiles)
						  error:&error];
		
		
		if(error==nil && [oldroutes count]>0){
			
			for(NSURL *filename in oldroutes){
				
				NSData *routedata=[[NSData alloc ] initWithContentsOfURL:filename];
				
				RouteVO *newroute=(RouteVO*)[[ApplicationXMLParser sharedInstance] parseXML:routedata forType:CALCULATEROUTE];
				
				[_legacyRoutes addObject:newroute];
				
				[self saveRoute:newroute];
				
				
			}
			
		}
		
	}else {
		
		BetterLog(@"[INFO] OldRoutes dir was not there");
		
	}
	
	self.activeRouteDir=ROUTEARCHIVEPATH;
	
	
}



-(void)legacyRouteCleanup{
	
	self.legacyRoutes=nil;
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSError *error=nil;
	
	[fileManager removeItemAtPath:[self oldroutesDirectory] error:&error];
	
}



- (void) queryFailureMessage:(NSString *)message {
	[[HudManager sharedInstance] showHudWithType:HUDWindowTypeError withTitle:message andMessage:nil];
}


//
/***********************************************
 * @description			RESEPONSE EVENTS
 ***********************************************/
//

- (void) selectRoute:(RouteVO *)route {
	
	BetterLog(@"");
	
	self.selectedRoute=route;
	
	[[SavedRoutesManager sharedInstance] selectRoute:route];
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	[cycleStreets.files setMiscValue:route.fileid forKey:@"selectedroute"];
	
	BetterLog(@"");
	
	[[NSNotificationCenter defaultCenter] postNotificationName:CSROUTESELECTED object:[route routeid]];
	
}


- (void) clearSelectedRoute{
	
	if(_selectedRoute!=nil){
		
		self.selectedRoute=nil;
		
		CycleStreets *cycleStreets = [CycleStreets sharedInstance];
		[cycleStreets.files setMiscValue:EMPTYSTRING forKey:@"selectedroute"];
	}
	
	
}


-(BOOL)hasSelectedRoute{
	return _selectedRoute!=nil;
}


-(BOOL)routeIsSelectedRoute:(RouteVO*)route{
	
	if(_selectedRoute!=nil){
	
		return [route.fileid isEqualToString:_selectedRoute.fileid];
		
	}else{
		return NO;
	}
	
}



- (void)warnOnFirstRoute {
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	NSMutableDictionary *misc = [NSMutableDictionary dictionaryWithDictionary:[cycleStreets.files misc]];
	NSString *experienceLevel = [misc objectForKey:@"experienced"];
	
	if (experienceLevel == nil) {
		[misc setObject:@"1" forKey:@"experienced"];
		[cycleStreets.files setMisc:misc];
		
		UIAlertView *firstAlert = [[UIAlertView alloc] initWithTitle:@"Warning"
													 message:@"Route quality cannot be guaranteed. Please proceed at your own risk. Do not use a mobile while cycling."
													delegate:self
										   cancelButtonTitle:@"OK"
										   otherButtonTitles:nil];
		[firstAlert show];		
	} else if ([experienceLevel isEqualToString:@"1"]) {
		[misc setObject:@"2" forKey:@"experienced"];
		[cycleStreets.files setMisc:misc];
		
		UIAlertView *optionsAlert = [[UIAlertView alloc] initWithTitle:@"Routing modes"
													   message:@"You can change between fastest / quietest / balanced routing type using the route type button above."
													  delegate:self
											 cancelButtonTitle:@"OK"
											 otherButtonTitles:nil];
		[optionsAlert show];
	}	
	 
}





//
/***********************************************
 * @description			Pre Selects route as SR
 ***********************************************/
//
-(void)selectRouteWithIdentifier:(NSString*)identifier{
	
	if (identifier!=nil) {
		RouteVO *route = [_routes objectForKey:identifier];
		if(route!=nil){
			[self selectRoute:route];
		}
	}
	
}

//
/***********************************************
 * @description			loads route from disk and stores
 ***********************************************/
//
-(void)loadRouteWithIdentifier:(NSString*)identifier{
	
	RouteVO *route=nil;
	
	if (identifier!=nil) {
		route = [self loadRouteForFileID:identifier];
	}
	if(route!=nil){
		[_routes setObject:route forKey:identifier];
	}
	
}

//


// loads the currently saved selectedRoute by identifier
-(BOOL)loadSavedSelectedRoute{
	
	BetterLog(@"");
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	NSString *selectedroutefileid = [cycleStreets.files miscValueForKey:@"selectedroute"];
	
	
	if(selectedroutefileid!=nil){
		RouteVO *route=[self loadRouteForFileID:selectedroutefileid];
		
		if(route!=nil){
			[self selectRoute:route];
			return YES;
		}else{
			[[NSNotificationCenter defaultCenter] postNotificationName:CSLASTLOCATIONLOAD object:nil];
			return NO;
		}
		
	}
	
	return NO;
	
}



-(void)removeRoute:(RouteVO*)route{
	
	[_routes removeObjectForKey:route.fileid];
	[self removeRouteFile:route];
	
}


//
/***********************************************
 * @description			File I/O
 ***********************************************/
//


-(RouteVO*)loadRouteForFileID:(NSString*)fileid{
	
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", fileid]];
	
	BetterLog(@"routeFile=%@",routeFile);
	
	NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile:routeFile];
	
	if(data!=nil){
		NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
		RouteVO *route = [unarchiver decodeObjectForKey:kROUTEARCHIVEKEY];
		[unarchiver finishDecoding];
		return route;
	}
	
	return nil;
	
}


- (void)saveRoute:(RouteVO *)route   {
	
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", route.fileid]];
	
	//BetterLog(@"routeFile=%@",routeFile);
	
	NSMutableData *data = [[NSMutableData alloc] init];
	NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	[archiver encodeObject:route forKey:kROUTEARCHIVEKEY];
	[archiver finishEncoding];
	[data writeToFile:routeFile atomically:YES];
	
	
}


- (void)removeRouteFile:(RouteVO*)route{
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", route.fileid]];
	
	BOOL fileexists = [fileManager fileExistsAtPath:routeFile];
	
	if(fileexists==YES){
		
		NSError *error=nil;
		[fileManager removeItemAtPath:routeFile error:&error];
	}
	
}


-(BOOL)createRoutesDir{
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSArray* paths=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString* docsdir=[paths objectAtIndex:0];
	NSString *ipath=[docsdir stringByAppendingPathComponent:ROUTEARCHIVEPATH];
	
	BOOL isDir=YES;
	
	if([fileManager fileExistsAtPath:ipath isDirectory:&isDir]){
		return YES;
	}else {
		
		if([fileManager createDirectoryAtPath:ipath withIntermediateDirectories:NO attributes:nil error:nil ]){
			return YES;
		}else{
			return NO;
		}
	}
	
	
}


//
/***********************************************
 * @description			LEGACY ROUTE ID METHODS
 ***********************************************/
//

// legacy conversion call only
-(RouteVO*)legacyLoadRoute:(NSString*)routeid{
	
	NSString *routeFile = [[self oldroutesDirectory] stringByAppendingPathComponent:routeid];
	
	//BetterLog(@"routeFile=%@",routeFile);
	
	NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile:routeFile];
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	RouteVO *route = [unarchiver decodeObjectForKey:kROUTEARCHIVEKEY];
	[unarchiver finishDecoding];
	
	return route;
	
	
}

- (void)legacyRemoveRouteFile:(NSString*)routeid{
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", routeid]];
	
	BOOL fileexists = [fileManager fileExistsAtPath:routeFile];
	
	if(fileexists==YES){
		
		NSError *error=nil;
		[fileManager removeItemAtPath:routeFile error:&error];
	}
	
}



//
/***********************************************
END
 ***********************************************/
//


- (NSString *) oldroutesDirectory {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [[paths objectAtIndex:0] copy];
	return [documentsDirectory stringByAppendingPathComponent:OLDROUTEARCHIVEPATH];
}

- (NSString *) routesDirectory {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [[paths objectAtIndex:0] copy];
	return [documentsDirectory stringByAppendingPathComponent:ROUTEARCHIVEPATH];
}



@end
