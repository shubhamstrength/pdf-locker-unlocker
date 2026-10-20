# How other PDF password tools work

Before building PDF Locker we looked at the tools people already use to add or remove a PDF
password, based on their public documentation and UI. This is what shaped the feature set.

| Tool | Lock (add password) | Unlock | Permissions | Where files go |
| --- | --- | --- | --- | --- |
| macOS Preview | File › Export… › Encrypt, or Export as PDF › Security Options | Open with password, then export without Encrypt | Printing, copying, editing (owner password) | Stays on the Mac |
| PDF Expert (Mac) | File › Set Password | File › Remove Password | Owner password with print/copy/edit | Stays on the Mac |
| Adobe Acrobat | Protect › Encrypt with password | Protect › Remove security | Detailed print/edit/copy settings | Stays on the machine (paid) |
| iLovePDF / Smallpdf / Adobe online | Upload, type password, download | Upload, type password, download | Mostly none in free tiers | Uploaded to their servers |

What we took from this:

- **Two clear modes.** Every tool separates "add a password" from "remove a password".
  PDF Locker has a Lock / Unlock switch and picks the right one from the files you add.
- **Confirm the password.** Preview and Acrobat ask twice, because a typo locks you out for good.
- **Optional restrictions.** Desktop tools offer a separate permissions (owner) password that
  blocks printing, copying or editing. We offer the same three switches, hidden until asked for.
- **Never overwrite the original.** Results are saved as `name-locked.pdf` / `name-unlocked.pdf`.
- **Batch.** Online tools and PDF Expert accept several files at once; so do we.
- **Privacy without paying.** Online tools upload your document. Our website runs qpdf in the
  browser via WebAssembly, so the file never leaves your device, and the Mac app uses Apple's PDFKit.
- **Strong encryption.** The website writes AES-256; the Mac app uses the AES encryption built into Apple's PDFKit.

Unlocking always needs the open password if the PDF has one. PDF Locker does not crack or
guess passwords.
