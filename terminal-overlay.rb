class TerminalOverlay < Formula
  desc "Zero-dependency floating desktop environment status overlay for Terminal.app"
  homepage "https://github.com/yourusername/terminal-overlay"
  # Update URL and sha256 when you publish a release version on GitHub
  url "file://#{Dir.pwd}/archive.tar.gz" # Placeholder for local testing
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  version "1.0.0"
  license "MIT"

  def install
    # Compile from Swift source
    system "swiftc", "terminal_overlay.swift", "-o", "terminal_overlay"
    
    # Install binary into /opt/homebrew/bin/terminal_overlay
    bin.install "terminal_overlay"

    # Install default GIFs directory into share/terminal-overlay
    pkgshare.install "gifs"
  end

  def caveats
    <<~EOS
      To run terminal-overlay:
        terminal_overlay start
      
      To configure context matches and env GIFs:
        terminal_overlay tui
        
      The configuration will be stored locally in config.json.
    EOS
  end

  test do
    assert_match "Terminal Overlay CLI", shell_output("#{bin}/terminal_overlay status", 0)
  end
end
