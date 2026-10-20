import Foundation
import PDFKit

/// How a PDF on disk is currently protected.
public enum PDFProtection: Equatable, Sendable {
    /// Not encrypted at all.
    case none
    /// Encrypted and needs a password to open.
    case passwordToOpen
    /// Encrypted with an owner password only: it opens, but printing/copying/editing may be restricted.
    case restricted
}

public enum PDFLockerError: LocalizedError, Equatable {
    case cannotOpen
    case alreadyEncrypted
    case notEncrypted
    case wrongPassword
    case emptyPassword
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .cannotOpen: return "This file could not be opened as a PDF."
        case .alreadyEncrypted: return "This PDF is already password protected. Unlock it first."
        case .notEncrypted: return "This PDF is not password protected."
        case .wrongPassword: return "The password is incorrect."
        case .emptyPassword: return "Enter a password."
        case .writeFailed: return "The new PDF could not be saved."
        }
    }
}

/// Options for locking a PDF.
public struct LockOptions: Equatable, Sendable {
    /// Password needed to open the PDF.
    public var userPassword: String
    /// Password that grants full access. When nil, the open password is used, so anyone who can open the file has full access.
    public var ownerPassword: String?
    public var allowPrinting: Bool
    public var allowCopying: Bool
    public var allowEditing: Bool

    public init(userPassword: String, ownerPassword: String? = nil,
                allowPrinting: Bool = true, allowCopying: Bool = true, allowEditing: Bool = true) {
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword
        self.allowPrinting = allowPrinting
        self.allowCopying = allowCopying
        self.allowEditing = allowEditing
    }

    var permissions: PDFAccessPermissions {
        var p: PDFAccessPermissions = [.allowsContentAccessibility]
        if allowPrinting { p.formUnion([.allowsLowQualityPrinting, .allowsHighQualityPrinting]) }
        if allowCopying { p.insert(.allowsContentCopying) }
        if allowEditing {
            p.formUnion([.allowsDocumentChanges, .allowsDocumentAssembly, .allowsCommenting, .allowsFormFieldEntry])
        }
        return p
    }
}

public enum PDFLocker {
    /// Reports whether and how a PDF is protected.
    public static func protection(of url: URL) throws -> PDFProtection {
        guard let doc = PDFDocument(url: url) else { throw PDFLockerError.cannotOpen }
        if !doc.isEncrypted { return .none }
        return doc.isLocked ? .passwordToOpen : .restricted
    }

    /// Encrypts `input` with AES and writes the result to `output`.
    public static func lock(_ input: URL, to output: URL, options: LockOptions) throws {
        guard !options.userPassword.isEmpty else { throw PDFLockerError.emptyPassword }
        guard let doc = PDFDocument(url: input) else { throw PDFLockerError.cannotOpen }
        guard !doc.isEncrypted else { throw PDFLockerError.alreadyEncrypted }

        let owner = (options.ownerPassword?.isEmpty == false) ? options.ownerPassword! : options.userPassword
        let writeOptions: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: options.userPassword,
            .ownerPasswordOption: owner,
            .accessPermissionsOption: NSNumber(value: options.permissions.rawValue),
        ]
        guard doc.write(to: output, withOptions: writeOptions) else { throw PDFLockerError.writeFailed }
    }

    /// Removes the password and restrictions from `input` and writes an unprotected copy to `output`.
    /// `password` may be empty for PDFs that open without one but carry restrictions.
    public static func unlock(_ input: URL, to output: URL, password: String) throws {
        guard let doc = PDFDocument(url: input) else { throw PDFLockerError.cannotOpen }
        guard doc.isEncrypted else { throw PDFLockerError.notEncrypted }
        if doc.isLocked {
            guard !password.isEmpty else { throw PDFLockerError.emptyPassword }
            guard doc.unlock(withPassword: password) else { throw PDFLockerError.wrongPassword }
        } else if !password.isEmpty {
            // Owner password on a restricted PDF; ignore a mismatch since the file already opens.
            _ = doc.unlock(withPassword: password)
        }

        if doc.write(to: output), let check = PDFDocument(url: output), !check.isEncrypted {
            return
        }
        // Some files keep their encryption when re-saved, so rebuild them page by page.
        let copy = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
            copy.insert(page, at: copy.pageCount)
        }
        copy.documentAttributes = doc.documentAttributes
        guard copy.pageCount == doc.pageCount, copy.write(to: output) else { throw PDFLockerError.writeFailed }
    }

    /// A URL next to `input` (or inside `folder`) named like "Report-locked.pdf" that does not exist yet.
    public static func outputURL(for input: URL, suffix: String, in folder: URL? = nil) -> URL {
        let dir = folder ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent + "-" + suffix
        var candidate = dir.appendingPathComponent(base).appendingPathExtension("pdf")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension("pdf")
            n += 1
        }
        return candidate
    }
}
