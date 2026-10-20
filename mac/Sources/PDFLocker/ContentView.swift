import PDFLockerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<FileItem.ID>()
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $model.mode) {
                ForEach(Mode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode == .lock ? "lock.fill" : "lock.open.fill").tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.mode) { _ in model.resetOutcomes() }

            fileList
            settings
            footer
        }
        .padding(20)
    }

    // MARK: Files

    private var fileList: some View {
        ZStack {
            if model.files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drop PDFs here")
                        .font(.title3)
                    Button("Choose Files…") { model.chooseFiles() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(model.files) { FileRow(item: $0) }
                }
                .onDeleteCommand { model.remove(selection) }
            }
        }
        .frame(minHeight: 180)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: model.files.isEmpty ? [6] : []))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in model.add([url]) } }
                }
            }
            return true
        }
    }

    // MARK: Settings

    @ViewBuilder
    private var settings: some View {
        Form {
            switch model.mode {
            case .lock:
                PasswordField("Password", text: $model.password)
                PasswordField("Confirm", text: $model.confirmPassword)
                Toggle("Restrict printing, copying or editing", isOn: $model.restrict.animation())
                if model.restrict {
                    PasswordField("Permissions password", text: $model.ownerPassword)
                    Toggle("Allow printing", isOn: $model.allowPrinting)
                    Toggle("Allow copying text and images", isOn: $model.allowCopying)
                    Toggle("Allow editing and comments", isOn: $model.allowEditing)
                }
            case .unlock:
                PasswordField("Password", text: $model.password)
                Text("Unlocking saves a copy without a password or restrictions. The original is left as it is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Save to") {
                HStack {
                    Text(model.outputFolder?.lastPathComponent ?? "Same folder as each PDF")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.outputFolder != nil {
                        Button("Reset") { model.outputFolder = nil }
                    }
                    Button("Choose…") { model.chooseOutputFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let message = model.validationMessage {
                Text(message).foregroundStyle(.secondary)
            } else if model.files.contains(where: { if case .done = $0.outcome { return true }; return false }) {
                Button("Show in Finder") { model.revealOutputs() }
            }
            Spacer()
            if !model.files.isEmpty {
                Button("Clear") { model.clear() }
                    .disabled(model.isWorking)
            }
            Button {
                Task { await model.run() }
            } label: {
                let count = model.files.count
                Text("\(model.mode.rawValue) \(count == 1 ? "PDF" : "\(count) PDFs")")
                    .frame(minWidth: 110)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(!model.canRun)
        }
    }
}

struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(item.protection == PDFProtection.none ? Color.secondary : Color.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1)
            }
            Spacer()
            switch item.outcome {
            case .working: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .pending: EmptyView()
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }

    private var icon: String {
        switch item.protection {
        case .passwordToOpen: return "lock.fill"
        case .restricted: return "lock.shield"
        case .none?: return "doc"
        case nil: return "questionmark.circle"
        }
    }

    private var detail: String {
        switch item.outcome {
        case .done(let url): return "Saved as \(url.lastPathComponent)"
        case .failed(let message): return message
        default:
            switch item.protection {
            case .passwordToOpen: return "Password protected"
            case .restricted: return "Opens freely, has restrictions"
            case .none?: return "Not protected"
            case nil: return "Can't read this file"
            }
        }
    }

    private var detailColor: Color {
        if case .failed = item.outcome { return .red }
        return .secondary
    }
}

/// A secure text field with a button to show what was typed.
struct PasswordField: View {
    let title: String
    @Binding var text: String
    @State private var reveal = false

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        HStack {
            Group {
                if reveal {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            Button {
                reveal.toggle()
            } label: {
                Image(systemName: reveal ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(reveal ? "Hide password" : "Show password")
        }
    }
}
