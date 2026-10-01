# Release template: generated chit.rb is published through a Casks/chit.rb PR.
# Keep this template outside Casks until a real release supplies its checksum.
cask "chit" do
  version "1.0.1"
  sha256 "ce711179324c4f1e4a85a3395b79e6214197d0f57a93dc0a4153d244f5b3a1d1"

  url "https://github.com/dankhole/chit/releases/download/v1.0.1/Chit-1.0.1.zip"
  name "Chit"
  desc "Native task lists stored in YAML files"
  homepage "https://github.com/dankhole/chit"

  auto_updates true
  depends_on macos: :sonoma

  app "Chit.app"
  binary "#{appdir}/Chit.app/Contents/Resources/bin/chit"

  caveats <<~EOS
    Chit is ad hoc signed and is not notarized by Apple.
    If macOS blocks the first launch and you trust this release, use
    Open Anyway in System Settings > Privacy & Security after trying to open Chit.
  EOS
end
