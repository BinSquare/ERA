class EraAgent < Formula
  desc "Secure code-execution runner with microVM orchestration using krunvm"
  homepage "https://github.com/your-username/era-agent"
  url "https://github.com/your-username/era-agent/archive/v1.0.0.tar.gz"
  sha256 "TODO_REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on "go" => :build
  depends_on "krunvm" => :recommended  # Can work without but limited functionality
  depends_on "buildah" => :recommended # Can work without but limited functionality

  def install
    # Build the binary with proper Go module support
    system "make", "agent"
    bin.install "agent"
  end

  def post_install
    # Create a user directory for state if needed
    state_dir = Pathname.new(ENV["HOME"]) / ".local" / "share" / "era-agent"
    state_dir.mkpath unless state_dir.directory?
  end

  def caveats
    <<~EOS
      ERA Agent installed successfully!

      Before using ERA Agent, you need to install required dependencies:

        brew install krunvm buildah  # Required for full functionality

      On macOS, krunvm requires a case-sensitive APFS volume:
        - Run: scripts/macos/setup.sh (from source directory)
        - Or create manually: diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm

      Quick start:
        agent vm temp --language python --cmd "python -c 'print(\"Hello from sandbox!\")'"

      For API server mode:
        agent server --addr :8080

      For more information, visit the GitHub repository.
    EOS
  end

  test do
    # Test that the binary exists and shows help
    output = shell_output("#{bin}/agent --help 2>&1")
    assert_match "Agent CLI", output
    assert_match "vm", output
  end
end