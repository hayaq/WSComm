//
//  WebSocketServer.h
//  WSComm
//
//  Created by hayashi on 11/14/13.
//  Copyright (c) 2013 Qoncept. All rights reserved.
//

#import <Foundation/Foundation.h>

@class WebSocketServer;

@protocol WebSocketServerDelegate <NSObject>
-(void)webSocketServer:(WebSocketServer*)server didReceiveMessage:(NSString*)msg;
@end

@interface WebSocketServer : NSObject
-(void)startWithPort:(int)port;
-(void)sendMessage:(NSString*)message;
@property (weak) id<WebSocketServerDelegate> delegate;
@end

