import Foundation


enum PreferenceKeys
{
  static let deemphasizeMerges = "deemphasizeMerges"
  static let collapseHistory = "collapseHistory"
  static let statusInTabs = "statusInTabs"
}

enum StatusInTabs: Int
{
  case multipleOnly
  case never
  case always
}

extension UserDefaults
{
  @objc dynamic var collapseHistory: Bool
  {
    get
    {
      return bool(forKey: PreferenceKeys.collapseHistory)
    }
    set
    {
      set(newValue, forKey: PreferenceKeys.collapseHistory)
    }
  }
  @objc dynamic var deemphasizeMerges: Bool
  {
    get
    {
      return bool(forKey: PreferenceKeys.deemphasizeMerges)
    }
    set
    {
      set(newValue, forKey: PreferenceKeys.deemphasizeMerges)
    }
  }
  var statusInTabs: StatusInTabs
  {
    get
    {
      return StatusInTabs(rawValue: integer(forKey: PreferenceKeys.statusInTabs))
             ?? .multipleOnly
    }
    set
    {
      set(newValue.rawValue, forKey: PreferenceKeys.statusInTabs)
    }
  }
}
