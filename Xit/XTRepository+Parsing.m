#import "XTRepository+Parsing.h"
#import "XTConstants.h"
#import "Xit-Swift.h"
#import <ObjectiveGit/ObjectiveGit.h>
#import <ObjectiveGit/GTRepository+Status.h>
#import "NSDate+Extensions.h"
#import "Xit-Swift.h"

@interface XTRepository (Private)

@property (readonly, copy) NSArray *stagingChanges;

@end


@implementation XTRepository (Reading)

- (BOOL)
    readRefsWithLocalBlock:(void (^)(NSString *name, NSString *commit))localBlock
               remoteBlock:(void (^)(NSString *remoteName, NSString *branchName,
                                     NSString *commit))remoteBlock
                  tagBlock:(void (^)(NSString *name, NSString *commit))tagBlock
{
  NSError *error = nil;
  NSData *output =
      [self executeGitWithArgs:@[ @"show-ref", @"-d" ]
                        writes:NO
                         error:&error];

  if (output != nil) {
    NSString *refs =
        [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    NSScanner *scanner = [NSScanner scannerWithString:refs];
    NSString *localBranchPrefix = @"refs/heads/";
    NSString *tagPrefix = @"refs/tags/";
    NSString *remotePrefix = @"refs/remotes/";
    NSString *commit;
    NSString *name;

    while ([scanner scanUpToString:@" " intoString:&commit]) {
      [scanner scanUpToString:@"\n" intoString:&name];
      if ([name hasPrefix:localBranchPrefix]) {
        localBlock([name substringFromIndex:localBranchPrefix.length],
                   commit);
      } else if ([name hasPrefix:tagPrefix]) {
        tagBlock([name substringFromIndex:tagPrefix.length], commit);
      } else if ([name hasPrefix:remotePrefix]) {
        NSString *remoteName = name.pathComponents[2];
        const NSUInteger prefixLen =
            remotePrefix.length + remoteName.length + 1;
        NSString *branchName = [name substringFromIndex:prefixLen];

        remoteBlock(remoteName, branchName, commit);
      }
    }
  }
  return error == nil;
}

- (NSDictionary<NSString*, XTWorkspaceFileStatus*>*)workspaceStatus
{
  NSMutableDictionary<NSString*, XTWorkspaceFileStatus*> *result =
      [NSMutableDictionary dictionary];
  NSDictionary *options =
      @{ GTRepositoryStatusOptionsFlagsKey:@(GIT_STATUS_OPT_INCLUDE_UNTRACKED) };

  [self.gtRepo enumerateFileStatusWithOptions:options error:NULL
      usingBlock:^(GTStatusDelta * _Nullable headToIndex,
                   GTStatusDelta * _Nullable indexToWorkingDirectory,
                   BOOL * _Nonnull stop) {
    NSString *path = headToIndex.oldFile.path;
    
    if (path == nil)
      path = indexToWorkingDirectory.oldFile.path;
    if (path != nil) {
      XTWorkspaceFileStatus *status = [[XTWorkspaceFileStatus alloc] init];
      
      status.unstagedChange = (XitChange)indexToWorkingDirectory.status;
      status.change = (XitChange)headToIndex.status;
      result[path] = status;
    }
  }];
  return result;
}

- (BOOL)readStashesWithBlock:(void (^)(NSString *, NSUInteger, NSString *))block
{
  NSError *error = nil;
  NSData *output =
      [self executeGitWithArgs:@[ @"stash", @"list", @"--pretty=%H %gd %gs" ]
                        writes:NO
                         error:&error];

  if (output != nil) {
    NSString *refs =
        [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    NSScanner *scanner = [NSScanner scannerWithString:refs];
    NSString *commit, *name;
    NSUInteger stashIndex = 0;

    while ([scanner scanUpToString:@" " intoString:&commit]) {
      [scanner scanUpToString:@"\n" intoString:&name];
      block(commit, stashIndex, name);
      ++stashIndex;
    }
  }
  return error == nil;
}

- (GTDiff*)diffForSHA:(NSString*)sha parent:(NSString*)parentSHA
{
  NSParameterAssert(sha != nil);
  if (parentSHA == nil)
    parentSHA = @"";

  NSString *key = [sha stringByAppendingString:parentSHA];
  GTDiff *diff = [_diffCache objectForKey:key];

  if (diff == nil) {
    NSError *error = nil;
    GTCommit *commit = [_gtRepo lookUpObjectBySHA:sha error:&error];

    if ((commit == nil) ||
        (git_object_type([commit git_object]) != GIT_OBJ_COMMIT))
      return nil;

    NSArray *parents = commit.parents;
    GTCommit *parent = nil;

    if (parents.count != 0) {
      if ([parentSHA isEqualToString:@""]) {
        parent = parents[0];
      } else {
        for (GTCommit *iterParent in parents)
          if ([iterParent.SHA isEqualToString:parentSHA]) {
            parent = iterParent;
            break;
          }
        if (parent == nil)
          [NSException raise:NSInternalInconsistencyException
                      format:@"Diff parent not found"];
      }
    }

    diff = [GTDiff diffOldTree:parent.tree
                   withNewTree:commit.tree
                  inRepository:_gtRepo
                       options:nil
                         error:&error];
    [_diffCache setObject:diff forKey:key];
  }
  return diff;
}

- (NSArray<XTFileChange*>*)changesForRef:(NSString*)ref
                                  parent:(NSString*)parentSHA
{
  if (ref == nil)
    return nil;

  if ([ref isEqualToString:XTStagingSHA])
    return [self stagingChanges];

  NSError *error = nil;
  GTCommit *commit = [_gtRepo lookUpObjectByRevParse:ref error:&error];
  
  if ((commit == nil) ||
      (git_object_type([commit git_object]) != GIT_OBJ_COMMIT))
    return nil;
  if (parentSHA == nil)
    parentSHA = commit.parents.firstObject.SHA;
  
  GTDiff *diff = [self diffForSHA:commit.SHA parent:parentSHA];

  NSMutableArray *result = [NSMutableArray array];

  if (error != nil)
    return nil;
  [diff enumerateDeltasUsingBlock:^(GTDiffDelta *delta, BOOL *stop) {
    if (delta.type != GTDeltaTypeUnmodified) {
      XTFileChange *change = [[XTFileChange alloc] init];

      change.path = delta.newFile.path;
      change.change = (XitChange)delta.type;
      [result addObject:change];
    }
  }];
  return result;
}

- (GTCommit*)commitForStashAtIndex:(NSUInteger)index
{
  GTReference *stashRef = [self.gtRepo lookUpReferenceWithName:@"refs/stash" error:NULL];
  
  if (stashRef == nil)
    return nil;
  
  GTReflog *stashLog = [[GTReflog alloc] initWithReference:stashRef];
  
  if ((stashLog == nil) || (index >= stashLog.entryCount))
    return nil;
  
  GTReflogEntry *entry = [stashLog entryAtIndex:index];
  
  if (entry == nil)
    return nil;
  return [self.gtRepo lookUpObjectByOID:entry.updatedOID error:nil];
}

- (NSArray*)stagingChanges
{
  NSMutableArray *result = [NSMutableArray array];
  NSDictionary *options = @{
      GTRepositoryStatusOptionsFlagsKey: @(GTRepositoryStatusFlagsIncludeUntracked) };
  NSError *error = nil;
  
  if (![_gtRepo enumerateFileStatusWithOptions:options
                                         error:nil
                                    usingBlock:
      ^(GTStatusDelta *headToIndex, GTStatusDelta *indexToWorking, BOOL *stop) {
    XTFileStaging *change = [[XTFileStaging alloc] init];
    
    if (headToIndex != nil) {
      change.path = headToIndex.oldFile.path;
      change.destinationPath = headToIndex.newFile.path;
    } else {
      change.path = indexToWorking.oldFile.path;
      change.destinationPath = indexToWorking.newFile.path;
    }
    change.change = (XitChange)headToIndex.status;
    change.unstagedChange = (XitChange)indexToWorking.status;
    [result addObject:change];
  }]) {
    NSLog(@"Can't enumerate file status: %@", error.description);
    return nil;
  }
  
  return result;
}

- (BOOL)isTextFile:(NSString*)path commit:(NSString*)commit
{
  NSString *name = path.lastPathComponent;

  if (name.length == 0)
    return NO;

  NSArray *extensionlessNames = @[
      @"AUTHORS", @"CONTRIBUTING", @"COPYING", @"LICENSE", @"Makefile",
      @"README", ];

  for (NSString *extensionless in extensionlessNames)
    if ([name isCaseInsensitiveLike:extensionless])
      return YES;

  NSString *extension = name.pathExtension;
  const CFStringRef utType = UTTypeCreatePreferredIdentifierForTag(
      kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
  const Boolean result = UTTypeConformsTo(utType, kUTTypeText);
  
  CFRelease(utType);
  return result;
}

- (nullable XTRemote*)remoteWithName:(NSString*)name error:(NSError**)error
{
  return [XTRemote remoteWithName:name inRepository:_gtRepo error:error];
}

- (nullable NSArray<XTLocalBranch*>*)localBranchesWithError:(NSError**)error
{
  NSArray<GTBranch*> *gtBranches =
      [_gtRepo localBranchesWithError:error];

  if (gtBranches == nil)
    return nil;
  
  NSMutableArray<XTLocalBranch*> *result =
      [NSMutableArray arrayWithCapacity:gtBranches.count];
  
  for (GTBranch *gtBranch in gtBranches)
    [result addObject:[[XTLocalBranch alloc] initWithGtBranch:gtBranch]];
  return result;
}

- (XTDiffDelta*)deltaFromDiff:(GTDiff*)diff withPath:(NSString*)path
{
  __block GTDiffDelta *result = nil;
  
  [diff enumerateDeltasUsingBlock:^(GTDiffDelta *delta, BOOL *stop) {
    if ([delta.newFile.path isEqualToString:path]) {
      *stop = YES;
      result = delta;
    }
  }];
  return (XTDiffDelta*)result;
}

- (XTDiffDelta*)diffForFile:(NSString*)path
                  commitSHA:(NSString*)sha
                  parentSHA:(NSString*)parentSHA
{
  GTDiff *diff = [self diffForSHA:sha parent:parentSHA];
  
  return [self deltaFromDiff:diff withPath:path];
}

- (BOOL)stageAllFilesWithError:(NSError**)error
{
  return [self executeGitWithArgs:@[ @"add", @"--all" ]
                           writes:YES
                            error:error] != nil;
}

- (BOOL)unstageFile:(NSString*)file error:(NSError**)error
{
  NSArray *args = self.hasHeadReference
      ? @[ @"reset", @"-q", @"HEAD", file ]
      : @[ @"rm", @"--cached", file ];
  
  return [self executeGitWithArgs:args writes:YES error:error] != nil;
}

- (BOOL)commitWithMessage:(NSString *)message
                    amend:(BOOL)amend
              outputBlock:(void (^)(NSString *output))outputBlock
                    error:(NSError **)error
{
  NSArray *args = @[ @"commit", @"-F", @"-" ];

  if (amend)
    args = [args arrayByAddingObject:@"--amend"];

  NSData *output = [self executeGitWithArgs:args
                                  withStdIn:message
                                     writes:YES
                                      error:error];

  if (output == nil)
    return NO;
  if (outputBlock != NULL)
    outputBlock([[NSString alloc] initWithData:output
                                      encoding:NSUTF8StringEncoding]);
  return YES;
}

@end


@implementation XTFileChange

- (instancetype)initWithPath:(NSString*)path
{
  return [self initWithPath:path
                     change:XitChangeUnmodified
             unstagedChange:XitChangeUnmodified];
}

- (instancetype)initWithPath:(NSString*)path
                      change:(XitChange)change
{
  return [self initWithPath:path
                     change:change
             unstagedChange:XitChangeUnmodified];
}

- (instancetype)initWithPath:(NSString*)path
                      change:(XitChange)change
              unstagedChange:(XitChange)unstagedChange
{
  if ((self = [super init]) == nil)
    return nil;
  
  self.path = path;
  self.change = change;
  self.unstagedChange = unstagedChange;
  return self;
}

-(NSString*)description
{
  return [NSString stringWithFormat:@"%@ %ld %ld", self.path.description,
          self.change, self.unstagedChange];
}

@end


@implementation XTWorkspaceFileStatus

@end


@implementation XTFileStaging

@end


@implementation XTDiffDelta

@end
