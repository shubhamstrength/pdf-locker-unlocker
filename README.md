# PDF Locker

Add or remove a password on PDF files, free and open source. Comes as a native **Mac app** and a
**website** that works entirely in your browser. Your files are never uploaded anywhere.

- **Lock** a PDF with a password (AES encryption), optionally blocking printing, copying or editing.
- **Unlock** a PDF you know the password for and save a copy with no password or restrictions.
- Batch several files at once. Originals are never overwritten: you get `name-locked.pdf` or `name-unlocked.pdf`.

PDF Locker does not crack or guess passwords. To unlock a PDF that needs a password to open, you need that password.

## Website

**https://shubhamstrength.github.io/pdf-locker/**

The page runs [qpdf](https://github.com/qpdf/qpdf) compiled to WebAssembly inside a Web Worker, so
encryption and decryption happen on your device. It writes AES-256 encryption and works in any
modern browser on Mac, Windows, Linux, iOS and Android.

To run it locally (a web server is needed because browsers block workers on `file://`):

```sh
cd web
python3 -m http.server 8000
# open http://localhost:8000
```

The site is plain HTML, CSS and JavaScript with no build step. `web/vendor/` holds the qpdf
WebAssembly build; see [web/vendor/README.md](web/vendor/README.md).

## Mac app

A SwiftUI app built on Apple's PDFKit. Requires macOS 13 Ventura or later, on Apple silicon or Intel.

- Drag PDFs onto the window or the Dock icon, or use **Open With › PDF Locker** in Finder.
- The app switches to Lock or Unlock based on the files you add, and shows each file's status.
- Choose to save next to the originals or in a folder of your choice, then **Show in Finder**.

### Download

Get `PDF-Locker-mac.zip` from the [latest release](https://github.com/shubhamstrength/pdf-locker/releases/latest),
unzip it and move **PDF Locker** to Applications.

The app is not notarized by Apple, so the first time you open it macOS will say it can't check it
for malware. Right-click the app and choose **Open**, then **Open** again (on macOS 15, go to
**System Settings › Privacy & Security** and click **Open Anyway**). Or build it yourself:

### Build from source

With Xcode or the Command Line Tools installed:

```sh
cd mac
swift test                 # run the tests
swift run                  # run the app straight from source
scripts/build-app.sh       # build "build/PDF Locker.app" (universal, ad-hoc signed)
```

You can also open `mac/Package.swift` in Xcode and press Run.

## Project layout

```
mac/                      Mac app (Swift Package)
  Sources/PDFLockerCore/  lock/unlock logic on top of PDFKit
  Sources/PDFLocker/      SwiftUI app
  Tests/                  tests that lock, unlock and check permissions on generated PDFs
  scripts/build-app.sh    packages the .app bundle
web/                      website (static, deployed to GitHub Pages)
docs/RESEARCH.md          how existing PDF password tools work, and what we took from them
```

## Releasing

- Every push to `main` builds and tests the Mac app and deploys the website to GitHub Pages.
- Pushing a tag like `v1.0.0` also publishes a GitHub release with the zipped app.

## Contributing

Issues and pull requests are welcome. Please keep both apps working offline and never send a
user's file or password anywhere.

## License

[MIT](LICENSE). The website bundles qpdf (Apache 2.0) via [qpdf-wasm](https://github.com/neslinesli93/qpdf-wasm) (ISC).
