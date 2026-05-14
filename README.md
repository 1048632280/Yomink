# Yomink

Yomink is an iOS 15.5+ native UIKit TXT reader focused on mmap-based file access, CoreText pagination, UICollectionView rendering, and strict local-only privacy.

## Phase 1 Status

The repository currently contains the first-phase project skeleton:

- UIKit App/Scene lifecycle.
- Bookshelf placeholder built with `UICollectionViewDiffableDataSource`.
- Reader placeholder built around `UICollectionView`.
- ReaderEngine boundaries for mmap file mapping, encoding, text windows, CoreText pagination, page byte ranges, page cache, and byte-offset progress.
- GRDB-backed database skeleton with initial migrations.
- Settings and search indexing service skeletons.
- Unit test target with starter model tests.
- GitHub Actions workflow for an unsigned IPA build.

## Build

Local builds require macOS with Xcode. The CI entrypoint is:

```sh
xcodebuild build -project Yomink.xcodeproj -scheme Yomink -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO
```

The workflow at `.github/workflows/build-ipa.yml` packages an unsigned IPA artifact. Real-device installation will require signing configuration in a later phase.
