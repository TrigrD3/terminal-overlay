import Cocoa
import Darwin

struct EnvironmentGifs: Codable {
    var dev: String? = nil
    var staging: String? = nil
    var prod: String? = nil
}

struct K8sMatches: Codable {
    var dev: String = "minikube"
    var staging: String = "staging"
    var prod: String = "prod"
}

struct TabConfiguration: Codable {
    var env: String = "auto" // "auto", "dev", "staging", "prod"
    var size: Double = 120
}

struct ConfigStore: Codable {
    var tabs: [String: TabConfiguration] = ["default": TabConfiguration()]
    var gifs: EnvironmentGifs = EnvironmentGifs()
    var k8s: K8sMatches = K8sMatches()
}

func getExecutablePath() -> String {
    if let path = Bundle.main.executablePath {
        return path
    }
    let arg0 = CommandLine.arguments[0]
    if arg0.hasPrefix("/") {
        return arg0
    }
    if arg0.contains("/") {
        return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(arg0)
    }
    if let pathVar = ProcessInfo.processInfo.environment["PATH"] {
        let paths = pathVar.components(separatedBy: ":")
        for p in paths {
            let fullPath = (p as NSString).appendingPathComponent(arg0)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
    }
    return arg0
}

func getAppConfigDirectory() -> String {
    let homeDir = NSHomeDirectory()
    let configDir = (homeDir as NSString).appendingPathComponent(".config/terminal-overlay")
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: configDir) {
        try? fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
    }
    return configDir
}

func copyDefaultGifsIfEmpty(targetGifsDir: String) {
    let fileManager = FileManager.default
    
    var hasGifs = false
    if let files = try? fileManager.contentsOfDirectory(atPath: targetGifsDir) {
        for file in files {
            if file.lowercased().hasSuffix(".gif") {
                hasGifs = true
                break
            }
        }
    }
    
    if hasGifs {
        return
    }
    
    let exePath = getExecutablePath()
    let exeDir = (exePath as NSString).deletingLastPathComponent
    let shareDir = (exeDir as NSString).appendingPathComponent("../share/terminal-overlay/gifs")
    
    var sourceGifsDir = shareDir
    if !fileManager.fileExists(atPath: sourceGifsDir) {
        sourceGifsDir = "gifs"
    }
    
    guard fileManager.fileExists(atPath: sourceGifsDir) else {
        return
    }
    
    if let files = try? fileManager.contentsOfDirectory(atPath: sourceGifsDir) {
        for file in files {
            if file.lowercased().hasSuffix(".gif") {
                let sourceFile = (sourceGifsDir as NSString).appendingPathComponent(file)
                let destFile = (targetGifsDir as NSString).appendingPathComponent(file)
                if !fileManager.fileExists(atPath: destFile) {
                    try? fileManager.copyItem(atPath: sourceFile, toPath: destFile)
                }
            }
        }
    }
}

func getAppGifsDirectory() -> String {
    let configDir = getAppConfigDirectory()
    let gifsDir = (configDir as NSString).appendingPathComponent("gifs")
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: gifsDir) {
        try? fileManager.createDirectory(atPath: gifsDir, withIntermediateDirectories: true, attributes: nil)
    }
    copyDefaultGifsIfEmpty(targetGifsDir: gifsDir)
    return gifsDir
}

func getAppConfigPath() -> String {
    let configDir = getAppConfigDirectory()
    return (configDir as NSString).appendingPathComponent("config.json")
}

func getAppPidPath() -> String {
    let configDir = getAppConfigDirectory()
    return (configDir as NSString).appendingPathComponent("terminal_overlay.pid")
}

func resolveGifPath(_ path: String) -> String? {
    if path == "none" || path == "null" || path == "" {
        return nil
    }
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.contains("/") {
        return expanded
    } else {
        return (getAppGifsDirectory() as NSString).appendingPathComponent(expanded)
    }
}

func loadConfigStore() -> ConfigStore {
    let configFile = getAppConfigPath()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)) else {
        return ConfigStore()
    }
    return (try? JSONDecoder().decode(ConfigStore.self, from: data)) ?? ConfigStore()
}

func saveConfigStore(_ store: ConfigStore) {
    let configFile = getAppConfigPath()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(store) {
        try? data.write(to: URL(fileURLWithPath: configFile))
    }
}

func getCurrentTTY() -> String {
    if let ttyPath = ttyname(STDIN_FILENO) {
        let path = String(cString: ttyPath)
        return (path as NSString).lastPathComponent
    }
    return "default"
}

func getAvailableGIFs() -> [String] {
    let gifsDir = getAppGifsDirectory()
    var list = ["None (Built-in mascot)"]
    let fileManager = FileManager.default
    if let files = try? fileManager.contentsOfDirectory(atPath: gifsDir) {
        let sortedFiles = files.sorted()
        for file in sortedFiles {
            if file.lowercased().hasSuffix(".gif") {
                list.append(file)
            }
        }
    }
    return list
}

func getK8sCurrentContext() -> String? {
    let kubeConfigPath = ("~/.kube/config" as NSString).expandingTildeInPath
    guard let content = try? String(contentsOfFile: kubeConfigPath, encoding: .utf8) else {
        return nil
    }
    
    let lines = content.components(separatedBy: .newlines)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("current-context:") {
            let parts = trimmed.components(separatedBy: ":")
            if parts.count >= 2 {
                return parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    return nil
}

class InteractiveContainerView: NSView {
    override func rightMouseDown(with event: NSEvent) {
        NSApplication.shared.terminate(self)
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            NSApplication.shared.terminate(self)
        } else {
            // Pass standard clicks to window drag handler
            super.mouseDown(with: event)
        }
    }
}

class OverlayWindowDelegate: NSObject, NSWindowDelegate {
    weak var parent: OverlayApplicationDelegate?
    
    init(parent: OverlayApplicationDelegate) {
        self.parent = parent
    }
    
    func windowDidMove(_ notification: Notification) {
        parent?.updateOffsets()
    }
}

class OverlayApplicationDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel!
    var windowDelegate: OverlayWindowDelegate!
    var gifPath: String?
    var env: String = "dev"
    var windowSize: CGFloat = 120
    
    var offsetX: CGFloat = 130 // Default: windowSize + 10px padding
    var offsetY: CGFloat = 80  // Default: 80px down from top to clear window title & tab bar
    var isUpdatingFromTimer = false
    var trackingTimer: Timer?
    var configTimer: Timer?
    
    var currentActiveTTY: String = "default"
    var lastFileModificationDate: Date?
    var lastKubeConfigModificationDate: Date?

    func getTerminalWindowBounds() -> NSRect? {
        let terminalApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal")
        guard let terminalApp = terminalApps.first else { return nil }
        let pid = terminalApp.processIdentifier
        
        let options = CGWindowListOption.optionOnScreenOnly
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            return NSRect(origin: rect.origin, size: rect.size)
        }
        return nil
    }
    
    func getActiveTabTTY() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"Terminal\" to get tty of selected tab of front window"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return (output as NSString).lastPathComponent
            }
        } catch {}
        return nil
    }

    func updateOffsets() {
        if isUpdatingFromTimer { return }
        
        guard let termBounds = getTerminalWindowBounds() else { return }
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenHeight = screenFrame.height
        
        let right = termBounds.origin.x + termBounds.size.width
        let overlayX = window.frame.origin.x
        let overlayAppleScriptY = screenHeight - window.frame.origin.y - windowSize
        
        offsetX = right - overlayX
        offsetY = overlayAppleScriptY - termBounds.origin.y
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenHeight = screenFrame.height
        
        // Initial positioning
        var rect = NSRect(
            x: screenFrame.width - windowSize - 40,
            y: screenFrame.height - windowSize - 80,
            width: windowSize,
            height: windowSize
        )
        
        if let termBounds = getTerminalWindowBounds() {
            let left = termBounds.origin.x
            let top = termBounds.origin.y
            let width = termBounds.size.width
            let right = left + width
            
            offsetX = windowSize + 10
            offsetY = 80 // Push down by 80px to bypass terminal tab bar
            
            let overlayX = right - offsetX
            let overlayAppleScriptY = top + offsetY
            let overlayY = screenHeight - overlayAppleScriptY - windowSize
            
            rect = NSRect(x: overlayX, y: overlayY, width: windowSize, height: windowSize)
        }
        
        window = NSPanel(
            contentRect: rect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.isFloatingPanel = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        
        windowDelegate = OverlayWindowDelegate(parent: self)
        window.delegate = windowDelegate
        
        // Load initial active TTY and apply its settings
        if let activeTTY = getActiveTabTTY() {
            currentActiveTTY = activeTTY
        }
        let store = loadConfigStore()
        let tabConfig = store.tabs[currentActiveTTY] ?? store.tabs["default"] ?? TabConfiguration()
        applyConfig(tabConfig: tabConfig, gifs: store.gifs, k8s: store.k8s)
        
        // Poll for window bounds tracking (50Hz)
        trackingTimer = Timer.scheduledTimer(timeInterval: 0.02, target: self, selector: #selector(trackTerminalWindow), userInfo: nil, repeats: true)
        
        // Poll for active tab switching, config changes, and k8s updates (5Hz)
        configTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(checkConfigAndTabUpdates), userInfo: nil, repeats: true)
        
        trackTerminalWindow()
    }
    
    @objc func checkConfigAndTabUpdates() {
        var needsUpdate = false
        
        if let activeTTY = getActiveTabTTY() {
            if activeTTY != currentActiveTTY {
                currentActiveTTY = activeTTY
                needsUpdate = true
            }
        }
        
        let configFile = getAppConfigPath()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: configFile),
           let modificationDate = attributes[.modificationDate] as? Date {
            if lastFileModificationDate == nil || modificationDate > lastFileModificationDate! {
                lastFileModificationDate = modificationDate
                needsUpdate = true
            }
        }
        
        let kubeConfigFile = ("~/.kube/config" as NSString).expandingTildeInPath
        if let attributes = try? FileManager.default.attributesOfItem(atPath: kubeConfigFile),
           let modificationDate = attributes[.modificationDate] as? Date {
            if lastKubeConfigModificationDate == nil || modificationDate > lastKubeConfigModificationDate! {
                lastKubeConfigModificationDate = modificationDate
                needsUpdate = true
            }
        }
        
        if needsUpdate {
            let store = loadConfigStore()
            let tabConfig = store.tabs[currentActiveTTY] ?? store.tabs["default"] ?? TabConfiguration()
            applyConfig(tabConfig: tabConfig, gifs: store.gifs, k8s: store.k8s)
        }
    }
    
    func applyConfig(tabConfig: TabConfiguration, gifs: EnvironmentGifs, k8s: K8sMatches) {
        self.windowSize = CGFloat(tabConfig.size)
        
        // Handle Auto (K8s) detection
        if tabConfig.env == "auto" {
            var detected = "dev"
            if let context = getK8sCurrentContext() {
                let lowercasedContext = context.lowercased()
                if !k8s.prod.isEmpty && lowercasedContext.contains(k8s.prod.lowercased()) {
                    detected = "prod"
                } else if !k8s.staging.isEmpty && lowercasedContext.contains(k8s.staging.lowercased()) {
                    detected = "staging"
                } else if !k8s.dev.isEmpty && lowercasedContext.contains(k8s.dev.lowercased()) {
                    detected = "dev"
                }
            }
            self.env = detected
        } else {
            self.env = tabConfig.env
        }
        
        // Map the GIF depending on the active environment
        if env == "prod" {
            self.gifPath = gifs.prod
        } else if env == "staging" {
            self.gifPath = gifs.staging
        } else {
            self.gifPath = gifs.dev
        }
        
        // Re-align bounds with the new size
        let termBounds = getTerminalWindowBounds()
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenHeight = screenFrame.height
        
        let targetX: CGFloat
        let targetY: CGFloat
        
        if let bounds = termBounds {
            let right = bounds.origin.x + bounds.size.width
            targetX = right - windowSize - 10
            let overlayAppleScriptY = bounds.origin.y + 80 // Shift down to bypass tab bar
            targetY = screenHeight - overlayAppleScriptY - windowSize
            
            offsetX = windowSize + 10
            offsetY = 80
        } else {
            targetX = window.frame.origin.x
            targetY = window.frame.origin.y
        }
        
        window.setFrame(NSRect(x: targetX, y: targetY, width: windowSize, height: windowSize), display: true)
        
        let containerView = InteractiveContainerView(frame: NSRect(x: 0, y: 0, width: windowSize, height: windowSize))
        if let path = gifPath, FileManager.default.fileExists(atPath: path) {
            let imageView = NSImageView(frame: containerView.bounds)
            if let image = NSImage(contentsOfFile: path) {
                imageView.image = image
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.animates = true
                containerView.addSubview(imageView)
            }
        } else {
            let overlayView = BuiltInOverlayView(frame: containerView.bounds, env: env)
            containerView.addSubview(overlayView)
        }
        window.contentView = containerView
    }
    
    @objc func trackTerminalWindow() {
        let terminalAppId = "com.apple.Terminal"
        let activeApp = NSWorkspace.shared.frontmostApplication
        let myPid = NSRunningApplication.current.processIdentifier
        
        let isTerminalActive = (activeApp?.bundleIdentifier == terminalAppId)
        let isOverlayActive = (activeApp?.processIdentifier == myPid)
        
        if isTerminalActive || isOverlayActive {
            if let termBounds = getTerminalWindowBounds() {
                let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let screenHeight = screenFrame.height
                
                let right = termBounds.origin.x + termBounds.size.width
                let overlayX = right - offsetX
                let overlayAppleScriptY = termBounds.origin.y + offsetY
                let overlayY = screenHeight - overlayAppleScriptY - windowSize
                
                let newOrigin = NSPoint(x: overlayX, y: overlayY)
                if window.frame.origin != newOrigin {
                    isUpdatingFromTimer = true
                    window.setFrameOrigin(newOrigin)
                    isUpdatingFromTimer = false
                }
                
                if !window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        } else {
            if window.isVisible {
                window.orderOut(nil)
            }
        }
    }
}

class BuiltInOverlayView: NSView {
    var env: String
    var timer: Timer?
    var frameCount = 0
    
    init(frame frameRect: NSRect, env: String) {
        self.env = env
        super.init(frame: frameRect)
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.frameCount += 1
            self?.needsDisplay = true
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let size = bounds.width
        let cycle = frameCount % 30
        
        var breathH: CGFloat = 0
        var breathW: CGFloat = 0
        if cycle < 15 {
            breathH = CGFloat(cycle) * 0.4
            breathW = -CGFloat(cycle) * 0.2
        } else {
            breathH = CGFloat(30 - cycle) * 0.4
            breathW = -CGFloat(30 - cycle) * 0.2
        }
        
        let overlayColor: NSColor
        let eyeColor = NSColor(red: 47/255, green: 53/255, blue: 66/255, alpha: 1.0)
        let accColor: NSColor
        
        if env == "prod" {
            overlayColor = NSColor(red: 255/255, green: 71/255, blue: 87/255, alpha: 1.0)
            accColor = NSColor(red: 255/255, green: 165/255, blue: 2/255, alpha: 1.0)
        } else if env == "staging" {
            overlayColor = NSColor(red: 46/255, green: 213/255, blue: 115/255, alpha: 1.0)
            accColor = NSColor(red: 255/255, green: 107/255, blue: 129/255, alpha: 1.0)
        } else {
            overlayColor = NSColor(red: 30/255, green: 144/255, blue: 255/255, alpha: 1.0)
            accColor = NSColor(red: 255/255, green: 127/255, blue: 80/255, alpha: 1.0)
        }
        
        let shadowWidth = 60 - breathW
        let shadowPath = NSBezierPath(ovalIn: NSRect(
            x: size/2 - shadowWidth/2,
            y: 5,
            width: shadowWidth,
            height: 10
        ))
        NSColor(white: 0.8, alpha: 0.5).set()
        shadowPath.fill()
        
        let bodyRect = NSRect(
            x: 20 - breathW,
            y: 10,
            width: size - 40 + (breathW * 2),
            height: size - 30 + breathH
        )
        let bodyPath = NSBezierPath(ovalIn: bodyRect)
        overlayColor.set()
        bodyPath.fill()
        
        let eyeY = bodyRect.minY + bodyRect.height * 0.55
        
        if env == "prod" {
            let leftEye = NSBezierPath()
            leftEye.move(to: NSPoint(x: size/2 - 25, y: eyeY + 5))
            leftEye.line(to: NSPoint(x: size/2 - 13, y: eyeY - 2))
            eyeColor.setStroke()
            leftEye.lineWidth = 3
            leftEye.stroke()
            
            let rightEye = NSBezierPath()
            rightEye.move(to: NSPoint(x: size/2 + 13, y: eyeY - 2))
            rightEye.line(to: NSPoint(x: size/2 + 25, y: eyeY + 5))
            rightEye.lineWidth = 3
            rightEye.stroke()
            
            let lightCycle = (frameCount / 3) % 2
            let lightColor = lightCycle == 0 ? overlayColor : NSColor.yellow
            
            let wire = NSBezierPath()
            wire.move(to: NSPoint(x: size/2, y: bodyRect.maxY))
            wire.line(to: NSPoint(x: size/2, y: bodyRect.maxY + 8))
            NSColor.darkGray.setStroke()
            wire.lineWidth = 2
            wire.stroke()
            
            let light = NSBezierPath(ovalIn: NSRect(x: size/2 - 5, y: bodyRect.maxY + 6, width: 10, height: 10))
            lightColor.set()
            light.fill()
        } else if env == "staging" {
            let leftEye = NSBezierPath()
            leftEye.appendArc(withCenter: NSPoint(x: size/2 - 18, y: eyeY + 2), radius: 6, startAngle: 0, endAngle: 180)
            eyeColor.setStroke()
            leftEye.lineWidth = 2.5
            leftEye.stroke()
            
            let rightEye = NSBezierPath()
            rightEye.appendArc(withCenter: NSPoint(x: size/2 + 18, y: eyeY + 2), radius: 6, startAngle: 0, endAngle: 180)
            rightEye.lineWidth = 2.5
            rightEye.stroke()
            
            let leftCheek = NSBezierPath(ovalIn: NSRect(x: size/2 - 27, y: eyeY - 8, width: 8, height: 6))
            accColor.set()
            leftCheek.fill()
            
            let rightCheek = NSBezierPath(ovalIn: NSRect(x: size/2 + 19, y: eyeY - 8, width: 8, height: 6))
            rightCheek.fill()
            
            let zOffset = CGFloat(frameCount % 20) * 1.5
            let zSize: CGFloat = 8
            let zRect = NSRect(
                x: size/2 + 20 + zOffset * 0.2,
                y: bodyRect.maxY - 10 + zOffset,
                width: zSize,
                height: zSize
            )
            let zPath = NSBezierPath()
            zPath.move(to: NSPoint(x: zRect.minX, y: zRect.maxY))
            zPath.line(to: NSPoint(x: zRect.maxX, y: zRect.maxY))
            zPath.line(to: NSPoint(x: zRect.minX, y: zRect.minY))
            zPath.line(to: NSPoint(x: zRect.maxX, y: zRect.minY))
            NSColor.gray.setStroke()
            zPath.lineWidth = 1.5
            zPath.stroke()
        } else {
            let blink = cycle > 26
            if blink {
                let leftEye = NSBezierPath()
                leftEye.move(to: NSPoint(x: size/2 - 22, y: eyeY + 4))
                leftEye.line(to: NSPoint(x: size/2 - 14, y: eyeY + 4))
                eyeColor.setStroke()
                leftEye.lineWidth = 3
                leftEye.stroke()
                
                let rightEye = NSBezierPath()
                rightEye.move(to: NSPoint(x: size/2 + 14, y: eyeY + 4))
                rightEye.line(to: NSPoint(x: size/2 + 22, y: eyeY + 4))
                rightEye.lineWidth = 3
                rightEye.stroke()
            } else {
                let leftEye = NSBezierPath(ovalIn: NSRect(x: size/2 - 22, y: eyeY, width: 8, height: 8))
                eyeColor.set()
                leftEye.fill()
                
                let rightEye = NSBezierPath(ovalIn: NSRect(x: size/2 + 14, y: eyeY, width: 8, height: 8))
                rightEye.fill()
            }
            
            let leftCheek = NSBezierPath(ovalIn: NSRect(x: size/2 - 26, y: eyeY - 6, width: 6, height: 4))
            accColor.set()
            leftCheek.fill()
            
            let rightCheek = NSBezierPath(ovalIn: NSRect(x: size/2 + 20, y: eyeY - 6, width: 6, height: 4))
            rightCheek.fill()
        }
        
        if env != "prod" {
            let smilePath = NSBezierPath()
            smilePath.appendArc(withCenter: NSPoint(x: size/2, y: eyeY - 2), radius: 4, startAngle: 180, endAngle: 360)
            eyeColor.setStroke()
            smilePath.lineWidth = 2
            smilePath.stroke()
        }
    }
}

// Quick interactive setup wizard when running config without arguments
func runConfigWizard(tty: String) {
    print("\n\u{001B}[1;36m👾  Terminal Overlay - Quick Configuration Wizard \u{001B}[0m")
    print("Welcome! Let's configure your terminal overlay step-by-step.\n")
    
    var store = loadConfigStore()
    var tabConfig = store.tabs[tty] ?? store.tabs["default"] ?? TabConfiguration()
    
    // 1. Environment Mode
    print("\u{001B}[1;33mStep 1: Select Environment Mode\u{001B}[0m")
    print("  Choose how the overlay detects your environment:")
    print("    - [auto]    Detect environment automatically based on active Kubernetes context")
    print("    - [dev]     Lock to Development mode")
    print("    - [staging] Lock to Staging mode")
    print("    - [prod]    Lock to Production mode")
    print("Enter mode (default: \(tabConfig.env)): ", terminator: "")
    fflush(stdout)
    if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
        let lower = input.lowercased()
        if lower == "auto" || lower == "dev" || lower == "staging" || lower == "prod" {
            tabConfig.env = lower
        } else {
            print("⚠️  Invalid mode. Keeping default: \(tabConfig.env)")
        }
    }
    
    // 2. K8s context match strings (only if env is auto)
    if tabConfig.env == "auto" {
        print("\n\u{001B}[1;33mStep 2: Configure Kubernetes Context Match Substrings\u{001B}[0m")
        print("  If your active kubectl context contains these strings, the overlay switches environment.")
        
        // Dev Match
        print("  - Dev context match string (current: \(store.k8s.dev)): ", terminator: "")
        fflush(stdout)
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
            store.k8s.dev = input
        }
        
        // Staging Match
        print("  - Staging context match string (current: \(store.k8s.staging)): ", terminator: "")
        fflush(stdout)
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
            store.k8s.staging = input
        }
        
        // Prod Match
        print("  - Prod context match string (current: \(store.k8s.prod)): ", terminator: "")
        fflush(stdout)
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
            store.k8s.prod = input
        }
    }
    
    // 3. Overlay Size
    print("\n\u{001B}[1;33mStep 3: Configure Overlay Size\u{001B}[0m")
    print("  Set the size of the overlay window in pixels (50 to 300).")
    print("Enter size (current: \(Int(tabConfig.size))): ", terminator: "")
    fflush(stdout)
    if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
        if let val = Double(input), val >= 50 && val <= 300 {
            tabConfig.size = val
        } else {
            print("⚠️  Invalid size. Keeping default: \(Int(tabConfig.size))")
        }
    }
    
    // 4. Custom GIFs
    print("\n\u{001B}[1;33mStep 4: Configure Environment GIFs\u{001B}[0m")
    print("  Type 'list' to see available GIFs, or type a GIF filename, or 'none' for default mascot.")
    
    let availableGifs = getAvailableGIFs()
    
    func askForGif(envName: String, current: String?) -> String? {
        while true {
            print("  - GIF for \(envName) (current: \(current != nil ? (current! as NSString).lastPathComponent : "none")): ", terminator: "")
            fflush(stdout)
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return current
            }
            if input.isEmpty {
                return current
            }
            if input.lowercased() == "list" {
                print("Available GIFs in folder:")
                for gif in availableGifs {
                    print("  - \(gif)")
                }
                continue
            }
            if input.lowercased() == "none" {
                return nil
            }
            if let resolved = resolveGifPath(input) {
                if FileManager.default.fileExists(atPath: resolved) {
                    return resolved
                } else {
                    print("⚠️  GIF file '\(input)' not found in your gifs directory. Make sure to add it first!")
                    print("  Do you want to use it anyway? (y/N): ", terminator: "")
                    fflush(stdout)
                    if let ans = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), ans == "y" || ans == "yes" {
                        return resolved
                    }
                }
            }
        }
    }
    
    store.gifs.dev = askForGif(envName: "Dev", current: store.gifs.dev)
    store.gifs.staging = askForGif(envName: "Staging", current: store.gifs.staging)
    store.gifs.prod = askForGif(envName: "Prod", current: store.gifs.prod)
    
    // Save
    store.tabs[tty] = tabConfig
    saveConfigStore(store)
    
    print("\n\u{001B}[1;32m✓ Configuration successfully saved to global settings!\u{001B}[0m")
}

// Parse config arguments from CLI command
func parseConfigArgsAndSave(tty: String) {
    var store = loadConfigStore()
    var tabConfig = store.tabs[tty] ?? store.tabs["default"] ?? TabConfiguration()
    let args = CommandLine.arguments
    
    for i in 0..<args.count {
        if args[i] == "--env" && i + 1 < args.count {
            tabConfig.env = args[i+1]
        } else if args[i] == "--size" && i + 1 < args.count {
            if let val = Double(args[i+1]) {
                tabConfig.size = val
            }
        } else if args[i] == "--dev-gif" && i + 1 < args.count {
            store.gifs.dev = resolveGifPath(args[i+1])
        } else if args[i] == "--staging-gif" && i + 1 < args.count {
            store.gifs.staging = resolveGifPath(args[i+1])
        } else if args[i] == "--prod-gif" && i + 1 < args.count {
            store.gifs.prod = resolveGifPath(args[i+1])
        } else if args[i] == "--dev-k8s" && i + 1 < args.count {
            store.k8s.dev = args[i+1]
        } else if args[i] == "--staging-k8s" && i + 1 < args.count {
            store.k8s.staging = args[i+1]
        } else if args[i] == "--prod-k8s" && i + 1 < args.count {
            store.k8s.prod = args[i+1]
        }
    }
    
    store.tabs[tty] = tabConfig
    saveConfigStore(store)
}

func startOverlayDaemon() {
    let pidFile = getAppPidPath()
    if FileManager.default.fileExists(atPath: pidFile),
       let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(pidString) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", String(pid)]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            print("Terminal overlay is already running (PID \(pid))")
            return
        }
    }
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["start", "--daemon"]
    
    do {
        try process.run()
        let pid = process.processIdentifier
        try String(pid).write(toFile: pidFile, atomically: true, encoding: .utf8)
        print("Started terminal overlay in the background (PID \(pid))")
    } catch {
        print("Failed to start terminal overlay in background: \(error)")
    }
}

func stopOverlay() {
    let pidFile = getAppPidPath()
    if FileManager.default.fileExists(atPath: pidFile) {
        if let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidString) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/kill")
            process.arguments = [String(pid)]
            try? process.run()
            process.waitUntilExit()
            print("Stopped terminal overlay (PID \(pid))")
        }
        try? FileManager.default.removeItem(atPath: pidFile)
    } else {
        print("No terminal overlay is currently running.")
    }
}

func printStatus(tty: String) {
    let pidFile = getAppPidPath()
    var isRunning = false
    var pidVal: Int32 = 0
    if FileManager.default.fileExists(atPath: pidFile),
       let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(pidString) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", String(pid)]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            isRunning = true
            pidVal = pid
        }
    }
    
    print("--- Terminal Overlay CLI ---")
    if isRunning {
        print("Status: RUNNING (PID \(pidVal))")
    } else {
        print("Status: STOPPED")
    }
    
    let store = loadConfigStore()
    let tabConfig = store.tabs[tty] ?? store.tabs["default"] ?? TabConfiguration()
    let currentK8s = getK8sCurrentContext() ?? "None"
    
    // Resolve auto environment
    var resolvedEnv = tabConfig.env
    if tabConfig.env == "auto" {
        resolvedEnv = "dev (default)"
        let lowercasedContext = currentK8s.lowercased()
        if !store.k8s.prod.isEmpty && lowercasedContext.contains(store.k8s.prod.lowercased()) {
            resolvedEnv = "prod (matched: \(store.k8s.prod))"
        } else if !store.k8s.staging.isEmpty && lowercasedContext.contains(store.k8s.staging.lowercased()) {
            resolvedEnv = "staging (matched: \(store.k8s.staging))"
        } else if !store.k8s.dev.isEmpty && lowercasedContext.contains(store.k8s.dev.lowercased()) {
            resolvedEnv = "dev (matched: \(store.k8s.dev))"
        }
    }
    
    print("Active Configuration (Tab: \(tty)):")
    print("  Environment Mode: \(tabConfig.env)")
    print("  Resolved Env:     \(resolvedEnv)")
    print("  Active Context:   \(currentK8s)")
    print("  Size:             \(Int(tabConfig.size))px")
    print("K8s Environment Matches:")
    print("  Dev Match:        \(store.k8s.dev)")
    print("  Staging Match:    \(store.k8s.staging)")
    print("  Prod Match:       \(store.k8s.prod)")
    print("Global Environment GIFs:")
    print("  Dev GIF:          \(store.gifs.dev ?? "Built-in Mascot (Blue)")")
    print("  Staging GIF:      \(store.gifs.staging ?? "Built-in Mascot (Green)")")
    print("  Prod GIF:         \(store.gifs.prod ?? "Built-in Mascot (Red)")")
}

func addGif(source: String) {
    let fileManager = FileManager.default
    let gifsDir = getAppGifsDirectory()
    
    if source.lowercased().hasPrefix("http://") || source.lowercased().hasPrefix("https://") {
        guard let url = URL(string: source) else {
            print("Error: Invalid URL.")
            return
        }
        
        let filename = url.lastPathComponent.lowercased().hasSuffix(".gif") ? url.lastPathComponent : "downloaded.gif"
        let destPath = (gifsDir as NSString).appendingPathComponent(filename)
        
        print("Downloading \(url)...")
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error? = nil
        
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                downloadError = error
            } else if let localURL = localURL {
                do {
                    if fileManager.fileExists(atPath: destPath) {
                        try fileManager.removeItem(atPath: destPath)
                    }
                    try fileManager.moveItem(at: localURL, to: URL(fileURLWithPath: destPath))
                } catch {
                    downloadError = error
                }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        if let error = downloadError {
            print("Error downloading GIF: \(error.localizedDescription)")
        } else {
            print("Successfully added GIF: \(filename)")
            print("Path: \(destPath)")
        }
    } else {
        let sourcePath = (source as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: sourcePath) else {
            print("Error: Source file does not exist at \(sourcePath)")
            return
        }
        
        let filename = (sourcePath as NSString).lastPathComponent
        guard filename.lowercased().hasSuffix(".gif") else {
            print("Error: Source file must have a .gif extension.")
            return
        }
        
        let destPath = (gifsDir as NSString).appendingPathComponent(filename)
        do {
            if fileManager.fileExists(atPath: destPath) {
                try fileManager.removeItem(atPath: destPath)
            }
            try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
            print("Successfully added GIF: \(filename)")
            print("Path: \(destPath)")
        } catch {
            print("Error copying GIF: \(error.localizedDescription)")
        }
    }
}

func listGifs() {
    let gifs = getAvailableGIFs()
    print("Available GIFs:")
    for gif in gifs {
        if gif == "None (Built-in mascot)" {
            print("  - \(gif) (default)")
        } else {
            print("  - \(gif)")
        }
    }
}

func removeGif(name: String) {
    let fileManager = FileManager.default
    let gifsDir = getAppGifsDirectory()
    let filename = name.lowercased().hasSuffix(".gif") ? name : "\(name).gif"
    let targetPath = (gifsDir as NSString).appendingPathComponent(filename)
    
    guard fileManager.fileExists(atPath: targetPath) else {
        print("Error: GIF '\(filename)' does not exist.")
        return
    }
    
    do {
        try fileManager.removeItem(atPath: targetPath)
        print("Successfully removed GIF: \(filename)")
    } catch {
        print("Error removing GIF: \(error.localizedDescription)")
    }
}

func printGifUsage() {
    print("""
    Terminal Overlay CLI - GIF Management
    
    Usage:
      terminal-overlay gif <action> [options]
      
    Actions:
      add <path|url>   Add a local GIF or download from a URL
      list             List all available custom GIFs
      remove <name>    Delete a custom GIF by name
      help, -h, --help Show this help usage message
      
    Examples:
      terminal-overlay gif add ~/Downloads/party-parrot.gif
      terminal-overlay gif add https://example.com/bongo-cat.gif
      terminal-overlay gif list
      terminal-overlay gif remove party-parrot.gif
    """)
}

func handleGifSubcommands(args: [String]) {
    if args.count < 3 {
        printGifUsage()
        return
    }
    
    let action = args[2]
    switch action {
    case "add":
        if args.count < 4 {
            print("Error: 'gif add' requires a file path or URL.")
            return
        }
        addGif(source: args[3])
    case "list":
        listGifs()
    case "remove", "delete":
        if args.count < 4 {
            print("Error: 'gif remove' requires a GIF name.")
            return
        }
        removeGif(name: args[3])
    case "help", "-h", "--help":
        printGifUsage()
    default:
        print("Unknown gif action: \(action)")
        print("Available actions: add, list, remove, help")
    }
}

func printStartUsage() {
    print("""
    Terminal Overlay CLI - Start Subcommand
    
    Usage:
      terminal-overlay start [options]
      
    Launches the floating environment overlay. If not locked via options, 
    the active Kubernetes context dynamically updates the overlay.
    
    Options:
      --env <name>       Set environment mode: auto (k8s-based), dev, staging, prod
      --size <pixels>    Set overlay size in pixels for current tab (50 to 300)
      --dev-k8s <match>  K8s context match string for Dev (e.g. minikube)
      --staging-k8s <m>  K8s context match string for Staging
      --prod-k8s <match> K8s context match string for Prod
      --dev-gif <path>   Set global Dev GIF path (or 'none')
      --staging-gif <p>  Set global Staging GIF path (or 'none')
      --prod-gif <path>  Set global Prod GIF path (or 'none')
      
    Examples:
      terminal-overlay start
      terminal-overlay start --env auto
      terminal-overlay start --env dev --size 150
    """)
}

func printStopUsage() {
    print("""
    Terminal Overlay CLI - Stop Subcommand
    
    Usage:
      terminal-overlay stop
      
    Stops the currently running terminal-overlay background daemon process.
    """)
}

func printStatusUsage() {
    print("""
    Terminal Overlay CLI - Status Subcommand
    
    Usage:
      terminal-overlay status
      
    Shows the current daemon process state (RUNNING or STOPPED), active 
    tab settings, current K8s context, and environment-to-GIF configurations.
    """)
}

func printTuiUsage() {
    print("""
    Terminal Overlay CLI - TUI Subcommand
    
    Usage:
      terminal-overlay tui
      
    Opens the interactive Terminal UI (TUI) in the current window.
    Allows adjusting active tab styles, environment modes, cycling GIFs,
    and toggling the background daemon using keyboard arrow keys.
    """)
}

func printConfigureUsage() {
    print("""
    Terminal Overlay CLI - Configure Subcommand
    
    Usage:
      terminal-overlay configure [options]
      
    If run without options, this command starts the interactive Configuration Wizard.
    
    Options:
      --env <name>       Set environment mode: auto (k8s-based), dev, staging, prod
      --size <pixels>    Set overlay size in pixels for current tab (50 to 300)
      --dev-k8s <match>  K8s context match string for Dev (e.g. minikube)
      --staging-k8s <m>  K8s context match string for Staging
      --prod-k8s <match> K8s context match string for Prod
      --dev-gif <path>   Set global Dev GIF path (or 'none')
      --staging-gif <p>  Set global Staging GIF path (or 'none')
      --prod-gif <path>  Set global Prod GIF path (or 'none')
      
    Examples:
      terminal-overlay configure
      terminal-overlay configure --size 150
      terminal-overlay configure --prod-k8s production-gke-cluster --size 120
      terminal-overlay configure --dev-gif cat-bongo.gif
    """)
}

func printUsage() {
    print("""
    Terminal Overlay CLI - Floating Environment Companion
    
    Usage:
      terminal-overlay <command> [options]
      
    Commands:
      start              Launch the overlay in the background
      stop               Stop the running overlay
      status             Show current status and configuration settings
      configure          Modify configuration settings (interactive wizard if no options)
      tui                Open the interactive Terminal UI to configure settings
      gif                Manage custom GIFs (add, list, remove)
      help, -h, --help   Show this usage instructions screen
      
    Commands for gif:
      gif add <path|url> Add a local GIF or download from a URL
      gif list           List all available custom GIFs
      gif remove <name>  Delete a custom GIF by name
      
    Options for configure (and start):
      --env <name>       Set environment mode: auto (k8s-based), dev, staging, prod
      --size <pixels>    Set overlay size for current tab
      --dev-k8s <match>  K8s context match string for Dev (e.g. minikube)
      --staging-k8s <m>  K8s context match string for Staging
      --prod-k8s <match> K8s context match string for Prod
      --dev-gif <path>   Set global Dev GIF path (or 'none')
      --staging-gif <p>  Set global Staging GIF path (or 'none')
      --prod-gif <path>  Set global Prod GIF path (or 'none')
      
    Examples:
      terminal-overlay start --env auto
      terminal-overlay configure --size 150
      terminal-overlay configure --prod-k8s production-gke-cluster
      terminal-overlay stop
      terminal-overlay tui
    """)
}

// POSIX Terminal Raw Mode Utilities
func enableRawMode(tty: Int32) -> termios {
    var raw = termios()
    tcgetattr(tty, &raw)
    let original = raw
    cfmakeraw(&raw)
    raw.c_oflag |= UInt(OPOST)
    tcsetattr(tty, TCSAFLUSH, &raw)
    return original
}

func disableRawMode(tty: Int32, original: termios) {
    var temp = original
    tcsetattr(tty, TCSAFLUSH, &temp)
}

enum Key {
    case none
    case up
    case down
    case left
    case right
    case enter
    case escape
    case q
    case char(Character)
}

func readKey() -> Key {
    var char: UInt8 = 0
    let n = read(STDIN_FILENO, &char, 1)
    if n <= 0 { return .none }
    
    if char == 27 {
        var next1: UInt8 = 0
        var next2: UInt8 = 0
        
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        
        let n1 = read(STDIN_FILENO, &next1, 1)
        let n2 = read(STDIN_FILENO, &next2, 1)
        
        _ = fcntl(STDIN_FILENO, F_SETFL, flags)
        
        if n1 > 0 && next1 == 91 {
            if n2 > 0 {
                switch next2 {
                case 65: return .up
                case 66: return .down
                case 67: return .right
                case 68: return .left
                default: return .none
                }
            }
        }
        return .escape
    } else if char == 10 || char == 13 {
        return .enter
    } else if char == 113 {
        return .q
    }
    return .char(Character(UnicodeScalar(char)))
}

func renderTUI(selectedIndex: Int, tty: String) {
    let store = loadConfigStore()
    let tabConfig = store.tabs[tty] ?? store.tabs["default"] ?? TabConfiguration()
    
    let pidFile = getAppPidPath()
    var isRunning = false
    var pidVal: Int32 = 0
    if FileManager.default.fileExists(atPath: pidFile),
       let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(pidString) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", String(pid)]
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            isRunning = true
            pidVal = pid
        }
    }
    
    print("\u{001B}[H", terminator: "")
    let cl = "\u{001B}[K"
    
    print("\u{001B}[1;36m┌────────────────────────────────────────────────────────┐\u{001B}[0m\(cl)")
    print("\u{001B}[1;36m│             TERMINAL OVERLAY INTERACTIVE CONFIG        │\u{001B}[0m\(cl)")
    print("\u{001B}[1;36m│             Active Tab: \(tty.padding(toLength: 30, withPad: " ", startingAt: 0)) │\u{001B}[0m\(cl)")
    print("\u{001B}[1;36m└────────────────────────────────────────────────────────┘\u{001B}[0m\(cl)")
    print(" Navigate: \u{001B}[1m▲/▼ (Up/Down)\u{001B}[0m | Modify: \u{001B}[1m◀/▶ (Left/Right)\u{001B}[0m\(cl)")
    print(" Execute:  \u{001B}[1mENTER\u{001B}[0m       | Exit:   \u{001B}[1mq / ESC\u{001B}[0m\(cl)")
    print("──────────────────────────────────────────────────────────\(cl)")
    
    let labelColor = "\u{001B}[1m"
    let focusColor = "\u{001B}[1;33m"
    
    print(" \u{001B}[1;36m⚙️  TAB SETTINGS\u{001B}[0m\(cl)")
    
    // Row 0: Tab Environment Selection (Auto vs static)
    let r0Sel = selectedIndex == 0 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    var envText = ""
    if tabConfig.env == "auto" {
        let k8sContext = getK8sCurrentContext() ?? "None"
        var resolved = "dev"
        let lowercasedContext = k8sContext.lowercased()
        if !store.k8s.prod.isEmpty && lowercasedContext.contains(store.k8s.prod.lowercased()) {
            resolved = "prod"
        } else if !store.k8s.staging.isEmpty && lowercasedContext.contains(store.k8s.staging.lowercased()) {
            resolved = "staging"
        } else if !store.k8s.dev.isEmpty && lowercasedContext.contains(store.k8s.dev.lowercased()) {
            resolved = "dev"
        }
        let resolvedDisplay: String
        if resolved == "prod" {
            resolvedDisplay = "\u{001B}[1;38;5;203mProd (Matched: \(store.k8s.prod))\u{001B}[1;36m"
        } else if resolved == "staging" {
            resolvedDisplay = "\u{001B}[1;38;5;82mStaging (Matched: \(store.k8s.staging))\u{001B}[1;36m"
        } else if !store.k8s.dev.isEmpty && lowercasedContext.contains(store.k8s.dev.lowercased()) {
            resolvedDisplay = "\u{001B}[1;38;5;39mDev (Matched: \(store.k8s.dev))\u{001B}[1;36m"
        } else {
            resolvedDisplay = "\u{001B}[1;38;5;39mDev (Default)\u{001B}[1;36m"
        }
        envText = "\u{001B}[1;36m◆ Auto (\(resolvedDisplay))\u{001B}[0m  \u{001B}[90m◇ Dev  ◇ Staging  ◇ Prod\u{001B}[0m"
    } else if tabConfig.env == "dev" {
        envText = "\u{001B}[90m◇ Auto\u{001B}  \u{001B}[1;38;5;39m◆ Dev (Blue)\u{001B}[0m  \u{001B}[90m◇ Staging  ◇ Prod\u{001B}[0m"
    } else if tabConfig.env == "staging" {
        envText = "\u{001B}[90m◇ Auto  ◇ Dev\u{001B}  \u{001B}[1;38;5;82m◆ Staging (Green)\u{001B}[0m  \u{001B}[90m◇ Prod\u{001B}[0m"
    } else {
        envText = "\u{001B}[90m◇ Auto  ◇ Dev  ◇ Staging\u{001B}  \u{001B}[1;38;5;203m◆ Prod (Red)\u{001B}[0m"
    }
    print("\(r0Sel)Environment:           \(cl)\u{001B}[0m\(envText)")
    
    // Row 1: Mascot Size (Tab specific)
    let r1Sel = selectedIndex == 1 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    let progressWidth = 15
    let minSize = 50.0
    let maxSize = 300.0
    let percentage = (tabConfig.size - minSize) / (maxSize - minSize)
    let filledChars = Int(round(Double(progressWidth) * percentage))
    
    var slider = "["
    for i in 0..<progressWidth {
        if i < filledChars { slider += "█" }
        else if i == filledChars { slider += "▒" }
        else { slider += "░" }
    }
    slider += "]"
    
    let sizeColor = selectedIndex == 1 ? "\u{001B}[1;35m" : "\u{001B}[35m"
    print("\(r1Sel)Mascot Size:           \u{001B}[0m\(sizeColor)\u{001B}[1m\(Int(tabConfig.size))px\u{001B}[0m  \(slider)\(cl)")
    print("\(cl)")
    
    print(" \u{001B}[1;36m☸️  KUBERNETES CONTEXT AUTO-SWITCHING\u{001B}[0m\(cl)")
    
    // Row 2: Dev K8s Context Match string
    let r2Sel = selectedIndex == 2 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    print("\(r2Sel)Dev Cluster Match:     \u{001B}[0m\u{001B}[37m\(store.k8s.dev.isEmpty ? "(empty)" : store.k8s.dev)\u{001B}[0m  \u{001B}[3;90m(Enter to edit)\u{001B}[0m\(cl)")
    
    // Row 3: Staging K8s Context Match string
    let r3Sel = selectedIndex == 3 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    print("\(r3Sel)Staging Cluster Match:   \u{001B}[0m\u{001B}[37m\(store.k8s.staging.isEmpty ? "(empty)" : store.k8s.staging)\u{001B}[0m  \u{001B}[3;90m(Enter to edit)\u{001B}[0m\(cl)")
    
    // Row 4: Prod K8s Context Match string
    let r4Sel = selectedIndex == 4 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    print("\(r4Sel)Prod Cluster Match:    \u{001B}[0m\u{001B}[37m\(store.k8s.prod.isEmpty ? "(empty)" : store.k8s.prod)\u{001B}[0m  \u{001B}[3;90m(Enter to edit)\u{001B}[0m\(cl)")
    print("\(cl)")
    
    print(" \u{001B}[1;36m👾  ENVIRONMENT MASCOTS / GIFS\u{001B}[0m\(cl)")
    
    // Row 5: Dev Environment GIF (Global mapping)
    let r5Sel = selectedIndex == 5 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    let devGifVal = store.gifs.dev != nil ? (store.gifs.dev! as NSString).lastPathComponent : "Built-in Mascot Slime (Blue)"
    let devGifDisplay = selectedIndex == 5 ? "\u{001B}[1;35m◀ \(devGifVal) ▶\u{001B}[0m" : "\u{001B}[37m\(devGifVal)\u{001B}[0m"
    print("\(r5Sel)Dev Env GIF:            \u{001B}[0m\(devGifDisplay)\(cl)")
    
    // Row 6: Staging Environment GIF (Global mapping)
    let r6Sel = selectedIndex == 6 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    let stagingGifVal = store.gifs.staging != nil ? (store.gifs.staging! as NSString).lastPathComponent : "Built-in Mascot Slime (Green)"
    let stagingGifDisplay = selectedIndex == 6 ? "\u{001B}[1;35m◀ \(stagingGifVal) ▶\u{001B}[0m" : "\u{001B}[37m\(stagingGifVal)\u{001B}[0m"
    print("\(r6Sel)Staging Env GIF:        \u{001B}[0m\(stagingGifDisplay)\(cl)")
    
    // Row 7: Prod Environment GIF (Global mapping)
    let r7Sel = selectedIndex == 7 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    let prodGifVal = store.gifs.prod != nil ? (store.gifs.prod! as NSString).lastPathComponent : "Built-in Mascot Slime (Red)"
    let prodGifDisplay = selectedIndex == 7 ? "\u{001B}[1;35m◀ \(prodGifVal) ▶\u{001B}[0m" : "\u{001B}[37m\(prodGifVal)\u{001B}[0m"
    print("\(r7Sel)Prod Env GIF:           \u{001B}[0m\(prodGifDisplay)\(cl)")
    print("\(cl)")
    
    print(" \u{001B}[1;36m⚡️ SYSTEM DAEMON & CONTROL\u{001B}[0m\(cl)")
    
    // Row 8: Daemon control
    let r8Sel = selectedIndex == 8 ? "\(focusColor)  ➔  \(labelColor)" : "     \(labelColor)"
    var daemonStatus = ""
    if isRunning {
        daemonStatus = "\u{001B}[1;31m[ STOP OVERLAY ]\u{001B}[0m  \u{001B}[90m(Active PID: \(pidVal))\u{001B}[0m"
    } else {
        daemonStatus = "\u{001B}[1;32m[ START OVERLAY ]\u{001B}[0m \u{001B}[90m(Currently Off)\u{001B}[0m"
    }
    print("\(r8Sel)Daemon Power:          \u{001B}[0m\(daemonStatus)\(cl)")
    
    // Row 9: Exit
    let r9Sel = selectedIndex == 9 ? "\(focusColor)  ➔  \u{001B}[1;31m" : "     \u{001B}[22m"
    print("\(r9Sel)Exit Settings Panel\u{001B}[0m\(cl)")
    print("──────────────────────────────────────────────────────────\(cl)")
    
    fflush(stdout)
}

func cycleGIF(currentPath: String?, direction: Int) -> String? {
    let gifsList = getAvailableGIFs()
    var currentIdx = 0
    if let path = currentPath {
        let filename = (path as NSString).lastPathComponent
        currentIdx = gifsList.firstIndex(of: filename) ?? 0
    }
    let nextIdx = (currentIdx + direction + gifsList.count) % gifsList.count
    if nextIdx == 0 {
        return nil
    } else {
        return (getAppGifsDirectory() as NSString).appendingPathComponent(gifsList[nextIdx])
    }
}

func runTUI(tty: String) {
    var selectedIndex = 0
    print("\u{001B}[2J", terminator: "")
    print("\u{001B}[?25l", terminator: "")
    defer {
        print("\u{001B}[?25h", terminator: "")
    }
    
    let origTerm = enableRawMode(tty: STDIN_FILENO)
    
    var running = true
    while running {
        renderTUI(selectedIndex: selectedIndex, tty: tty)
        
        let key = readKey()
        switch key {
        case .up:
            selectedIndex = (selectedIndex - 1 + 10) % 10
        case .down:
            selectedIndex = (selectedIndex + 1) % 10
        case .left:
            var store = loadConfigStore()
            var tabConfig = store.tabs[tty] ?? store.tabs["default"] ?? TabConfiguration()
            
            if selectedIndex == 0 {
                if tabConfig.env == "prod" { tabConfig.env = "staging" }
                else if tabConfig.env == "staging" { tabConfig.env = "dev" }
                else if tabConfig.env == "dev" { tabConfig.env = "auto" }
                else { tabConfig.env = "prod" }
                store.tabs[tty] = tabConfig
            } else if selectedIndex == 1 {
                tabConfig.size = max(50, tabConfig.size - 10)
                store.tabs[tty] = tabConfig
            } else if selectedIndex == 5 {
                store.gifs.dev = cycleGIF(currentPath: store.gifs.dev, direction: -1)
            } else if selectedIndex == 6 {
                store.gifs.staging = cycleGIF(currentPath: store.gifs.staging, direction: -1)
            } else if selectedIndex == 7 {
                store.gifs.prod = cycleGIF(currentPath: store.gifs.prod, direction: -1)
            }
            saveConfigStore(store)
        case .right:
            var store = loadConfigStore()
            var tabConfig = store.tabs[tty] ?? store.tabs["default"] ?? TabConfiguration()
            
            if selectedIndex == 0 {
                if tabConfig.env == "auto" { tabConfig.env = "dev" }
                else if tabConfig.env == "dev" { tabConfig.env = "staging" }
                else if tabConfig.env == "staging" { tabConfig.env = "prod" }
                else { tabConfig.env = "auto" }
                store.tabs[tty] = tabConfig
            } else if selectedIndex == 1 {
                tabConfig.size = min(300, tabConfig.size + 10)
                store.tabs[tty] = tabConfig
            } else if selectedIndex == 5 {
                store.gifs.dev = cycleGIF(currentPath: store.gifs.dev, direction: 1)
            } else if selectedIndex == 6 {
                store.gifs.staging = cycleGIF(currentPath: store.gifs.staging, direction: 1)
            } else if selectedIndex == 7 {
                store.gifs.prod = cycleGIF(currentPath: store.gifs.prod, direction: 1)
            }
            saveConfigStore(store)
        case .enter:
            if selectedIndex == 2 || selectedIndex == 3 || selectedIndex == 4 {
                disableRawMode(tty: STDIN_FILENO, original: origTerm)
                print("\u{001B}[?25h", terminator: "") // Show cursor
                
                let modeName = selectedIndex == 2 ? "Dev" : (selectedIndex == 3 ? "Staging" : "Prod")
                print("\n\u{001B}[1;33mEnter k8s context substring match for \(modeName):\u{001B}[0m")
                print("Match: ", terminator: "")
                fflush(stdout)
                
                if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    var store = loadConfigStore()
                    if selectedIndex == 2 { store.k8s.dev = input }
                    else if selectedIndex == 3 { store.k8s.staging = input }
                    else { store.k8s.prod = input }
                    saveConfigStore(store)
                }
                
                print("\u{001B}[2J", terminator: "")
                print("\u{001B}[?25l", terminator: "")
                _ = enableRawMode(tty: STDIN_FILENO)
            } else if selectedIndex == 8 {
                var isRunning = false
                let pidFile = getAppPidPath()
                if FileManager.default.fileExists(atPath: pidFile),
                   let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                   let pid = Int32(pidString) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/kill")
                    process.arguments = ["-0", String(pid)]
                    try? process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        isRunning = true
                    }
                }
                
                disableRawMode(tty: STDIN_FILENO, original: origTerm)
                print("")
                if isRunning {
                    stopOverlay()
                } else {
                    startOverlayDaemon()
                }
                print("\nPress Enter to return...")
                _ = readLine()
                
                print("\u{001B}[2J", terminator: "")
                _ = enableRawMode(tty: STDIN_FILENO)
            } else if selectedIndex == 9 {
                running = false
            }
        case .escape, .q:
            running = false
        default:
            break
        }
    }
    
    disableRawMode(tty: STDIN_FILENO, original: origTerm)
    print("\u{001B}[2J\u{001B}[H", terminator: "")
}

// CLI Subcommand Router
func main() {
    let args = CommandLine.arguments
    let currentTty = getCurrentTTY()
    
    if args.count < 2 {
        printUsage()
        return
    }
    
    let subcommand = args[1]
    
    switch subcommand {
    case "gif":
        handleGifSubcommands(args: args)
    case "start":
        if args.contains("-h") || args.contains("--help") || args.contains("help") {
            printStartUsage()
        } else if args.contains("--daemon") {
            let app = NSApplication.shared
            let delegate = OverlayApplicationDelegate()
            app.delegate = delegate
            app.run()
        } else {
            parseConfigArgsAndSave(tty: currentTty)
            startOverlayDaemon()
        }
    case "stop":
        if args.contains("-h") || args.contains("--help") || args.contains("help") {
            printStopUsage()
        } else {
            stopOverlay()
        }
    case "status":
        if args.contains("-h") || args.contains("--help") || args.contains("help") {
            printStatusUsage()
        } else {
            printStatus(tty: currentTty)
        }
    case "configure":
        if args.contains("-h") || args.contains("--help") || args.contains("help") {
            printConfigureUsage()
        } else if args.count < 3 {
            runConfigWizard(tty: currentTty)
            printStatus(tty: currentTty)
        } else {
            parseConfigArgsAndSave(tty: currentTty)
            printStatus(tty: currentTty)
        }
    case "tui":
        if args.contains("-h") || args.contains("--help") || args.contains("help") {
            printTuiUsage()
        } else {
            runTUI(tty: currentTty)
        }
    case "-h", "--help", "help":
        printUsage()
    default:
        print("Unknown command: \(subcommand)")
        printUsage()
    }
}

main()
