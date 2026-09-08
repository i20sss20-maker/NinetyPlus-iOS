import SwiftUI

struct V2SavedLineupsView: View {
    @AppStorage("v2.lineup.library.v1") private var saved = ""
    @State private var library = V2LineupLibrary()
    @State private var draft = V2LineupDraft()
    @State private var ready = false
    @State private var storageInvalid = false
    @State private var notice: String?
    @State private var confirmingDelete = false
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TopBar(title: "بناء التشكيلة", subtitle: "حفظ تلقائي على هذا الجهاز")
                if let notice { Text(notice).font(.caption).foregroundStyle(AppTheme.muted).accessibilityIdentifier("lineup.notice") }
                if storageInvalid {
                    Button("بدء مكتبة جديدة") { confirmingReset = true }
                } else {
                    HStack {
                        Menu("التشكيلات المحفوظة") {
                            ForEach(library.drafts) { item in
                                Button(item.title.isEmpty ? "تشكيلة بلا اسم" : item.title) { select(item.id) }
                            }
                        }.accessibilityIdentifier("lineup.library")
                        Spacer()
                        Button("جديدة") { create() }.disabled(library.drafts.count >= V2LineupLibrary.limit)
                            .accessibilityIdentifier("lineup.new")
                        Button(role: .destructive) { confirmingDelete = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("حذف التشكيلة").accessibilityIdentifier("lineup.delete")
                    }
                    TextField("اسم التشكيلة", text: Binding(get: { draft.title }, set: { draft.title = String($0.prefix(60)); persist() }))
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("lineup.title")
                    Picker("الخطة", selection: Binding(get: { draft.formation }, set: { draft.formation = $0; persist() })) {
                        ForEach(V2LineupDraft.formations, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("lineup.formation")
                    pitch
                    Text("\(draft.filledCount) / 11 لاعبًا • تشكيلتك الشخصية وليست تشكيلة رسمية")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                    ForEach(0..<11, id: \.self) { index in
                        HStack {
                            Text(String(index + 1)).foregroundStyle(AppTheme.green).monospacedDigit().frame(width: 28)
                            TextField("اسم اللاعب", text: Binding(get: { draft.names[index] }, set: { draft.names[index] = String($0.prefix(80)); persist() }))
                                .accessibilityLabel("اللاعب \(index + 1)").accessibilityIdentifier("lineup.player.\(index)")
                        }.padding(12).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    ShareLink(item: draft.shareText.englishDigits) {
                        Label("مشاركة التشكيلة", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(14).foregroundStyle(.black)
                            .background(AppTheme.green, in: RoundedRectangle(cornerRadius: 16))
                    }.accessibilityIdentifier("lineup.share")
                }
            }.padding(16).padding(.bottom, 30)
        }
        .background(AppTheme.bg.ignoresSafeArea()).navigationTitle("التشكيلة").navigationBarTitleDisplayMode(.inline)
        .onAppear { restore() }
        .confirmationDialog("حذف هذه التشكيلة من الجهاز؟", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { remove() }
        }
        .confirmationDialog("تعذر قراءة البيانات المحفوظة. استبدالها بمكتبة فارغة؟", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("استبدال البيانات", role: .destructive) {
                library = V2LineupLibrary(); draft = V2LineupDraft(); storageInvalid = false; persist()
            }
        }
    }
    private var pitch: some View {
        VStack(spacing: 16) {
            ForEach(Array(draft.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 4) {
                    ForEach(row, id: \.self) { index in
                        VStack(spacing: 4) {
                            Text(String(index + 1)).font(.caption.bold()).frame(width: 30, height: 30)
                                .background(AppTheme.green.opacity(0.18), in: Circle()).foregroundStyle(AppTheme.green)
                            Text(draft.names[index].isEmpty ? "—" : draft.names[index]).font(.caption2).lineLimit(2)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }.padding(16).frame(maxWidth: .infinity).background(AppTheme.cardRaised, in: RoundedRectangle(cornerRadius: 20))
    }
    private func restore() {
        guard !ready else { return }; ready = true
        do {
            library = try V2LineupLibrary.decode(saved)
            draft = library.selected ?? library.drafts.first ?? V2LineupDraft()
            persist()
        } catch {
            storageInvalid = true
            notice = "تعذر قراءة مكتبة التشكيلات. لم نحذف بياناتك أو نستبدلها."
        }
    }
    private func persist() {
        guard ready, !storageInvalid else { return }
        do {
            draft.updatedAt = Date()
            try library.save(draft)
            saved = try library.encoded()
            notice = "محفوظة على هذا الجهاز"
        } catch { notice = "تعذر الحفظ. لم نستبدل النسخة المحفوظة." }
    }
    private func create() {
        guard library.drafts.count < V2LineupLibrary.limit else { return }
        draft = V2LineupDraft(); persist()
    }
    private func select(_ id: UUID) {
        library.select(id)
        guard let value = library.selected else { return }
        draft = value; persist()
    }
    private func remove() {
        library.remove(draft.id)
        draft = library.selected ?? V2LineupDraft()
        persist()
    }
}
