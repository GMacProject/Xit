#import "Xit-Swift.h"
#import "XTSideBarDataSource.h"
#import "XTConstants.h"
#import "XTRefFormatter.h"
#import "XTRepository+Commands.h"
#import "XTRepository+Parsing.h"
#import "XTSideBarTableCellView.h"
#import "NSMutableDictionary+MultiObjectForKey.h"
#import <ObjectiveGit/ObjectiveGit.h>

NSString * const XTStagingSHA = @"";


@interface XTSideBarDataSource ()

- (NSArray<XTSideBarGroupItem*>*)loadRoots;

@property (readwrite) NSArray<XTSideBarGroupItem*> *roots;
@property (readwrite) XTSideBarItem *stagingItem;
@property NSMutableArray<BOSResource*> *observedResources;

@end


@implementation XTSideBarDataSource

- (instancetype)init
{
  if ((self = [super init]) != nil) {
    _stagingItem = [[XTStagingItem alloc] initWithTitle:@"Staging"];
    _roots = [self makeRoots];
    self.stagingItem = [[XTStagingItem alloc] initWithTitle:@"Staging"];
    self.roots = [self makeRoots];
    _roots = [self makeRoots];
    _stagingItem = [[XTStagingItem alloc] initWithTitle:@"Staging"];
    _observedResources = [[NSMutableArray alloc] init];
    self.buildStatuses = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.buildStatusTimer invalidate];
}

- (void)setRepo:(XTRepository *)newRepo
{
  _repo = newRepo;
  if (_repo != nil) {
    _stagingItem.model = [[XTStagingChanges alloc] initWithRepository:_repo];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(refsChanged:)
               name:XTRepositoryRefsChangedNotification
             object:_repo];
    [self reload];
  }
}

- (void)reload
{
  [_repo executeOffMainThread:^{
    NSArray *newRoots = [self loadRoots];

    dispatch_async(dispatch_get_main_queue(), ^{
      [self willChangeValueForKey:@"reload"];
      _roots = newRoots;
      [self didChangeValueForKey:@"reload"];
      [self.outline reloadData];
      // Empty groups get automatically collapsed, so counter that.
      [self.outline expandItem:nil expandChildren:YES];
    });
  }];
}

- (NSArray<XTSideBarGroupItem*>*)loadRoots
{
  NSArray<XTSideBarGroupItem*> *newRoots = [self makeRoots];

  NSMutableDictionary *refsIndex = [NSMutableDictionary dictionary];
  XTSideBarItem *branches = newRoots[XTGroupIndexBranches];
  NSMutableArray *tags = [NSMutableArray array];
  XTSideBarItem *remotes = newRoots[XTGroupIndexRemotes];
  NSArray<XTStashItem*> *stashes = [self makeStashItems];
  NSArray<XTSubmoduleItem*> *submodules = [self makeSubmoduleItems];

  [self loadBranches:branches tags:tags remotes:remotes refsIndex:refsIndex];

  [newRoots[XTGroupIndexTags] setChildren:tags];
  [newRoots[XTGroupIndexStashes] setChildren:stashes];
  [newRoots[XTGroupIndexSubmodules] setChildren:submodules];

  _repo.refsIndex = refsIndex;
  _currentBranch = [_repo currentBranch];

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateTeamCity];
  });

  return newRoots;
}

- (void)loadStashes:(NSMutableArray *)stashes
          refsIndex:(NSMutableDictionary *)refsIndex
{
  [_repo readStashesWithBlock:
      ^(NSString *commit, NSUInteger index, NSString *name) {
    XTStashChanges *stashModel = [[XTStashChanges alloc]
        initWithRepository:_repo index:index];
    XTSideBarItem *stash = [[XTStashItem alloc]
        initWithTitle:name model:stashModel];
    
    [stashes addObject:stash];
    [refsIndex addObject:name forKey:commit];
  }];
}

- (XTSideBarItem*)parentForBranch:(NSArray*)components
                        underItem:(XTSideBarItem*)item
{
  if (components.count == 1)
    return item;
  
  NSString *folderName = components[0];

  for (XTSideBarItem *child in item.children) {
    if (child.expandable && [child.title isEqualToString:folderName]) {
      const NSRange subRange = NSMakeRange(1, components.count-1);
      
      return [self parentForBranch:[components subarrayWithRange:subRange]
                         underItem:child];
    }
  }
  
  XTBranchFolderItem *newItem =
      [[XTBranchFolderItem alloc] initWithTitle:folderName];

  [item addChild:newItem];
  return newItem;
}

- (XTSideBarItem*)parentForBranch:(NSString*)branch
                        groupItem:(XTSideBarItem*)group
{
  NSArray *components = [branch componentsSeparatedByString:@"/"];
  
  return [self parentForBranch:components
                     underItem:group];
}

- (void)loadBranches:(XTSideBarItem*)branches
                tags:(NSMutableArray*)tags
             remotes:(XTSideBarItem*)remotes
           refsIndex:(NSMutableDictionary *)refsIndex
{
  NSMutableDictionary *remoteIndex = [NSMutableDictionary dictionary];
  NSMutableDictionary *tagIndex = [NSMutableDictionary dictionary];

  void (^localBlock)(NSString *, NSString *) =
      ^(NSString *name, NSString *commit) {
    XTCommitChanges *branchModel =
        [[XTCommitChanges alloc] initWithRepository:_repo sha:commit];
    XTLocalBranchItem *branch =
        [[XTLocalBranchItem alloc] initWithTitle:name
                                           model:branchModel];
    XTSideBarItem *parent = [self parentForBranch:name groupItem:branches];

    [parent addChild:branch];
    [refsIndex addObject:[@"refs/heads" stringByAppendingPathComponent:name]
                  forKey:commit];
  };

  void (^remoteBlock)(NSString *, NSString *, NSString *) =
      ^(NSString *remoteName, NSString *branchName, NSString *commit) {
    XTSideBarItem *remote = remoteIndex[remoteName];

    if (remote == nil) {
      remote = [[XTRemoteItem alloc] initWithTitle:remoteName
                                        repository:self.repo];
      [remotes addChild:remote];
      remoteIndex[remoteName] = remote;
    }

    XTCommitChanges *branchModel =
        [[XTCommitChanges alloc] initWithRepository:_repo sha:commit];
    XTRemoteBranchItem *branch =
        [[XTRemoteBranchItem alloc] initWithTitle:branchName
                                           remote:remoteName
                                            model:branchModel];
    NSString *branchRef =
        [NSString stringWithFormat:@"refs/remotes/%@/%@", remoteName, branchName];
    XTSideBarItem *parent = [self parentForBranch:branchName groupItem:remote];

    [parent addChild:branch];
    [refsIndex addObject:branchRef
                  forKey:commit];
  };

  void (^tagBlock)(NSString *, NSString *) = ^(NSString *name, NSString *commit) {
    XTTagItem *tag;
    XTCommitChanges *tagModel =
        [[XTCommitChanges alloc] initWithRepository:_repo sha:commit];

    if ([name hasSuffix:@"^{}"]) {
      name = [name substringToIndex:name.length - 3];
      tag = tagIndex[name];
      tag.model = tagModel;
    } else {
      tag = [[XTTagItem alloc] initWithTitle:name model:tagModel];
      [tags addObject:tag];
      tagIndex[name] = tag;
    }
    [refsIndex addObject:[@"refs/tags" stringByAppendingPathComponent:name]
                  forKey:commit];
  };

  [_repo readRefsWithLocalBlock:localBlock
                    remoteBlock:remoteBlock
                       tagBlock:tagBlock];
}

- (void)doubleClick:(id)sender
{
  id clickedItem = [self.outline itemAtRow:self.outline.clickedRow];

  if ([clickedItem isKindOfClass:[XTSubmoduleItem class]]) {
    XTSubmoduleItem *subItem = (XTSubmoduleItem*)clickedItem;
    NSString *subPath = subItem.submodule.path;
    NSString *rootPath = _repo.repoURL.path;
    NSURL *subURL = [NSURL fileURLWithPath:
        [rootPath stringByAppendingPathComponent:subPath]];
    
    [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:subURL
                              display:YES
                    completionHandler:^(NSDocument *doc,BOOL open, NSError *error) {}];
  }
}

- (XTLocalBranchItem *)itemForBranchName:(NSString *)branch
{
  XTSideBarItem *branches = _roots[XTGroupIndexBranches];

  for (XTSideBarItem *branchItem in branches.children) {
    if ([branchItem.title isEqual:branch])
      return (XTLocalBranchItem*)branchItem;
  }
  return nil;
}

- (XTSideBarItem *)itemNamed:(NSString *)name inGroup:(NSInteger)groupIndex
{
  XTSideBarItem *group = _roots[groupIndex];

  for (XTSideBarItem *item in group.children) {
    if ([item.title isEqual:name])
      return item;
  }
  return nil;
}

@end
