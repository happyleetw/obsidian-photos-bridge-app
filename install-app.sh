#!/bin/bash

echo "🚀 Installing Obsidian Photos Bridge to Applications..."

# Check if app exists
if [ ! -d "Obsidian Photos Bridge.app" ]; then
    echo "❌ App not found. Please build first with: swift build -c release && ./build-app.sh"
    exit 1
fi

# Copy to Applications
if cp -R "Obsidian Photos Bridge.app" /Applications/; then
    echo "✅ Successfully installed to /Applications/"
    echo "📱 You can now find 'Obsidian Photos Bridge' in your Applications folder"
    echo "🔍 Or search for it in Spotlight"
    echo ""
    echo "🎯 When you run it:"
    echo "   • A photo icon will appear in your menu bar (top right)"
    echo "   • Click the icon to see options and quit"
    echo "   • The API server will run in the background"
    echo ""
else
    echo "❌ Failed to install. You might need to run with sudo:"
    echo "   sudo ./install-app.sh"
    exit 1
fi 