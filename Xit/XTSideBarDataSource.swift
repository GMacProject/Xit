import Cocoa


extension XTSideBarDataSource {
  
  @nonobjc static let kReloadInterval: NSTimeInterval = 1
  
  public override func awakeFromNib()
  {
    outline!.target = self
    outline!.doubleAction = #selector(XTSideBarDataSource.doubleClick(_:))
    if (!XTAccountsManager.manager.accounts(ofType: .TeamCity).isEmpty) {
      buildStatusTimer = NSTimer.scheduledTimerWithTimeInterval(
          60 * 5,
          target: self,
          selector: #selector(XTSideBarDataSource.buildStatusTimerFired(_:)),
          userInfo: nil, repeats: true)
    }
  }
  
  func buildStatusTimerFired(timer: NSTimer)
  {
    updateTeamCity()
  }
  
  func scheduleReload()
  {
    if let timer = reloadTimer where timer.valid {
      timer.fireDate =
          NSDate(timeIntervalSinceNow: XTSideBarDataSource.kReloadInterval)
    }
    else {
      reloadTimer = NSTimer.scheduledTimerWithTimeInterval(
          XTSideBarDataSource.kReloadInterval,
          target: self,
          selector: #selector(XTSideBarDataSource.reloadTimerFired(_:)),
          userInfo: nil,
          repeats: false)
    }
  }
  
  func reloadTimerFired(timer: NSTimer)
  {
    dispatch_async(dispatch_get_main_queue()) { 
      self.outline!.reloadData()
    }
    reloadTimer = nil
  }
  
  func makeRoots() -> [XTSideBarGroupItem]
  {
    let rootNames =
        ["WORKSPACE", "BRANCHES", "REMOTES", "TAGS", "STASHES", "SUBMODULES"];
    let roots = rootNames.map({ XTSideBarGroupItem(title: $0) })
    
    roots[0].addChild(stagingItem)
    return roots;
  }
  
  func makeTagItems() -> [XTTagItem]
  {
    guard let tags = try? repo.tags()
    else { return [XTTagItem]() }
    
    return tags.map({ XTTagItem(tag: $0)})
  }
  
  func makeStashItems() -> [XTStashItem]
  {
    let stashes = repo.stashes()
    var stashItems = [XTStashItem]()
    
    for (index, stash) in stashes.enumerate() {
      let model = XTStashChanges(repository: repo, stash: stash)
      let message = stash.message ?? "stash \(index)"
    
      stashItems.append(XTStashItem(title: message, model: model))
    }
    return stashItems
  }
  
  func makeSubmoduleItems() -> [XTSubmoduleItem]
  {
    return repo.submodules().map({ XTSubmoduleItem(submodule: $0) })
  }
  
}

extension XTSideBarDataSource { // MARK: Updating
  
  func refsChanged(notification: NSNotification)
  {
    guard let info = notification.userInfo as? [String: Set<String>],
      let outline = outline
      else { return }
    
    let localBranchesPrefix = "refs/heads/"
    let tagsPrefix = "refs/tags/"
    let remoteBranchesPrefix = "refs/remotes/"
    
    if let added = info[XTAddedRefsKey]  {
      outline.beginUpdates()
      for addedRef in added {
        if let branchName = addedRef.substringAfterPrefix(localBranchesPrefix),
          let sha = repo.shaForRef(addedRef) {
          let model = XTCommitChanges(repository: repo, sha: sha)
          
          addItem(XTLocalBranchItem(title: branchName, model: model),
                     groupIndex: .Branches)
        }
        else if let tagName = addedRef.substringAfterPrefix(tagsPrefix),
          let tag = XTTag(repository: repo, name: tagName) {
          addItem(XTTagItem(tag: tag), groupIndex: .Tags)
        }
        else if let remoteBranchName =
          addedRef.substringAfterPrefix(remoteBranchesPrefix) {
          insertRemoteBranch(remoteBranchName)
        }
      }
      outline.endUpdates()
    }
    if let deleted = info[XTDeletedRefsKey] {
      outline.beginUpdates()
      for deletedRef in deleted {
        if let branchName = deletedRef.substringAfterPrefix(localBranchesPrefix) {
          deleteItem(branchName, groupIndex: .Branches)
        }
        else if let tagName = deletedRef.substringAfterPrefix(tagsPrefix) {
          deleteItem(tagName, groupIndex: .Tags)
        }
        else if let remoteBranchName =
          deletedRef.substringAfterPrefix(remoteBranchesPrefix) {
          deleteItem(remoteBranchName, groupIndex: .Remotes)
        }
      }
      outline.endUpdates()
    }
    // Don't care about changed refs
  }
  
  /// Adds the item to its parent and notifies the table.
  func insertItem(item: XTSideBarItem, atIndex index: Int, parent: XTSideBarItem)
  {
    parent.children.insert(item, atIndex: index)
    outline!.insertItemsAtIndexes(NSIndexSet(index: index),
                                  inParent: parent,
                                  withAnimation: .EffectFade)
  }
  
  /// Removes the item from its parent and notifies the table.
  func removeItem(atIndex index: Int, parent: XTSideBarItem)
  {
    parent.children.removeAtIndex(index)
    outline!.removeItemsAtIndexes(NSIndexSet(index: index),
                                  inParent: parent,
                                  withAnimation: .EffectFade)
  }
  
  /// Finds where a new item goes, and inserts it.
  func addItem(newItem: XTSideBarItem, groupIndex: XTGroupIndex)
  {
    let group = roots[groupIndex.rawValue]
    
    addItem(newItem, parent: group, path: newItem.title)
  }
  
  /// Adds a new item, recursively adding folders if necessary.
  func addItem(newItem: XTSideBarItem, parent: XTSideBarItem, path: String)
  {
    var insertIndex = parent.children.count
    let (folderTitle, subpath) = path.splitFirstPathComponent()
    
    for (index, item) in parent.children.enumerate() {
      if item.title == newItem.title {
        return
      }
      if (folderTitle == item.title) && (item is XTBranchFolderItem) {
        addItem(newItem, parent:item, path: subpath)
        return
      }
      if item.title > newItem.title {
        insertIndex = index
        break
      }
    }
    if let folderTitle = folderTitle {
      let folder = XTBranchFolderItem(title: folderTitle)
      
      insertItem(folder, atIndex: insertIndex, parent: parent)
      addItem(newItem, parent: folder, path: subpath)
    }
    else {
      insertItem(newItem, atIndex: insertIndex, parent: parent)
    }
  }
  
  /// Finds the matching item and deletes it.
  func deleteItem(name: String, groupIndex: XTGroupIndex)
  {
    deleteItem(name, parent: roots[groupIndex.rawValue])
  }
  
  /// Deletes an item, searching branch folders recursively.
  func deleteItem(name: String, parent: XTSideBarItem)
  {
    for (index, item) in parent.children.enumerate() {
      // A folder can have the same name as a branch.
      if let folder = item as? XTBranchFolderItem where
         name.hasPrefix(folder.title) && (name != folder.title) {
        deleteItem(name, parent: folder)
        if folder.children.isEmpty {
          removeItem(atIndex: index, parent: parent)
        }
      }
      if item.title == name {
        removeItem(atIndex: index, parent: parent)
        break
      }
    }
  }
  
  func insertRemoteBranch(branchName: String)
  {
    let remotes = roots[XTGroupIndex.Remotes.rawValue]
    
    for remote in remotes.children {
      if branchName.hasPrefix(remote.title) {
        break
      }
    }
  }
  
  func deleteSidebarItem(name: String, groupIndex: XTGroupIndex)
  {
    let group = roots[groupIndex.rawValue]
    
    for (index, item) in group.children.enumerate() {
      if item.title == name {
        removeItem(atIndex: index, parent: group)
        break
      }
    }
  }

}

extension XTSideBarDataSource { // MARK: TeamCity
  
  func updateTeamCity()
  {
    guard let localBranches = try? repo.localBranches()
    else { return }
    
    buildStatuses = [:]
    for local in localBranches {
      guard let fullBranchName = local.name,
            let tracked = local.trackingBranch,
            let (api, buildTypes) = matchTeamCity(tracked.remoteName)
      else { continue }
      
      let branchName = (fullBranchName as NSString).lastPathComponent
      
      for buildType in buildTypes {
        let statusResource = api.buildStatus(branchName, buildType: buildType)
        
        statusResource.useData(self) { (data) in
          guard let xml = data.content as? NSXMLDocument,
                let firstBuildElement =
                    xml.rootElement()?.children?.first as? NSXMLElement,
                let build = XTTeamCityAPI.Build(element: firstBuildElement)
          else { return }
          
          NSLog("\(buildType)/\(branchName): \(build.status)")
          var buildTypeStatuses = self.buildStatuses[buildType] as? [String: Bool] ?? [String: Bool]()
          
          buildTypeStatuses[branchName] = build.status == .Succeeded
          self.buildStatuses[buildType] = buildTypeStatuses
          self.scheduleReload()
        }
      }
    }
  }
  
  /// Returns the name of the remote for either a remote branch or a local
  /// tracking branch.
  func remoteName(forBranchItem branchItem: XTSideBarItem) -> String?
  {
    if let remoteBranchItem = branchItem as? XTRemoteBranchItem {
      return remoteBranchItem.remote
    }
    else if let localBranchItem = branchItem as? XTLocalBranchItem {
      guard let branch = XTLocalBranch(repository: repo,
                                       name: localBranchItem.title)
      else {
        NSLog("Can't get branch for branch item: \(branchItem.title)")
        return nil
      }
      
      return branch.trackingBranch?.remoteName
    }
    return nil
  }
  
  /// Returns the first TeamCity service that builds from the given repository,
  /// and a list of its build types.
  func matchTeamCity(remoteName: String) -> (XTTeamCityAPI, [String])?
  {
    guard let remote = XTRemote(name: remoteName, repository: repo),
          let remoteURL = remote.URLString
    else { return nil }
    
    let accounts = XTAccountsManager.manager.accounts(ofType: .TeamCity)
    let services = accounts.flatMap({ XTServices.services.teamCityAPI($0) })
    
    for service in services {
      let buildTypes = service.buildTypes(forRemote: remoteURL)
      
      if !buildTypes.isEmpty {
        return (service, buildTypes)
      }
    }
    return nil
  }
  
  func statusImage(item: XTSideBarItem) -> NSImage?
  {
    guard let remoteName = remoteName(forBranchItem: item),
          let (_, buildTypes) = matchTeamCity(remoteName)
    else { return nil }
    
    let branchName = (item.title as NSString).lastPathComponent
    var overallSuccess: Bool?
    
    for buildType in buildTypes {
      if let buildSuccess = buildStatuses[buildType]?[branchName]??.boolValue {
        overallSuccess = (overallSuccess ?? true) && buildSuccess
      }
    }
    if overallSuccess == nil {
      return NSImage(named: NSImageNameStatusNone)
    }
    else {
      return NSImage(named: overallSuccess!
          ? NSImageNameStatusAvailable
          : NSImageNameStatusUnavailable)
    }
  }
}

extension XTSideBarDataSource: NSOutlineViewDataSource {
  // MARK: NSOutlineViewDataSource
  
  public func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
    if item == nil {
      return roots.count
    }
    return (item as? XTSideBarItem)?.children.count ?? 0
  }
  
  public func outlineView(outlineView: NSOutlineView,
                          isItemExpandable item: AnyObject) -> Bool {
    return (item as? XTSideBarItem)?.expandable ?? false
  }
  
  public func outlineView(outlineView: NSOutlineView,
                          child index: Int,
                          ofItem item: AnyObject?) -> AnyObject {
    if item == nil {
      return roots[index]
    }
    return (item as! XTSideBarItem).children[index]
  }
}

extension XTSideBarDataSource: NSOutlineViewDelegate {
  // MARK: NSOutlineViewDelegate

  public func outlineViewSelectionDidChange(notification: NSNotification)
  {
    guard let item = outline!.itemAtRow(outline!.selectedRow) as? XTSideBarItem,
          let model = item.model,
          let controller = outline!.window?.windowController as? XTWindowController
    else { return }
    
    controller.selectedModel = model
  }


  public func outlineView(outlineView: NSOutlineView,
                          isGroupItem item: AnyObject) -> Bool
  {
    return item is XTSideBarGroupItem
  }

  public func outlineView(outlineView: NSOutlineView,
                          shouldSelectItem item: AnyObject) -> Bool
  {
    return (item as? XTSideBarItem)?.selectable ?? false
  }

  public func outlineView(outlineView: NSOutlineView,
                          heightOfRowByItem item: AnyObject) -> CGFloat
  {
    // Using this instead of setting rowSizeStyle because that prevents text
    // from displaying as bold (for the active branch).
   return 20.0
  }

  public func outlineView(outlineView: NSOutlineView,
                          viewForTableColumn tableColumn: NSTableColumn?,
                          item: AnyObject) -> NSView?
  {
    guard let sideBarItem = item as? XTSideBarItem
    else { return nil }
    
    if item is XTSideBarGroupItem {
      guard let headerView = outlineView.makeViewWithIdentifier(
          "HeaderCell", owner: self) as? NSTableCellView
      else { return nil }
      
      headerView.textField?.stringValue = sideBarItem.title
      return headerView
    }
    else {
      guard let dataView = outlineView.makeViewWithIdentifier(
          "DataCell", owner: self) as? XTSideBarTableCellView
      else { return nil }
      
      let textField = dataView.textField!
      
      dataView.item = sideBarItem
      dataView.imageView?.image = sideBarItem.icon
      textField.stringValue = sideBarItem.displayTitle
      textField.editable = sideBarItem.editable
      textField.selectable = sideBarItem.selectable
      dataView.statusImage.image = statusImage(sideBarItem)
      if sideBarItem.editable {
        textField.formatter = refFormatter
        textField.target = viewController
        textField.action =
            #selector(XTHistoryViewController.sideBarItemRenamed(_:))
      }
      if sideBarItem.current {
        textField.font = NSFont.boldSystemFontOfSize(
            textField.font?.pointSize ?? 12)
      }
      else {
        textField.font = NSFont.systemFontOfSize(
            textField.font?.pointSize ?? 12)
      }
      return dataView
    }
  }
}
