import XCTest
import PDFKit
@testable import PDFLockerCore

final class PDFLockerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a two-page PDF with some text on it.
    func makeSample(_ name: String = "sample.pdf") throws -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for i in 1...2 {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello page \(i)"))
            ctx.textPosition = CGPoint(x: 40, y: 100)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    func testLockThenUnlock() throws {
        let input = try makeSample()
        XCTAssertEqual(try PDFLocker.protection(of: input), PDFProtection.none)

        let locked = dir.appendingPathComponent("locked.pdf")
        try PDFLocker.lock(input, to: locked, options: LockOptions(userPassword: "s3cret"))
        XCTAssertEqual(try PDFLocker.protection(of: locked), .passwordToOpen)

        let doc = try XCTUnwrap(PDFDocument(url: locked))
        XCTAssertFalse(doc.unlock(withPassword: "wrong"))
        XCTAssertTrue(doc.unlock(withPassword: "s3cret"))
        XCTAssertEqual(doc.pageCount, 2)

        let unlocked = dir.appendingPathComponent("unlocked.pdf")
        try PDFLocker.unlock(locked, to: unlocked, password: "s3cret")
        XCTAssertEqual(try PDFLocker.protection(of: unlocked), PDFProtection.none)
        let out = try XCTUnwrap(PDFDocument(url: unlocked))
        XCTAssertEqual(out.pageCount, 2)
        XCTAssertTrue(out.page(at: 0)?.string?.contains("Hello page 1") ?? false)
    }

    func testWrongPasswordIsRejected() throws {
        let locked = dir.appendingPathComponent("locked.pdf")
        try PDFLocker.lock(try makeSample(), to: locked, options: LockOptions(userPassword: "right"))
        XCTAssertThrowsError(try PDFLocker.unlock(locked, to: dir.appendingPathComponent("x.pdf"), password: "wrong")) {
            XCTAssertEqual($0 as? PDFLockerError, .wrongPassword)
        }
    }

    func testRestrictionsAreApplied() throws {
        let locked = dir.appendingPathComponent("locked.pdf")
        let options = LockOptions(userPassword: "open", ownerPassword: "owner",
                                  allowPrinting: false, allowCopying: false, allowEditing: false)
        try PDFLocker.lock(try makeSample(), to: locked, options: options)

        let doc = try XCTUnwrap(PDFDocument(url: locked))
        XCTAssertTrue(doc.unlock(withPassword: "open"))
        XCTAssertFalse(doc.allowsCopying)
        XCTAssertFalse(doc.allowsPrinting)

        let owner = try XCTUnwrap(PDFDocument(url: locked))
        XCTAssertTrue(owner.unlock(withPassword: "owner"))
        XCTAssertTrue(owner.allowsCopying)
    }

    func testLockingTwiceFails() throws {
        let locked = dir.appendingPathComponent("locked.pdf")
        try PDFLocker.lock(try makeSample(), to: locked, options: LockOptions(userPassword: "a"))
        XCTAssertThrowsError(try PDFLocker.lock(locked, to: dir.appendingPathComponent("y.pdf"),
                                                options: LockOptions(userPassword: "b"))) {
            XCTAssertEqual($0 as? PDFLockerError, .alreadyEncrypted)
        }
    }

    func testOutputURLDoesNotOverwrite() throws {
        let input = try makeSample("Report.pdf")
        let first = PDFLocker.outputURL(for: input, suffix: "locked")
        XCTAssertEqual(first.lastPathComponent, "Report-locked.pdf")
        try Data().write(to: first)
        XCTAssertEqual(PDFLocker.outputURL(for: input, suffix: "locked").lastPathComponent, "Report-locked 2.pdf")
    }
}
