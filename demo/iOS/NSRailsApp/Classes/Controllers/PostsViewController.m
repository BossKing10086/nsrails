//
//  PostsViewController.m
//  NSRailsApp
//
//  Created by Dan Hassin on 2/20/12.
//  Copyright (c) 2012 InContext LLC. All rights reserved.
//

#import "PostsViewController.h"
#import "InputViewController.h"
#import "AppDelegate.h"
#import "ResponsesViewController.h"

#import "Post.h"

@implementation PostsViewController


/*
 =================================================
	RELEVANT NSRAILS STUFF
 =================================================
 */

- (void) refresh
{
	NSError *error;
	//when the refresh button is hit, get latest array of posts
	NSArray *allPosts = [Post remoteAll:&error];
	
	if (allPosts)
	{
		//set it to our ivar
		posts = [NSMutableArray arrayWithArray:allPosts];
		
		[self.tableView reloadData];		
	}
	else
	{
		[(AppDelegate *)[UIApplication sharedApplication].delegate alertForError:error];
	}
}

- (void) addPost
{
	//when the + button is hit, display an InputViewController (this is the shared input view for both posts and responses)
	//it has an init method that accepts a completion block - this block of code will be executed when the user hits "save"
	
	InputViewController *newPostVC = [[InputViewController alloc] initWithCompletionHandler:
										  ^BOOL (NSString *author, NSString *content) 
										  {
											  NSError *error;
											  
											  Post *newPost = [[Post alloc] init];
											  newPost.author = author;
											  newPost.content = content;
											  											  
											  if (![newPost remoteCreate:&error])
											  {
												  [(AppDelegate *)[UIApplication sharedApplication].delegate alertForError:error];
												  
												  //don't dismiss the input VC
												  return NO;
											  }
											  											  
											  [posts insertObject:newPost atIndex:0];
											  [self.tableView reloadData];
											  
											  return YES;											  
										  }];
	
	newPostVC.header = @"Post something to NSRails.com!";
	newPostVC.messagePlaceholder = @"A comment about NSRails, a philosophical inquiry, or simply a \"Hello world\"!";
	
	[self presentModalViewController:newPostVC animated:YES];
}

- (void) deletePostAtIndexPath:(NSIndexPath *)indexPath
{
	//here, on the delete, we're calling remoteDestroy to destroy our object remotely. remember to remove it from our local array, too.
	
	NSError *error;
	
	Post *post = [posts objectAtIndex:indexPath.row];
	if ([post remoteDestroy:&error])
	{
		[posts removeObject:post];
		
		[self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	}
	else
	{
		[(AppDelegate *)[UIApplication sharedApplication].delegate alertForError:error];
	}
}

/*
 =================================================
 UI + TABLE STUFF
 =================================================
 */

- (void)viewDidLoad
{
	[self refresh];
	
	self.title = @"Posts";
	
	//add refresh button
	UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
	self.navigationItem.leftBarButtonItem = refresh;
	
	//add the + button
	UIBarButtonItem *new = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPost)];
	self.navigationItem.rightBarButtonItem = new;
	
    [super viewDidLoad];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return 60;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return posts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) 
	{
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

	Post *post = [posts objectAtIndex:indexPath.row];
	cell.textLabel.text = post.content;
	cell.detailTextLabel.text = post.author;
	
	return cell;
}

- (void) tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[self deletePostAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	Post *post = [posts objectAtIndex:indexPath.row];

	ResponsesViewController *rvc = [[ResponsesViewController alloc] initWithStyle:UITableViewStyleGrouped];
	rvc.post = post;
	[self.navigationController pushViewController:rvc animated:YES];
}

@end
