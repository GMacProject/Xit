import Foundation

// swiftlint:disable line_length

prefix operator ›

prefix func ›(string: StringLiteralType) -> UIString
{
  return UIString(rawValue: string)
}

struct UIString: RawRepresentable
{
  let rawValue: String
  
  init(rawValue: String)
  {
    self.rawValue = rawValue
  }
  
  init(format: String, _ arguments: CVarArg...)
  {
    self.rawValue = String(format: format, arguments: arguments)
  }
  
  init(error: NSError)
  {
    rawValue = error.localizedDescription
  }
  
  static let emptyString = ›""
  
  static let openPrompt = ›"Open a directory that contains a Git repository"
  static let notARepository = ›"That folder does not contain a Git repository."
  
  static let branchNameInvalid = ›"Not a valid name"
  static let branchNameExists = ›"Branch already exists"
  static let trackingBranchMissing = ›"This branch's remote tracking branch does not exist."
  static let trackingToolTip = ›"The active branch is tracking this remote branch"
  
  // Command titles (menu, button, etc)
  static let add = ›"Add"
  static let apply = ›"Apply"
  static let cancel = ›"Cancel"
  static let clear = ›"Clear"
  static let delete = ›"Delete"
  static let deleteBranch = ›"Delete Branch"
  static let dontReplace = ›"Don't Replace"
  static let discard = ›"Discard"
  static let drop = ›"Drop"
  static let hideSidebar = ›"Hide Sidebar"
  static let ok = ›"OK"
  static let openPrefs = ›"Open Preferences"
  static let pop = ›"Pop"
  static let push = ›"Push"
  static let replace = ›"Replace"
  static let retry = ›"Retry"
  static let revert = ›"Revert"
  static let save = ›"Save"
  static let showSidebar = ›"Show Sidebar"
  static let stage = ›"Stage"
  static let stageAll = ›"Stage All"
  static let staging = ›"Staging"
  static let unstage = ›"Unstage"
  static let unstageAll = ›"Unstage All"

  // Sidebar roots
  static let workspace = ›"Workspace"
  static let branches = ›"Branches"
  static let remotes = ›"Remotes"
  static let tags = ›"Tags"
  static let stashes = ›"Stashes"
  static let submodules = ›"Submodules"

  // File preview strings
  static let binaryFile = ›"This is a binary file"
  static let blameNotAvailable = ›"Blame not available"
  static let cantApplyHunk = ›"This hunk cannot be applied"
  static let files = ›"Files"
  static let multipleItemsSelected = ›"Multiple items selected"
  static let multipleSelection = ›"Multiple selection"
  static let noChanges = ›"No changes for this selection"
  static let none = ›"None"
  static let noSelection = ›"No selection"
  static let noStagedChanges = ›"No staged changes for this selection"
  static let noUnstagedChanges = ›"No unstaged changes for this selection"
  static let parent = ›"Parent:"
  static let parents = ›"Parents:"
  static let replaceMessagePrompt = ›"Replace the commit message?"
  static let replaceMessageInfo = ›"""
      Do you want to replace the commit message with the message from
      the previous commit?
      """
  static let staged = ›"Staged"
  static let whitespaceChangesHidden = ›"Whitespace changes are hidden"

  static let confirmDeleteAccount = ›"Are you sure you want to delete the selected account?"
  static let confirmRevertMultiple = ›"Revert changes to the selected files?"
  
  // Format strings
  static let authorFormat = "%@ (author)"
  static let checkOutFormat = "Check out \"%@\""
  static let committerFormat = "%@ (committer)"
  static let confirmPushFormat = "Push local branch \"%1$@\" to remote \"%2$@\"?"
  static let confirmRevertFormat = "Are you sure you want to revert changes to %@?"
  static let confirmDeleteFormat = "Delete the %1$@ %2$@?"
  static let createTrackingFormat = "Create local branch tracking %@"
  static let mergeFormat = "Merge \"%1$@\" into \"%2$@\""
  static let renamePromptFormat = "Rename branch \"%@\" to:"
  static let trackingMissingInfoFormat = """
      The remote branch may have been merged and deleted. Do you want to \
      clear the tracking branch setting, or delete your local branch "%@"?
      """

  static func author(_ name: String) -> UIString
  {
    return UIString(format: UIString.authorFormat, name)
  }
  static func checkOut(_ branch: String) -> UIString
  {
    return UIString(format: UIString.renamePromptFormat, branch)
  }
  static func committer(_ name: String) -> UIString
  {
    return UIString(format: UIString.committerFormat, name)
  }
  static func confirmPush(localBranch: String, remote: String) -> UIString
  {
    return UIString(format: UIString.confirmPushFormat, localBranch, remote)
  }
  static func confirmRevert(_ name: String) -> UIString
  {
    return UIString(format: UIString.confirmRevertFormat, name)
  }
  static func confirmDelete(kind: String, name: String) -> UIString
  {
    return UIString(format: UIString.confirmDeleteFormat, kind, name)
  }
  static func createTracking(_ remoteBranch: String) -> UIString
  {
    return UIString(format: UIString.createTrackingFormat, remoteBranch)
  }
  static func merge(_ source: String, _ target: String) -> UIString
  {
    return UIString(format: UIString.mergeFormat, source, target)
  }
  static func renamePrompt(_ branch: String) -> UIString
  {
    return UIString(format: UIString.renamePromptFormat, branch)
  }
  static func trackingMissingInfo(_ branch: String) -> UIString
  {
    return UIString(format: UIString.trackingMissingInfoFormat, branch)
  }

  static let newFileDeleted = ›"The new file will be deleted."
  
  static let noStashes = ›"Repository has no stashes."
  static let checkoutFailedConflict = ›"Checkout failed because of a conflict with local changes."
  static let checkoutFailedConflictInfo = ›"Revert or stash your changes and try again."
  static let confirmPop = ›"Apply the most recent stash, and then delete it?"
  static let confirmApply = ›"Apply the most recent stash, without deleting it?"
  static let confirmStashDelete = ›"Delete the most recent stash?"
  
  static let keychainInvalidURL = ›"""
      The password could not be saved to the keychain because \
      the URL is not valid.
      """
  static let keychainError = ›"""
      The password could not be saved to the keychain because \
      an unexpected error occurred.
      """
  
  // Keychain errors
  static let cantSavePassword = ›"The password could not be saved."
  static let invalidName = ›"The name is not valid."
  static let invalidURL = ›"The URL is not valid."
  static let unexpectedError = ›"An unexpected error occurred."
  
  // Services
  static let prActionFailed = ›"Pull request action failed."
  
  static let authFailedTemplate = "Signing in to the %1$@ account %2$@ failed."
  static let buildStatusTemplate = "Builds for %@"
  
  static func authFailed(service: String, account: String) -> UIString
  {
    return UIString(format: UIString.authFailedTemplate, service, account)
  }
  static func buildStatus(_ branch: String) -> UIString
  {
    return UIString(format: UIString.buildStatusTemplate, branch)
  }
  
  // Pull request status
  static let approved = ›"Approved"
  static let needsWork = ›"Needs work"
  static let merged = ›"Merged"
  static let closed = ›"Closed"
}

extension NSAlert
{
  var messageString: UIString
  {
    get { return UIString(rawValue: messageText) }
    set { messageText = newValue.rawValue }
  }
  var informativeString: UIString
  {
    get { return UIString(rawValue: informativeText) }
    set { informativeText = newValue.rawValue }
  }
  
  func addButton(withString title: UIString)
  {
    addButton(withTitle: title.rawValue)
  }
}

extension NSButton
{
  var titleString: UIString
  {
    get { return UIString(rawValue: title) }
    set { title = newValue.rawValue }
  }
}

extension NSControl
{
  var uiStringValue: UIString
  {
    get { return UIString(rawValue: stringValue) }
    set { stringValue = newValue.rawValue }
  }
}

extension NSMenuItem
{
  var titleString: UIString
  {
    get { return UIString(rawValue: title) }
    set { title = newValue.rawValue }
  }
}

extension NSPathComponentCell
{
  var titleString: UIString
  {
    get { return UIString(rawValue: title) }
    set { title = newValue.rawValue }
  }
}

extension NSSavePanel
{
  var messageString: UIString
  {
    get { return UIString(rawValue: message) }
    set { message = newValue.rawValue }
  }
  var promptString: UIString
  {
    get { return UIString(rawValue: prompt) }
    set { prompt = newValue.rawValue }
  }
}

extension NSTextField
{
  convenience init(labelWithUIString uiString: UIString)
  {
    self.init(labelWithString: uiString.rawValue)
  }
}
