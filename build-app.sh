#!/bin/bash

echo "🔨 Building Obsidian Photos Bridge App..."

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "Obsidian Photos Bridge.app"
rm -rf .build

# Build release version
echo "⚙️ Building release version..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "Obsidian Photos Bridge.app/Contents/MacOS"
mkdir -p "Obsidian Photos Bridge.app/Contents/Resources"

# Copy executable
cp .build/release/ObsidianPhotosBridge "Obsidian Photos Bridge.app/Contents/MacOS/"

# Set executable permissions
chmod +x "Obsidian Photos Bridge.app/Contents/MacOS/ObsidianPhotosBridge"

# Create Info.plist
cat > "Obsidian Photos Bridge.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ObsidianPhotosBridge</string>
    <key>CFBundleIdentifier</key>
    <string>com.happylee.obsidian-photos-bridge</string>
    <key>CFBundleName</key>
    <string>Obsidian Photos Bridge</string>
    <key>CFBundleDisplayName</key>
    <string>Obsidian Photos Bridge</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>OPBR</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Obsidian Photos Bridge needs access to your Photos library to provide photo integration with Obsidian.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ App bundle created successfully!"
echo "📱 You can now:"
echo "   1. Test: open 'Obsidian Photos Bridge.app'"
echo "   2. Install: ./install-app.sh"
echo "" 