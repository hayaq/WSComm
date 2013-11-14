//
//  ViewController.m
//  WSComm
//
//  Created by hayashi on 11/13/13.
//  Copyright (c) 2013 Qoncept. All rights reserved.
//

#import "ViewController.h"
#import "WebSocketServer.h"

@interface ViewController () <WebSocketServerDelegate>{
	IBOutlet UIWebView *_webView;
	IBOutlet UILabel *_msgInfo;
	WebSocketServer *_server;
	int _counter;
}

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	_server = [[WebSocketServer alloc] init];
	_server.delegate = self;
	[_server startWithPort:8000];
	NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"client" ofType:@"html"];
	NSString *htmlString = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
	[_webView loadHTMLString:htmlString baseURL:nil];
}

-(void)webSocketServer:(WebSocketServer *)server didReceiveMessage:(NSString *)msg{
	[_msgInfo performSelectorOnMainThread:@selector(setText:) withObject:msg waitUntilDone:NO];
	[server sendMessage:[NSString stringWithFormat:@"Message from VC %d",_counter++]];
}

@end
