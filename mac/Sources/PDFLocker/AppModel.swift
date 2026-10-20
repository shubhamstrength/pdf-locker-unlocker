import AppKit
import PDFLockerCore
import UniformTypeIdentifiers

enum Mode: String, CaseIterable, Identifiable {
    case lock = "Lock"
    case unlock = "Unlock"
    var id: Self { self }
}

struct FileItem: Identifiable, Equatable {
    enum Outcome: Equatable {
        case pending
        case working
        case done(URL)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    var protection: PDFProtection?
    var outcome: Outcome = .pending
}

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: Mode = .lock
    @Published var files: [FileItem] = []

    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var restrict = false
    @Published var ownerPassword = ""
    @Published var allowPrinting = true
    @Published var allowCopying = true
    @Published var allowEditing = true

    /// nil saves next to each original.
    @Published var outputFolder: URL?
    @Published private(set) var isWorking = false

    var validationMessage: String? {
        if files.isEmpty { return "Add one or more PDFs." }
        switch mode {
        case .lock:
            if password.isEmpty { return "Choose a password." }
            if password != confirmPassword { return "Passwords don't match." }
            if restrict && ownerPassword.isEmpty { return "Choose a permissions password." }
            if restrict && ownerPassword == password { return "Use a permissions password that differs from the open password." }
        case .unlock:
            let needsPassword = files.contains { $0.protection == .passwordToOpen }
            if needsPassword && password.isEmpty { return "Enter the PDF's password." }
        }
        return nil
    }

    var canRun: Bool { validationMessage == nil && !isWorking }

    func add(_ urls: [URL]) {
        let known = Set(files.map(\.url.standardizedFileURL))
        let pdfs = urls
            .filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) ?? ($0.pathExtension.lowercased() == "pdf") }
            .filter { !known.contains($0.standardizedFileURL) }
        guard !pdfs.isEmpty else { return }
        files += pdfs.map { FileItem(url: $0, protection: try? PDFLocker.protection(of: $0)) }

        // Pick the mode that matches what was dropped.
        if files.allSatisfy({ $0.protection == .passwordToOpen || $0.protection == .restricted }) {
            mode = .unlock
        } else if files.allSatisfy({ $0.protection == PDFProtection.none }) {
            mode = .lock
        }
    }

    func remove(_ ids: Set<FileItem.ID>) {
        files.removeAll { ids.contains($0.id) }
    }

    func clear() {
        files.removeAll()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK { outputFolder = panel.url }
    }

    func revealOutputs() {
        let urls = files.compactMap { if case .done(let url) = $0.outcome { return url } else { return nil } }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func run() async {
        guard canRun else { return }
        isWorking = true
        defer { isWorking = false }

        let mode = mode
        let password = password
        let options = LockOptions(
            userPassword: password,
            ownerPassword: restrict ? ownerPassword : nil,
            allowPrinting: !restrict || allowPrinting,
            allowCopying: !restrict || allowCopying,
            allowEditing: !restrict || allowEditing
        )
        let folder = outputFolder

        for index in files.indices {
            if case .done = files[index].outcome { continue }
            files[index].outcome = .working
            let input = files[index].url
            let outcome: FileItem.Outcome = await Task.detached(priority: .userInitiated) {
                do {
                    switch mode {
                    case .lock:
                        let output = PDFLocker.outputURL(for: input, suffix: "locked", in: folder)
                        try PDFLocker.lock(input, to: output, options: options)
                        return .done(output)
                    case .unlock:
                        let output = PDFLocker.outputURL(for: input, suffix: "unlocked", in: folder)
                        try PDFLocker.unlock(input, to: output, password: password)
                        return .done(output)
                    }
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
            files[index].outcome = outcome
        }
    }

    /// Clears results so the same files can be processed again, e.g. after switching mode.
    func resetOutcomes() {
        for i in files.indices {
            files[i].outcome = .pending
            files[i].protection = try? PDFLocker.protection(of: files[i].url)
        }
    }
}
