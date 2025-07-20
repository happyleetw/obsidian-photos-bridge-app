import Foundation
import Photos
import AppKit

class ObsidianPhotosBridgeApp {
    private let photosManager = PhotosManager.shared
    private let apiServer = APIServer.shared
    private var isGUIMode = false
    
    func run(guiMode: Bool = false) {
        self.isGUIMode = guiMode
        
        print("🚀 Obsidian Photos Bridge App Starting...")
        print("📸 Version: 1.0.0")
        print("🔒 Privacy: All operations are local-only")
        print("")
        
        // Check and request photos access
        Task {
            await requestPhotosPermission()
        }
        
        // Start API server
        startAPIServer()
        
        // Keep the app running (only in CLI mode)
        if !isGUIMode {
            RunLoop.main.run()
        }
    }
    
    private func requestPhotosPermission() async {
        let currentStatus = photosManager.checkPhotosAccess()
        
        switch currentStatus {
        case .authorized, .limited:
            print("✅ Photos access already granted")
            await loadPhotosLibrary()
        case .notDetermined:
            print("🔐 Requesting photos library access...")
            let granted = await photosManager.requestPhotosAccess()
            if granted {
                print("✅ Photos access granted")
                await loadPhotosLibrary()
            } else {
                print("❌ Photos access denied")
                printPhotosAccessHelp()
            }
        case .denied, .restricted:
            print("❌ Photos access denied or restricted")
            printPhotosAccessHelp()
        @unknown default:
            print("❓ Unknown photos authorization status")
        }
    }
    
    private func loadPhotosLibrary() async {
        print("📚 Loading photos library...")
        // Call loadPhotos on main thread
        await MainActor.run {
            photosManager.loadPhotosFromMainThread()
        }
        print("📸 Photos library loaded successfully")
    }
    
    private func startAPIServer() {
        print("🌐 Starting API server on port 44556...")
        
        if apiServer.start() {
            print("✅ API server started successfully")
            print("🔗 Server URL: \(apiServer.serverURL)")
            print("")
            print("📋 Available endpoints:")
            print("   GET  /api/health")
            print("   GET  /api/photos")
            print("   GET  /api/photos/search?q=<query>")
            print("   GET  /api/thumbnails/<photo-id>")
            print("   GET  /api/photos/<photo-id>/original")
            print("   POST /api/photos/<photo-id>/export")
            print("")
            print("🎯 Ready for Obsidian plugin connections!")
            print("💡 To stop the server, press Ctrl+C")
            print("")
            
            setupSignalHandlers()
        } else {
            print("❌ Failed to start API server")
            print("💡 Make sure port 44556 is not already in use")
            exit(1)
        }
    }
    
    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            print("")
            print("🛑 Shutting down...")
            APIServer.shared.stop()
            print("✅ API server stopped")
            exit(0)
        }
        
        signal(SIGTERM) { _ in
            print("")
            print("🛑 Shutting down...")
            APIServer.shared.stop()
            print("✅ API server stopped")
            exit(0)
        }
    }
    
    private func printPhotosAccessHelp() {
        print("")
        print("🔧 To grant photos access:")
        print("   1. Open System Preferences / System Settings")
        print("   2. Go to Security & Privacy / Privacy & Security")
        print("   3. Select 'Photos' in the left sidebar")
        print("   4. Check the box next to 'ObsidianPhotosBridge'")
        print("   5. Restart this application")
        print("")
        print("⚠️  Without photos access, the bridge cannot function.")
        print("   The app will continue running but no photos will be available.")
        print("")
    }
}

// Menu Bar App Wrapper
class MenuBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let bridgeApp = ObsidianPhotosBridgeApp()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar icon
        setupMenuBar()
        
        // Hide dock icon (makes it a menu bar only app)
        NSApp.setActivationPolicy(.accessory)
        
        // Run the original bridge app logic in GUI mode
        bridgeApp.run(guiMode: true)
    }
    
    private func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Set icon (using SF Symbol)
            button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Obsidian Photos Bridge")
            button.image?.isTemplate = true
        }
        
        // Create menu
        let menu = NSMenu()
        
        // Title
        let titleItem = NSMenuItem()
        titleItem.title = "Obsidian Photos Bridge"
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // API URL
        let apiItem = NSMenuItem()
        apiItem.title = "API: http://localhost:44556"
        apiItem.action = #selector(copyAPIUrl)
        apiItem.target = self
        menu.addItem(apiItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem()
        quitItem.title = "Quit"
        quitItem.action = #selector(quit)
        quitItem.target = self
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func copyAPIUrl() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("http://localhost:44556", forType: .string)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// Main function - choose between GUI and CLI
if ProcessInfo.processInfo.environment["GUI_MODE"] != "false" {
    // GUI Mode - with menu bar icon
    let app = NSApplication.shared
    let delegate = MenuBarApp()
    app.delegate = delegate
    app.run()
} else {
    // CLI Mode - original behavior
    let app = ObsidianPhotosBridgeApp()
    app.run()
} 