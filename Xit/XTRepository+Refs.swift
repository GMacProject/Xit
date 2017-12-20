import Foundation

// MARK: Refs
extension XTRepository: CommitReferencing
{
  /// Reloads the cached map of OIDs to refs.
  func rebuildRefsIndex()
  {
    var payload = CallbackPayload(repo: self)
    let callback: git_reference_foreach_cb = {
      (reference, payload) -> Int32 in
      let repo = payload!.bindMemory(to: XTRepository.self,
                                     capacity: 1).pointee
      
      let rawName = git_reference_name(reference)
      guard rawName != nil,
        let name = String(validatingUTF8: rawName!)
        else { return 0 }
      
      var peeled: OpaquePointer? = nil
      guard git_reference_peel(&peeled, reference, GIT_OBJ_COMMIT) == 0
        else { return 0 }
      
      let peeledOID = git_object_id(peeled)
      guard let sha = peeledOID.map({ GitOID(oid: $0.pointee) })?.sha
      else { return 0 }
      var refs = repo.refsIndex[sha] ?? [String]()
      
      refs.append(name)
      repo.refsIndex[sha] = refs
      
      return 0
    }
    
    refsIndex.removeAll()
    git_reference_foreach(gtRepo.git_repository(), callback, &payload)
  }
  
  /// Returns a list of refs that point to the given commit.
  func refs(at sha: String) -> [String]
  {
    return refsIndex[sha] ?? []
  }
  
  /// Returns a list of all ref names.
  func allRefs() -> [String]
  {
    var stringArray = git_strarray()
    guard git_reference_list(&stringArray, gtRepo.git_repository()) == 0
    else { return [] }
    defer { git_strarray_free(&stringArray) }
    
    return stringArray.flatMap { $0 }
  }

  public var headRef: String?
  {
    objc_sync_enter(self)
    defer {
      objc_sync_exit(self)
    }
    if cachedHeadRef == nil {
      recalculateHead()
    }
    return cachedHeadRef
  }
  
  var headSHA: String?
  {
    return headRef.map { sha(forRef: $0) } ?? nil
  }

  @objc public var currentBranch: String?
  {
    mutex.lock()
    defer { mutex.unlock() }
    if cachedBranch == nil {
      refsChanged()
    }
    return cachedBranch
  }

  func calculateCurrentBranch() -> String?
  {
    guard let branch = try? gtRepo.currentBranch(),
          let shortName = branch.shortName
    else { return nil }
    
    if let remoteName = branch.remoteName {
      return "\(remoteName)/\(shortName)"
    }
    else {
      return branch.shortName
    }
  }

  func hasHeadReference() -> Bool
  {
    if (try? gtRepo.headReference()) != nil {
      return true
    }
    else {
      return false
    }
  }
  
  func parseSymbolicReference(_ reference: String) -> String?
  {
    guard let gtRef = try? gtRepo.lookUpReference(withName: reference)
    else { return nil }
    
    if let unresolvedRef = gtRef.unresolvedTarget as? GTReference,
       let name = unresolvedRef.name {
      return name
    }
    return reference
  }
  
  func parentTree() -> String
  {
    return hasHeadReference() ? "HEAD" : kEmptyTreeHash
  }
  
  // TODO: Move this to a protocol extension
  func sha(forRef ref: String) -> String?
  {
    return oid(forRef: ref)?.sha
  }
  
  func oid(forRef ref: String) -> OID?
  {
    let object = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
    let result = git_revparse_single(object, gtRepo.git_repository(), ref)
    guard result == 0,
          let finalObject = object.pointee,
          let oid = git_object_id(finalObject)
    else { return nil }
    
    return GitOID(oidPtr: oid)
  }
  
  public func localBranch(named name: String) -> LocalBranch?
  {
    return GitLocalBranch(repository: self, name: name)
  }
  
  public func remoteBranch(named name: String, remote: String) -> RemoteBranch?
  {
    return GitRemoteBranch(repository: self, name: "\(remote)/\(name)")
  }
  
  public func remoteBranch(named name: String) -> RemoteBranch?
  {
    return GitRemoteBranch(repository: self, name: name)
  }
  
  func createBranch(_ name: String) -> Bool
  {
    clearCachedBranch()
    return (try? executeGit(args: ["checkout", "-b", name],
                            writes: true)) != nil
  }
  
  func deleteBranch(_ name: String) -> Bool
  {
    return writing {
      let fullBranch = GTBranch.localNamePrefix().appending(name)
      guard let ref = try? gtRepo.lookUpReference(withName: fullBranch),
            let branch = GTBranch(reference: ref)
      else { return false }
      
      return (try? branch.delete()) != nil
    }
  }
  
  /// Renames the given local branch.
  @objc(renameBranch:to:error:)
  func rename(branch: String, to newName: String) throws
  {
    if isWriting {
      throw Error.alreadyWriting
    }
    
    let branchRef = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
    var result = git_branch_lookup(branchRef, gtRepo.git_repository(),
                                   branch, GIT_BRANCH_LOCAL)
    
    if result != 0 {
      throw NSError.git_error(for: result)
    }
    
    let newRef = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
    
    result = git_branch_move(newRef, branchRef.pointee, newName, 0)
    if result != 0 {
      throw NSError.git_error(for: result)
    }
  }
  
  public func remoteNames() -> [String]
  {
    let strArray = UnsafeMutablePointer<git_strarray>.allocate(capacity: 1)
    guard git_remote_list(strArray, gtRepo.git_repository()) == 0
    else { return [] }
    
    return strArray.pointee.flatMap { $0 }
  }
  
  public func stashes() -> Stashes
  {
    return Stashes(repo: self)
  }
  
  /// Returns the list of tags, or throws if libgit2 hit an error.
  public func tags() throws -> [Tag]
  {
    let tagNames = UnsafeMutablePointer<git_strarray>.allocate(capacity: 1)
    let result = git_tag_list(tagNames, gtRepo.git_repository())
    
    try Error.throwIfError(result)
    defer { git_strarray_free(tagNames) }
    
    return tagNames.pointee.flatMap {
      name in name.flatMap { GitTag(repository: self, name: $0) }
    }
  }
}

extension XTRepository: BranchListing
{
  public func localBranches() -> Branches<GitLocalBranch>
  {
    return Branches(repo: self, type: GIT_BRANCH_LOCAL)
  }
  
  public func remoteBranches() -> Branches<GitRemoteBranch>
  {
    return Branches(repo: self, type: GIT_BRANCH_REMOTE)
  }
}
