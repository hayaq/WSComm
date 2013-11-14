#import "WebSocketServer.h"
#import "NSData+Base64.h"
#import <unistd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <CommonCrypto/CommonDigest.h>

enum WebSocketServerState{
	WSSStopped,
	WSSStarted,
	WSSWaiting,
	WSSAccepted,
	WSSConnecting
};

@implementation WebSocketServer{
	int  _state;
	int  _sock;
	int  _port;
	int  _csock;
	int  _quit;
	NSMutableString *_buffer;
	NSMutableDictionary *_header;
}

-(void)startWithPort:(int)port{
	if( _state != WSSStopped ){ return; }
	_port = port;
	[self performSelectorInBackground:@selector(runServer) withObject:nil];
}

-(void)dealloc{
	if( _sock ){
		close(_sock);
		_sock = 0;
	}
}

-(void)runServer{
	@autoreleasepool{
		do{
			if( ![self listen] ){ break; }
			int quit = 0;
			while( _sock && quit == 0 ){
				int csock = [self accept];
				if( csock <= 0 ){ break; }
				uint8_t buff[256];
				buff[255] = 0;
				while(1){
					int size = (int)recv(csock,buff,255,0);
					if( size <= 0 ){
						quit = 1;
						break;
						continue;
					}
					if( ![self procData:buff length:size] ){
						quit = 1;
						break;
					}
				}
			}
			@synchronized(self){
				if( _csock ){
					close(_csock);
					_csock = 0;
				}
				if( _sock ){
					close(_sock);
					_sock = 0;
				}
			}
		}while(0);
		_state = WSSStopped;
	}
}

-(BOOL)procData:(uint8_t*)data length:(int)length{
	if( _state == WSSAccepted ){
		if( ![self parseHeader:[NSString stringWithUTF8String:(char*)data]] ){
			return NO;
		}
		if( _header ){
			[self sendResponse];
			_state = WSSConnecting;
		}
	}else if( _state == WSSConnecting ){
		NSString *msg = [self parsePayload:data length:length];
		[_delegate webSocketServer:self didReceiveMessage:msg];
	}else{
		return NO;
	}
	return YES;
}

-(BOOL)listen{
	_sock = socket(AF_INET, SOCK_STREAM, 0);
	struct sockaddr_in addr;
	int on = 1;
	setsockopt(_sock, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on) );
	addr.sin_family = AF_INET;
	addr.sin_port = htons(_port);
	addr.sin_addr.s_addr = INADDR_ANY;
	if( bind(_sock, (struct sockaddr *)&addr, sizeof(addr))!=0 ){
		NSLog(@"Failed to bind port (%d)\n",_port);
		return NO;
	}
	if( listen(_sock,1) != 0 ){
		NSLog(@"Failed to listen port (%d)\n",_port);
		return NO;
	}
	NSLog(@"Start server with port (%d)\n",_port);
	return YES;
}

-(int)accept{
	_state = WSSWaiting;
	_header = nil;
	_buffer = [NSMutableString string];
	struct sockaddr_in client;
	socklen_t len = sizeof(client);
	int csock = 0;
	if( (csock=accept(_sock, (struct sockaddr*)&client,(socklen_t*)&len))<=0 ){
		NSLog(@"Failed to accept client\n");
		return 0;
	}
	NSLog(@"Client accepted!\n");
	_csock = csock;
	_state = WSSAccepted;
	return csock;
}

-(NSString*)parsePayload:(uint8_t*)data length:(int)length{
	int mlen = data[1]&0x7f;
	uint8_t mask[4];
	for(int i=0;i<4;i++){
		mask[i] = data[2+i];
	}
	int mi = 0;
	for(int i=0;i<mlen;i++){
		data[6+i] = data[6+i]^mask[mi];
		mi = (mi+1)%4;
	}
	data[length] = 0;
	if( data[0]&0x80 ){
		return [NSString stringWithUTF8String:(char*)data+6];
	}
	return nil;
}

-(BOOL)parseHeader:(NSString*)headerStr{
	if( [_buffer length] == 0 ){
		[_buffer appendString:headerStr];
		if( ![_buffer hasPrefix:@"GET"] ){
			return NO;
		}
	}else{
		[_buffer appendString:headerStr];
	}
	NSRange range = [_buffer rangeOfString:@"\r\n\r\n"];
	if( range.location == NSNotFound ){
		if( [_buffer length] > 1024 ){ return NO; }
		return YES;
	}
	
	NSRegularExpression *regexp = [NSRegularExpression regularExpressionWithPattern:@"(\\S+):\\s*(\\S+)"
																			options:0 error:nil];
	NSArray *matches = [regexp matchesInString:_buffer options:0 range:NSMakeRange(0,range.location)];
	if( ![matches count] ){ return NO; }
	
	_header = [NSMutableDictionary dictionary];
	for( NSTextCheckingResult *m in matches ){
		_header[[_buffer substringWithRange:[m rangeAtIndex:1]]] = [_buffer substringWithRange:[m rangeAtIndex:2]];
	}
	return YES;
}

-(void)sendResponse{
	NSString *key = [NSString stringWithFormat:@"%@258EAFA5-E914-47DA-95CA-C5AB0DC85B11",_header[@"Sec-WebSocket-Key"]];
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	NSData *keyBytes = [key dataUsingEncoding:NSUTF8StringEncoding];
	CC_SHA1([keyBytes bytes], (CC_LONG)[keyBytes length], digest);
	key = [[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH] base64EncodedString];
	_buffer = [NSMutableString string];
	[_buffer appendString:@"HTTP/1.1 101 Switching Protocols\r\n"];
	[_buffer appendString:@"Upgrade: websocket\r\n"];
	[_buffer appendString:@"Connection: Upgrade\r\n"];
	[_buffer appendFormat:@"Sec-WebSocket-Accept: %@\r\n",key];
	[_buffer appendString:@"\r\n"];
	send(_csock, [_buffer UTF8String], [_buffer length], 0);
}

-(void)sendMessage:(NSString*)message{
	int msglen = 0x7F&([message length]);
	int length = msglen+2;
	uint8_t *bytes = (uint8_t*)alloca(length);
	memset(bytes, 0, length+1);
	bytes[0] = 0x81;
	bytes[1] = msglen;
	const char *msgbytes = [message UTF8String];
	for(int i=0;i<msglen;i++){
		bytes[2+i] = msgbytes[i];
	}
	send(_csock, bytes, length, 0);
}

@end
