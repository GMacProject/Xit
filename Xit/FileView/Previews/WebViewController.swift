import Cocoa
import WebKit

protocol WebActionDelegateHost
{
  var webActionDelegate: Any { get }
}

class WebViewController: NSViewController
{
  @IBOutlet weak var webView: WebView!
  var savedTabWidth: UInt?
  var savedWrapping: TextWrapping?
  var fontObserver: NSObjectProtocol?
  private var appearanceObserver: NSKeyValueObservation?
  
  enum Default
  {
    static var tabWidth: UInt
    { return PreviewsPrefsController.Default.tabWidth() }
  }
  
  static let baseURL = Bundle.main.url(forResource: "html", withExtension: nil)!
  
  static func htmlTemplate(_ name: String) -> String
  {
    guard let htmlURL = Bundle.main.url(forResource: name, withExtension: "html",
                                        subdirectory: "html")
    else { return "" }
    
    return (try? String(contentsOf: htmlURL)) ?? ""
  }
  
  override func awakeFromNib()
  {
    webView.setValue(false, forKey: "drawsBackground")
    fontObserver = NotificationCenter.default.addObserver(forName: .XTFontChanged,
                                                          object: nil,
                                                          queue: .main) {
      [weak self] (_) in
      self?.updateFont()
    }
  }
  
  override func viewDidAppear()
  {
    super.viewDidAppear()
    if appearanceObserver == nil {
      appearanceObserver = webView.observe(\.effectiveAppearance) {
        [weak self] (_, _) in
        self?.updateColors()
      }
    }
  }
  
  deinit
  {
    webView.uiDelegate = nil
    webView.frameLoadDelegate = nil
  }
  
  func updateFont()
  {
    let font = PreviewsPrefsController.Default.font()
    
    webView?.preferences.standardFontFamily = font.familyName
    webView?.preferences.defaultFontSize = Int32(font.pointSize)
    webView?.preferences.defaultFixedFontSize = Int32(font.pointSize)
  }
  
  public func load(html: String, baseURL: URL = WebViewController.baseURL)
  {
    if let webView = self.webView {
      Thread.performOnMainThread {
        webView.mainFrame.loadHTMLString(html, baseURL: baseURL)
      }
    }
  }
  
  public func loadNotice(_ text: UIString)
  {
    let template = WebViewController.htmlTemplate("notice")
    let escapedText = text.rawValue.xmlEscaped
    let html = String(format: template, escapedText)
    
    load(html: html)
  }
  
  func setDefaultTabWidth()
  {
    let defaultWidth = UInt(UserDefaults.standard.integer(forKey: "tabWidth"))
    
    tabWidth = (defaultWidth == 0) ? Default.tabWidth : defaultWidth
  }
  
  func wrappingWidthAdjustment() -> Int { return 0 }
  
  func updateColors()
  {
    let savedAppearance = NSAppearance.current
    
    defer {
      NSAppearance.current = savedAppearance
    }
    NSAppearance.current = view.effectiveAppearance
    
    let names = [
          "addBackground",
          "blameBorder",
          "blameStart",
          "buttonActiveBorder",
          "buttonActiveGrad1",
          "buttonActiveGrad2",
          "buttonBorder",
          "buttonGrad1",
          "buttonGrad2",
          "deleteBackground",
          "divider",
          "heading",
          "hunkBottomBorder",
          "hunkTopBorder",
          "jumpActive",
          "jumpHoverBackground",
          "leftBackground",
          "shadow",
          ]
    
    setColor(name: "textColor", color: .textColor)
    setColor(name: "textBackground", color: .textBackgroundColor)
    setColor(name: "underPageBackgroundColor", color: .underPageBackgroundColor)
    for name in names {
      if let color = NSColor(named: name) {
        setColor(name: name, color: color)
      }
    }
  }
  
  func setColor(name: String, color: NSColor)
  {
    let cssColor = color.cssRGB
    
    _ = webView.stringByEvaluatingJavaScript(from: """
          document.documentElement.style.setProperty("--\(name)", "\(cssColor)")
          """)
  }
}

extension WebViewController: TabWidthVariable
{
  var tabWidth: UInt
  {
    get
    {
      guard let style = webView?.mainFrameDocument.body.style,
            let tabSizeString = style.getPropertyValue("tab-size"),
            let tabSize = UInt(tabSizeString)
      else { return Default.tabWidth }
      
      return tabSize
    }
    set
    {
      guard let style = webView?.mainFrameDocument.body.style
      else { return }
      
      style.setProperty("tab-size", value: "\(newValue)", priority: "important")
      savedTabWidth = newValue
    }
  }
}

extension TextWrapping
{
  var cssValue: String
  {
    switch self {
      case .none: return "pre"
      default: return "pre-wrap"
    }
  }
}

extension WebViewController: WrappingVariable
{
  public var wrapping: TextWrapping
  {
    get
    {
      return savedWrapping ?? .windowWidth
    }
    set
    {
      guard let style = webView?.mainFrameDocument.body.style
      else { return }
      var wrapWidth = "100%"
      
      style.setProperty("--wrapping", value: "\(newValue.cssValue)",
                        priority: "important")
      switch newValue {
        case .columns(let columns):
          wrapWidth = "\(columns+wrappingWidthAdjustment())ch"
        default:
          break
      }
      style.setProperty("--wrapwidth", value: wrapWidth, priority: "important")
      savedWrapping = newValue
    }
  }
}

extension WebViewController: WebFrameLoadDelegate
{
  func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!)
  {
    if let scrollView = sender.mainFrame.frameView.documentView
                        .enclosingScrollView {
      scrollView.hasHorizontalScroller = false
      scrollView.horizontalScrollElasticity = .none
      scrollView.backgroundColor = NSColor(deviceWhite: 0.8, alpha: 1.0)
    }
    
    if let webActionDelegate = (self as? WebActionDelegateHost)?
                               .webActionDelegate {
      sender.windowScriptObject.setValue(webActionDelegate,
                                         forKey: "webActionDelegate")
    }
    
    if let savedTabWidth = self.savedTabWidth {
      tabWidth = savedTabWidth
    }
    else {
      setDefaultTabWidth()
    }
    wrapping = savedWrapping ?? PreviewsPrefsController.Default.wrapping()
    updateFont()
    updateColors()
  }
}

let WebMenuItemTagInspectElement = 2024

extension WebViewController: WebUIDelegate
{
  static let allowedCMTags = [
      WebMenuItemTagCopy,
      WebMenuItemTagCut,
      WebMenuItemTagPaste,
      WebMenuItemTagOther,
      WebMenuItemTagSearchInSpotlight,
      WebMenuItemTagSearchWeb,
      WebMenuItemTagLookUpInDictionary,
      WebMenuItemTagOpenWithDefaultApplication,
      WebMenuItemTagInspectElement,
      ]
  
  func webView(_ sender: WebView!,
               contextMenuItemsForElement element: [AnyHashable: Any]!,
               defaultMenuItems: [Any]!) -> [Any]!
  {
    return defaultMenuItems.compactMap {
      (item) in
      guard let menuItem = item as? NSMenuItem
      else { return nil }
      
      return WebViewController.allowedCMTags.contains(menuItem.tag) ? item : nil
    }
  }
  
  func webView(_ webView: WebView!,
               dragDestinationActionMaskFor draggingInfo: NSDraggingInfo!) -> Int
  {
    return 0
  }
}
