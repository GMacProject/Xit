import Foundation

/// Abstract base class for file list data sources.
class FileListDataSourceBase: NSObject
{
  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var controller: FileViewController!
  let useWorkspaceList: Bool

  let observers = ObserverCollection()
  
  weak var delegate: FileListDelegate?

  weak var repoController: RepositoryController!
  {
    didSet
    {
      (self as! FileListDataSource).reload()
      observers.addObserver(forName: .XTRepositoryWorkspaceChanged,
                            object: repoController.repository, queue: .main) {
        [weak self] (note) in
        guard let self = self
        else { return }
        
        if self.outlineView?.dataSource === self {
          self.workspaceChanged(note.userInfo?[XTPathsKey] as? [String])
        }
      }
      observers.addObserver(forName: .XTSelectedModelChanged,
                            object: repoController, queue: .main) {
        [weak self] (_) in
        guard let self = self,
              self.outlineView?.dataSource === self,
              self.repoController != nil // Otherwise we're on a stale timer
        else { return }
        
        (self as? FileListDataSource)?.reload()
      }
    }
  }
  
  class func transformDisplayChange(_ change: DeltaStatus) -> DeltaStatus
  {
    return (change == .unmodified) ? .mixed : change
  }
  
  init(useWorkspaceList: Bool)
  {
    self.useWorkspaceList = useWorkspaceList
  }

  func model(for selection: RepositorySelection) -> FileListModel?
  {
    return useWorkspaceList
        ? (selection as? StagedUnstagedSelection)?.unstagedFileList
        : selection.fileList
  }
  
  func workspaceChanged(_ paths: [String]?)
  {
    if repoController.selection is StagingSelection {
      (self as! FileListDataSource).reload()
    }
  }
}


/// Methods that a file list data source must implement.
protocol FileListDataSource: AnyObject
{
  func reload()
  func fileChange(at row: Int) -> FileChange?
  func path(for item: Any) -> String
  func change(for item: Any) -> DeltaStatus
}

protocol FileListDelegate: AnyObject
{
  func configure(model: FileListModel)
}


/// Cell view with custom drawing for deleted files.
class FileCellView: NSTableCellView
{
  /// The change is stored to improve drawing of selected deleted files.
  var change: DeltaStatus = .unmodified
  
  override var backgroundStyle: NSView.BackgroundStyle
  {
    didSet
    {
      if backgroundStyle == .dark {
        textField?.textColor = .textColor
      }
      else if change == .deleted {
        textField?.textColor = .disabledControlTextColor
      }
    }
  }
}


/// Cell view with a button rather than an image.
class TableButtonView: NSTableCellView
{
  @IBOutlet var button: NSButton!
}
