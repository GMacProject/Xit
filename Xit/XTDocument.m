//
//  Xit.m
//  Xit
//
//  Created by glaullon on 7/15/11.
//

#import "XTDocument.h"
#import "XTHistoryView.h"
#import "XTRepository.h"
#import "XTStageViewController.h"
#import "XTFileViewController.h"
#import "XTStatusView.h"

@implementation XTDocument

- (id)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
    self = [super initWithContentsOfURL:absoluteURL ofType:typeName error:outError];
    if (self) {
        repoURL = absoluteURL;
        repo = [[XTRepository alloc] initWithURL:repoURL];
        [repo addObserver:self forKeyPath:@"activeTasks" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (id)initForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError **)outError {
    return [self initWithContentsOfURL:absoluteDocumentURL ofType:typeName error:outError];
}

- (NSString *)windowNibName {
    return @"XTDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController {
    [super windowControllerDidLoadNib:aController];

    [self loadViewController:historyView onTab:0];
    [self loadViewController:stageView onTab:1];
    [self loadViewController:fileListView onTab:2];

    [historyView setRepo:repo];
    [stageView setRepo:repo];
    [fileListView setRepo:repo];
    [statusView setRepo:repo];

    [repo start];
}

- (void)loadViewController:(NSViewController *)viewController onTab:(NSInteger)tabId {
    [viewController loadView];
    NSTabViewItem *tabView = [tabs tabViewItemAtIndex:tabId];
    [[viewController view] setFrame:NSMakeRect(0, 0, [[viewController view] frame].size.width, [[viewController view] frame].size.height)];
    [tabView setView:[viewController view]];
    NSLog(@"viewController:%@ view:%@", viewController, [viewController view]);
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
    NSURL *gitURL = [absoluteURL URLByAppendingPathComponent:@".git"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:[gitURL path]])
        return YES;

    if (outError != NULL) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"The folder does not contain a Git repository." forKey:NSLocalizedFailureReasonErrorKey];
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:userInfo];
    }
    return NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"activeTasks"]) {
        NSMutableArray *tasks = [change objectForKey:NSKeyValueChangeNewKey];
        if (tasks.count > 0) {
            [activity startAnimation:tasks];
        } else {
            [activity stopAnimation:tasks];
        }
    }
}

// This works around an Interface Builder/Xcode bug. If you make a toolbar
// item by dragging in a Custom View, the view's -drawRect never gets called.
// Instead the xib has a plain toolbar item that is modified at runtime.
- (void)toolbarWillAddItem:(NSNotification *)notification {
    NSToolbarItem *item = (NSToolbarItem *)[[notification userInfo] objectForKey:@"item"];

    if ([[item itemIdentifier] isEqualToString:@"xit.status"]) {
        if (statusView == nil)
            [NSBundle loadNibNamed:@"XTStatusView" owner:self];
        [item setView:statusView];
    }
}

#pragma mark - temp
- (IBAction)reload:(id)sender {
    NSLog(@"########## reload ##########");
    [self setValue:[NSArray arrayWithObjects:@".git/refs/", @".git/logs/", nil] forKey:@"reload"];
}
@end
