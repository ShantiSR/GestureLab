#import "BWLoggingTextView.h"

@interface BWLoggingTextView () {
    NSMutableString *_contents;
    int _oldStandardOut;
    int _oldStandardError;

    int _standardOutPipe[2];

    NSTimeInterval _startTimestamp;
    NSMutableArray *_lines;

    CFSocketRef _socketRef;
}
@end // extension

enum { kReadSide, kWriteSide };  // The two side to every pipe()


@interface BWLogEntry : NSObject
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, copy) NSString *line;
+ (BWLogEntry *) entryWithLine: (NSString *) line;
@end // BWLogEntry


@implementation BWLoggingTextView

static void ReceiveMessage (CFSocketRef socket, CFSocketCallBackType type,
                            CFDataRef address, const void *data, void *info) {
    NSString *string = [[NSString alloc] initWithData: (__bridge NSData *) data
                                         encoding: NSUTF8StringEncoding];
    BWLoggingTextView *self = (__bridge BWLoggingTextView *) info;

    [self addLine: string];

} // ReceiveMessage


- (void) startMonitoringSocket: (int) fd {
    CFSocketContext context = { 0, (__bridge void *)(self), NULL, NULL, NULL };
    _socketRef = CFSocketCreateWithNative (kCFAllocatorDefault,
                                           fd,
                                           kCFSocketDataCallBack,
                                           ReceiveMessage,
                                           &context);
    if (_socketRef == NULL) {
        NSLog (@"couldn't make cfsocket");
        goto bailout;
    }
    
    CFRunLoopSourceRef rls = 
        CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socketRef, 0);

    if (rls == NULL) {
        NSLog (@"couldn't create run loop source");
        goto bailout;
    }
    
    CFRunLoopAddSource (CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease (rls);

bailout: 
    return;

} // startMonitoringSocket


- (void) hijackStandardOut {
    int result;
    result = pipe (_standardOutPipe);
    if (result == -1) {
        NSLog (@"could not make a pipe for standard out");
        return;
    }

    // save off the existing fd's for eventual reconnecting.
    _oldStandardOut = dup (fileno(stdout));
    _oldStandardError = dup (fileno(stderr));
    setbuf (stdout, NULL);  // Turn off buffering
    setbuf (stderr, NULL);  // Turn off buffering

    dup2 (_standardOutPipe[kWriteSide], fileno(stdout));
    dup2 (_standardOutPipe[kWriteSide], fileno(stderr));

    // Add the read side to the runloop.
    [self startMonitoringSocket: _standardOutPipe[kReadSide]];

} // hijackStandardOut


- (id) initWithFrame: (CGRect) frame {
    if ((self = [super initWithFrame: frame])) {
        [self hijackStandardOut];
    }
    
    return self;

} // initWithFrame


- (id) initWithCoder: (NSCoder *) decoder {
    if ((self = [super initWithCoder: decoder])) {
        [self hijackStandardOut];
    }
    
    return self;

} // initWithCoder


- (void) scrollToEnd {
    NSRange range = NSMakeRange (_contents.length, 0);
    [self scrollRangeToVisible: range];
} // scrollToEnd


- (void) addLine: (NSString *) line {
    if (_contents == nil) _contents = [NSMutableString string];
    if (_lines == nil) _lines = [NSMutableArray array];

    [_contents appendString: line];
    self.text = _contents;

    BWLogEntry *entry = [BWLogEntry entryWithLine: line];
    [_lines addObject: entry];

    [self scrollToEnd];

} // addLine


- (void) clear {
    [_contents setString: @""];
    self.text = _contents;

    [_lines removeAllObjects];
    _startTimestamp = [NSDate timeIntervalSinceReferenceDate];
} // clear


- (void) displayToTimestamp: (NSTimeInterval) timestamp {
    NSTimeInterval adjustedTimestamp = _startTimestamp + timestamp;

    [_contents setString: @""];

    for (BWLogEntry *line in _lines) {
        if (line.timestamp > adjustedTimestamp) break;
        [_contents appendString: line.line];
    }

    self.text = _contents;
    [self scrollToEnd];
    
} // displayToTimestamp


@end // BWLoggingTextView


@implementation BWLogEntry

- (id) initWithLine: (NSString *) line {
    if ((self = [super init])) {
        _timestamp = [NSDate timeIntervalSinceReferenceDate];
        _line = [line copy];
    }

    return self;

} // initWithLine


+ (BWLogEntry *) entryWithLine: (NSString *) line {
    return [[self alloc] initWithLine: line];
} // entryWithLine

@end // BWLogEntry