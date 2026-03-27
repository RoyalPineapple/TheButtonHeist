# Homebrew formula for Button Heist CLI + MCP server.
#
# Source of truth lives here. The release workflow copies this to
# RoyalPineapple/homebrew-tap with real version and SHA-256 values.
#
# Users install with:
#   brew install RoyalPineapple/tap/buttonheist

class Buttonheist < Formula
  desc "Give AI agents full programmatic control of iOS apps"
  homepage "https://github.com/RoyalPineapple/ButtonHeist"
  version "0.0.1"

  url "https://github.com/RoyalPineapple/ButtonHeist/releases/download/v#{version}/buttonheist-#{version}-macos.tar.gz"
  sha256 "PLACEHOLDER"

  resource "mcp" do
    url "https://github.com/RoyalPineapple/ButtonHeist/releases/download/v#{version}/buttonheist-mcp-#{version}-macos.tar.gz"
    sha256 "PLACEHOLDER"
  end

  depends_on :macos
  depends_on macos: :sonoma

  resource "integrate" do
    url "https://github.com/RoyalPineapple/ButtonHeist/releases/download/v#{version}/buttonheist-integrate"
    sha256 "PLACEHOLDER"
  end

  def install
    bin.install "buttonheist"
    resource("mcp").stage { bin.install "buttonheist-mcp" }
    resource("integrate").stage { bin.install "buttonheist-integrate" }
  end

  def caveats
    <<~EOS
      To integrate Button Heist into your iOS app:

        cd /path/to/your-ios-project
        buttonheist-integrate

      This launches Claude Code to automatically wire TheInsideJob into your
      app, covering SPM, CocoaPods, Tuist, XcodeGen, Bazel, and bare Xcode
      projects. Requires Claude Code (npm install -g @anthropic-ai/claude-code).

      MCP server is installed at:
        #{opt_bin}/buttonheist-mcp

      Add to your project's .mcp.json:
        {
          "mcpServers": {
            "buttonheist": {
              "command": "#{opt_bin}/buttonheist-mcp",
              "args": []
            }
          }
        }
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/buttonheist --version")
  end
end
