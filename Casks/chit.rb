# Release template: generated chit.rb is published through a Casks/chit.rb PR.
# Keep this template outside Casks until a real release supplies its checksum.
cask "chit" do
  version "1.1.0"
  sha256 "b6326614283ac77c2700a573c8f028ea5bb87346d926d457cac2602e42b6597c"

  url "https://github.com/dankhole/chit/releases/download/v1.1.0/Chit-1.1.0.zip"
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
