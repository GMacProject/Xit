import Cocoa

public class XTHistoryTableController: NSViewController
{
  struct ColumnID
  {
    static let commit = "commit"
    static let date = "date"
    static let email = "email"
  }
  
  let observers = ObserverCollection()

  weak var repository: XTRepository!
  {
    didSet
    {
      history.repository = repository

      guard let table = view as? NSTableView
      else { return }
      var spacing = table.intercellSpacing
      
      spacing.height = 0
      table.intercellSpacing = spacing

      loadHistory()
      observers.addObserver(
          forName: NSNotification.Name.XTRepositoryRefsChanged,
          object: repository, queue: .main) {
        [weak self] _ in
        // To do: dynamic updating
        // - new and changed refs: add if they're not already in the list
        // - deleted and changed refs: recursively remove unreferenced commits
        
        // For now: just reload
        self?.reload()
      }
      observers.addObserver(
          forName: NSNotification.Name.XTReselectModel,
          object: repository, queue: .main) {
        [weak self] _ in
        guard let tableView = self?.view as? NSTableView,
              let selectedIndex = tableView.selectedRowIndexes.first
        else { return }
        
        tableView.scrollRowToCenter(selectedIndex)
      }
    }
  }
  
  let history = GitCommitHistory()
  
  deinit
  {
    let center = NotificationCenter.default
  
    center.removeObserver(self)
  }
  
  override public func viewDidLoad()
  {
    super.viewDidLoad()
  
    let controller = view.window?.windowController!
    
    observers.addObserver(
        forName: .XTSelectedModelChanged,
        object: controller,
        queue: nil) {
      [weak self] (notification) in
      if let selectedModel = notification.userInfo?[NSKeyValueChangeKey.newKey]
                             as? FileChangesModel {
        self?.selectRow(sha: selectedModel.shaToSelect)
      }
    }
  }
  
  /// Reloads the commit history from scratch.
  public func reload()
  {
    let tableView = view as! NSTableView
    
    loadHistory()
    tableView.reloadData()
  }
  
  func loadHistory()
  {
    let repository = self.repository!
    let history = self.history
    weak var tableView = view as? NSTableView
    
    history.reset()
    repository.queue.executeOffMainThread {
      guard let walker = try? GTEnumerator(repository: repository.gtRepo)
      else {
        NSLog("GTEnumerator failed")
        return
      }
      
      walker.reset(options: [.topologicalSort, .timeSort])
      
      let refs = repository.allRefs()
      
      for ref in refs {
        _ = repository.sha(forRef: ref).flatMap { try? walker.pushSHA($0) }
      }
      
      while let gtCommit = walker.nextObject() as? GTCommit {
        let oid = GitOID(oidPtr: gtCommit.oid!.git_oid())
        guard let commit = XTCommit(oid: oid,
                                    repository: repository)
        else { continue }
        
        history.appendCommit(commit)
      }
      
      history.connectCommits()
      DispatchQueue.main.async {
        tableView?.reloadData()
        self.ensureSelection()
      }
    }
  }
  
  func ensureSelection()
  {
    guard let tableView = view as? NSTableView,
          tableView.selectedRowIndexes.count == 0
    else { return }
    
    guard let controller = self.view.window?.windowController
                           as? RepositoryController,
          let selectedModel = controller.selectedModel
    else { return }
    
    selectRow(sha: selectedModel.shaToSelect, forceScroll: true)
  }
  
  /// Selects the row for the given commit SHA.
  func selectRow(sha: String?, forceScroll: Bool = false)
  {
    let tableView = view as! NSTableView
    
    guard let sha = sha,
          let row = history.entries.index(where: { $0.commit.sha == sha })
    else {
      tableView.deselectAll(self)
      return
    }
    
    tableView.selectRowIndexes(IndexSet(integer: row),
                               byExtendingSelection: false)
    if forceScroll || (view.window?.firstResponder !== tableView) {
      tableView.scrollRowToCenter(row)
    }
  }
}

extension XTHistoryTableController: NSTableViewDelegate
{
  public func tableView(_ tableView: NSTableView,
                        viewFor tableColumn: NSTableColumn?,
                        row: Int) -> NSView?
  {
    guard (row >= 0) && (row < history.entries.count)
    else {
      NSLog("Object value request out of bounds")
      return nil
    }
    guard let tableColumn = tableColumn,
          let result = tableView.make(withIdentifier: tableColumn.identifier,
                                      owner: self) as? NSTableCellView
    else { return nil }
    
    let entry = history.entries[row]
    guard let sha = entry.commit.sha
    else { return nil }
    
    switch tableColumn.identifier {
      case ColumnID.commit:
        let historyCell = result as! XTHistoryCellView
        
        historyCell.refs = repository.refs(at: sha)
        historyCell.textField?.stringValue = entry.commit.message ?? ""
        historyCell.objectValue = entry
      case ColumnID.date:
        (result as! DateCellView).date = entry.commit.commitDate
      case ColumnID.email:
        result.textField?.stringValue = entry.commit.email ?? ""
      default:
        return nil
    }
    return result
  }
 
  public func tableViewSelectionDidChange(_ notification: Notification)
  {
    guard view.window?.firstResponder === view,
          let tableView = notification.object as? NSTableView
    else { return }
    
    let selectedRow = tableView.selectedRow
    
    if (selectedRow >= 0) && (selectedRow < history.entries.count),
       let controller = view.window?.windowController as? RepositoryController {
      controller.selectedModel =
          CommitChanges(repository: repository,
                        commit: history.entries[selectedRow].commit)
    }
  }
}

extension XTHistoryTableController: XTTableViewDelegate
{
  func tableViewClickedSelectedRow(_ tableView: NSTableView)
  {
    guard let selectionIndex = tableView.selectedRowIndexes.first,
          let controller = tableView.window?.windowController
                           as? RepositoryController
    else { return }
    
    let entry = history.entries[selectionIndex]
    let newModel = CommitChanges(repository: repository, commit: entry.commit)
    
    if (controller.selectedModel == nil) ||
       (controller.selectedModel?.shaToSelect != newModel.shaToSelect) ||
       (type(of:controller.selectedModel!) != type(of:newModel)) {
      controller.selectedModel = newModel
    }
  }
}

extension XTHistoryTableController: NSTableViewDataSource
{
  public func numberOfRows(in tableView: NSTableView) -> Int
  {
    return history.entries.count
  }
}
