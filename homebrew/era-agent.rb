class EraAgent < Formula
  desc "Secure code-execution runner with microVM orchestration using krunvm"
  homepage "https://github.com/your-username/era-agent"
  # NOTE: Replace with actual GitHub release URL and SHA when creating a real release
  url "https://github.com/your-username/era-agent/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_FROM_RELEASE"  # Placeholder - update with actual SHA
  license "MIT"

  head do
    url "https://github.com/your-username/era-agent.git", branch: "main"
  end

  depends_on "go" => :build
  depends_on "krunvm" => :recommended  # Required for full functionality
  depends_on "buildah" => :recommended # Required for image building
  
  on_macos do
    depends_on "coreutils" # Required for macOS setup scripts
  end

  def install
    # Build the binary with proper Go module support
    system "make", "agent"
    bin.install "agent"
    
    # Install additional scripts
    (libexec/"setup").install "scripts/macos/setup.sh" if OS.mac?
    (libexec/"setup").install "scripts/brew-install/setup.sh"
    
    # Install documentation
    pkgshare.install "README.md" if File.exist?("README.md")
  end

  def post_install
    # Create user directory for state if needed
    state_dir = Pathname.new(ENV["HOME"]) / ".local" / "share" / "era-agent"
    state_dir.mkpath unless state_dir.directory?
  end

  def caveats
    <<~EOS
      ERA Agent installed successfully!

      Before using ERA Agent, you need to install required dependencies:
      
      #{Formatter.url("https://docs.krunvm.dev/installation.html")}
      
      For macOS users, run the setup script after installing dependencies:
      
          #{opt_libexec}/setup/setup.sh
      
      For Linux users, ensure krunvm and buildah are installed and configured properly.
      
      Then start the ERA Agent server:
      
          #{opt_bin}/agent serve
      
      To run with a custom state directory, use:
      
          AGENT_STATE_DIR=/path/to/desired/state #{opt_bin}/agent serve
    EOS
  end

  test do
    # Test basic functionality
    output = shell_output("#{bin}/agent --help 2>&1")
    assert_match "agent", output
    
    # Test that the binary exists
    assert_predicate bin/"agent", :executable?
  end
end

# Note for maintainers:
# To update this formula for a new release:
# 1. Update the version in the url line (v1.0.0 -> v1.0.1, etc.)
# 2. Get the SHA256 of the release tarball:
#    curl -L https://github.com/your-username/era-agent/archive/refs/tags/v1.0.1.tar.gz | shasum -a 256
# 3. Replace the sha256 value in this file