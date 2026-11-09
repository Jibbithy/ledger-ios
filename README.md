# Ledger

[![CI](https://github.com/Jibbithy/ledger-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/Jibbithy/ledger-ios/actions/workflows/ci.yml)

A native iOS personal finance app for tracking activity, spending, subscriptions and savings goals, with charts and a biometric lock.

Built with SwiftUI and Swift Charts. Sample data in this repo is fictional.

**This is a portfolio project.** The app gets its data from a personal backend that isn't in this repo, so it won't show live data without one. The project has no automated tests.

## Build

Requires Xcode. Open `Ledger.xcodeproj`, then set your own Apple team under Signing & Capabilities to run it on a device.

```bash
xcodebuild build -project Ledger.xcodeproj -scheme Ledger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Change the simulator name to one you have installed.

## License

[MIT](LICENSE)
