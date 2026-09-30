import AppKit
import SwiftUI
import TodoCore

/// A compact replacement for the ordinary list body, never an attached sheet.
struct CatalogRecoveryView: View {
    @ObservedObject var model: AppModel
    @State private var showsDetails = false
    @State private var showsIssues = false

    var body: some View {
        if model.isCatalogRecoveryPresented { review }
        else { unavailable }
    }

    private var unavailable: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 8) {
                        Text("Let's reconnect your lists")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Chit can't read its list index.\nYour list files are kept separately.")
                            .font(.system(size: 12))
                            .foregroundStyle(Mocha.secondary)
                            .multilineTextAlignment(.center)
                        if model.hasRetainedWork {
                            Text("Your unsaved text is kept in Chit.")
                                .font(.system(size: 11)).foregroundStyle(Mocha.secondary)
                        }
                        DisclosureGroup("Details", isExpanded: $showsDetails) {
                            Text(model.errorMessage ?? "The list index is unavailable.")
                                .font(.system(size: 11))
                                .foregroundStyle(Mocha.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: 340)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            HStack(spacing: 10) {
                Button("Retry") { model.refresh() }
                Button("Rebuild List Index…") { _ = model.beginCatalogRecovery() }
            }
            .font(.system(size: 12)).controlSize(.small)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("List index recovery")
    }

    private var review: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Rebuild List Index").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button("Refresh Preview") { _ = model.refreshCatalogRecovery() }
                    .font(.system(size: 11)).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Groups and list order reset. Your list files stay unchanged.")
                        .foregroundStyle(Mocha.secondary)
                    Text("Previously hidden lists may appear. Uncheck any you want to keep hidden.")
                        .foregroundStyle(Mocha.secondary)
                    if let error = model.catalogRecoveryErrorMessage {
                        Text(error).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Mocha.hover, in: RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel("Recovery error: " + error)
                    }
                    if let plan = model.catalogRecoveryPlan {
                        if plan.candidates.isEmpty {
                            Text("No readable lists found. Choose list files, or start with an empty index.")
                                .foregroundStyle(Mocha.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(plan.candidates, id: \.url) { candidate in
                                    Toggle(isOn: Binding(
                                        get: { model.catalogRecoverySelectedURLs.contains(candidate.url) },
                                        set: { model.setCatalogRecoverySelection(candidate.url, isSelected: $0) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.name).font(.system(size: 12)).lineLimit(1)
                                            Text(candidate.url.path).font(.system(size: 10))
                                                .foregroundStyle(Mocha.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .toggleStyle(.checkbox).controlSize(.small)
                                    .help(candidate.url.path)
                                    .accessibilityLabel(candidate.name + ", " + candidate.url.path)
                                }
                            }
                        }
                        if !plan.issues.isEmpty {
                            DisclosureGroup("Skipped files (\(plan.issues.count))", isExpanded: $showsIssues) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(plan.issues.enumerated()), id: \.offset) { _, issue in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(issue.url.path).lineLimit(1).truncationMode(.middle)
                                                .help(issue.url.path)
                                            Text(issue.message).textSelection(.enabled)
                                        }
                                    }
                                }
                                .foregroundStyle(Mocha.secondary).padding(.top, 5)
                            }
                        }
                    }
                    Button("Choose List Files…") { ListActions.chooseCatalogRecoveryFiles(model: model) }
                        .controlSize(.small)
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 3).padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 6) {
                if model.catalogRecoveryPlan != nil && model.catalogRecoverySelectedURLs.isEmpty {
                    Text("You can Open List later. Every file will be preserved.")
                        .font(.system(size: 10)).foregroundStyle(Mocha.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Cancel") { model.cancelCatalogRecovery() }
                        .keyboardShortcut(.cancelAction)
                    Spacer(minLength: 8)
                    Button(model.catalogRecoverySelectedURLs.isEmpty ? "Start Empty" : "Rebuild") {
                        _ = model.rebuildCatalog()
                    }
                    .disabled(model.catalogRecoveryPlan == nil)
                }
                .font(.system(size: 12)).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
            .background(Mocha.hover.opacity(0.35))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review recovered lists")
    }
}

struct CatalogRecoveryHeader: View {
    var body: some View {
        HStack(spacing: 2) {
            PanelCloseControl().frame(width: 22, height: 26)
            Spacer(minLength: 0)
        }
        .background { HeaderDragArea(excludedRects: [CGRect(x: 0, y: 0, width: 22, height: 26)]) }
    }
}

struct CatalogRecoveryNoticeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let notice = model.catalogRecoveryNotice {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("List index rebuilt.").fontWeight(.medium)
                    if model.hasRetainedWork { Text("Your unsaved text is kept in Chit.") }
                    HStack(spacing: 10) {
                        if let url = notice.preservedCatalogURL {
                            Button("Show Preserved Index") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("Open List…") { ListActions.open(model: model) }
                    }
                    .buttonStyle(.link)
                }
                Spacer(minLength: 0)
                Button { model.dismissCatalogRecoveryNotice() } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss recovery notice")
            }
            .font(.system(size: 11)).foregroundStyle(Mocha.secondary)
            .padding(8).background(Mocha.hover, in: RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 10).padding(.bottom, 5)
        }
    }
}
