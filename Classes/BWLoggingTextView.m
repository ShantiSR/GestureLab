#import "BWLoggingTextView.h"

#import <QuartzCore/QuartzCore.h>  // For layer styles

static const BOOL kShouldHijack = YES;


// TODO(markd) : add unhijack, at least before blog posting.

@interface BWLoggingTextView () {
    NSMutableString *_contents;
    int _oldStandardOut;
    int _oldStandardError;

    int _standardOutPipe[2];
    int _standardErrorPipe[2];

    NSTimeInterval _startTimestamp;
    NSMutableArray *_lines;

    CFSocketRef _socketRef;
}
@end // extension

enum { kReadSide, kWriteSide };  // The two side to every pipe()

static NSString * const kTimestampFormat = @"%.2f: ";


@interface BWLogEntry : NSObject
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, copy) NSString *line;
+ (BWLogEntry *) entryWithLine: (NSString *) line;
@end // BWLogEntry


@implementation BWLoggingTextView

static void ReceiveMessage (CFSocketRef socket, CFSocketCallBackType type,
                            CFDataRef address, const void *cfdata, void *info) {
    NSData *data = (__bridge NSData *) cfdata;

    NSString *string = [[NSString alloc] initWithData: data
                                         encoding: NSUTF8StringEncoding];
    BWLoggingTextView *self = (__bridge BWLoggingTextView *) info;

    [self addLine: string];

    // Now forward on to its original destination.
    if (CFSocketGetNative(socket) == self->_standardOutPipe[kReadSide]) {
        write (self->_oldStandardOut, data.bytes, data.length);
    } else if (CFSocketGetNative(socket) == self->_standardErrorPipe[kReadSide]) {
        write (self->_oldStandardError, data.bytes, data.length);
    }

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


- (void) hijackOutStreams {
    int result;

    result = pipe (_standardOutPipe);
    if (result == -1) {
        assert (!"could not make a pipe for standard out");
        return;
    }

    result = pipe (_standardErrorPipe);
    if (result == -1) {
        assert (!"could not make a pipe for standard error");
        return;
    }

    // save off the existing fd's for eventual reconnecting.
    _oldStandardOut = dup (fileno(stdout));
    _oldStandardError = dup (fileno(stderr));

    setbuf (stdout, NULL);  // Turn off buffering
    setbuf (stderr, NULL);  // Turn off buffering

    dup2 (_standardOutPipe[kWriteSide], fileno(stdout));
    dup2 (_standardErrorPipe[kWriteSide], fileno(stderr));

    // Add the read side to the runloop.
    [self startMonitoringSocket: _standardOutPipe[kReadSide]];
    [self startMonitoringSocket: _standardErrorPipe[kReadSide]];

} // hijackOutStreams


- (void) commonInit {
    if (kShouldHijack) [self hijackOutStreams];

    _contents = [NSMutableString string];
    _lines = [NSMutableArray array];

    self.layer.borderWidth = 1.0f;
    self.layer.borderColor = [UIColor blackColor].CGColor;

} // commonInit


- (id) initWithFrame: (CGRect) frame {
    if ((self = [super initWithFrame: frame])) {
        [self commonInit];
    }
    
    return self;

} // initWithFrame


- (id) initWithCoder: (NSCoder *) decoder {
    if ((self = [super initWithCoder: decoder])) {
        [self commonInit];
    }
    
    return self;

} // initWithCoder


- (void) scrollToEnd {
    NSRange range = NSMakeRange (_contents.length, 0);
    [self scrollRangeToVisible: range];
} // scrollToEnd


- (void) addLine: (NSString *) line  includeTimestamp: (BOOL) stampy {
    BWLogEntry *entry = [BWLogEntry entryWithLine: line];
    [_lines addObject: entry];

    if (stampy) {
        NSTimeInterval now = entry.timestamp - _startTimestamp;
        [_contents appendFormat: kTimestampFormat, now];
    }
    [_contents appendString: line];
    self.text = _contents;

    [self scrollToEnd];

} // addLine


- (void) addLine: (NSString *) line {
    [self addLine: line  includeTimestamp: YES];
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

    for (BWLogEntry *entry in _lines) {
        if (entry.timestamp > adjustedTimestamp) break;

        NSTimeInterval now = entry.timestamp - _startTimestamp;
        [_contents appendFormat: kTimestampFormat, now];

        [_contents appendString: entry.line];
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
