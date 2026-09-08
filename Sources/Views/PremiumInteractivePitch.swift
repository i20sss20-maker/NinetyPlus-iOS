import SwiftUI
import UIKit

struct PremiumInteractivePitch: View {
    @Binding var draft: V2LineupDraft
    let persist: () -> Void
    @State private var rendered: UIImage?
    @State private var sharing = false
    @State private var exportError = false
    private var captain: Binding<Int> {
        Binding(get: { draft.captainIndex ?? -1 }, set: { draft.captainIndex = $0 >= 0 ? $0 : nil; persist() })
    }
    var body: some View {
        VStack(spacing: 14) {
            Text("اسحب رقم لاعب إلى آخر لتبديل موقعيهما، أو استخدم قائمة اللاعب.").font(.caption).foregroundStyle(AppTheme.muted)
            VStack(spacing: 18) {
                ForEach(Array(draft.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(row, id: \.self) { index in
                            Menu {
                                ForEach(0..<11, id: \.self) { target in
                                    if target != index { Button("تبديل مع \(target + 1)") { swap(index, target) } }
                                }
                            } label: { player(index) }
                            .draggable("np-lineup:\(draft.id.uuidString):\(index)")
                            .dropDestination(for: String.self) { values, _ in
                                guard values.count == 1 else { return false }
                                let parts = values[0].split(separator: ":")
                                guard parts.count == 3, parts[0] == "np-lineup", parts[1] == Substring(draft.id.uuidString), let from = Int(parts[2]) else { return false }
                                return swap(from, index)
                            }
                            .accessibilityLabel("موقع \(index + 1)، \(draft.names[index])")
                        }
                    }
                }
            }.padding(16).frame(maxWidth: .infinity).background(AppTheme.greenDeep.opacity(0.35), in: RoundedRectangle(cornerRadius: 22))
            Picker("القائد", selection: captain) {
                Text("بدون قائد").tag(-1)
                ForEach(0..<11, id: \.self) { Text("\($0 + 1) • \(draft.names[$0].isEmpty ? "لاعب" : draft.names[$0])").tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("lineup.captain")
            Text("دكة البدلاء").font(.headline)
            ForEach(0..<(draft.bench?.count ?? 0), id: \.self) { index in
                HStack {
                    TextField("اسم البديل", text: Binding(get: { benchName(index) }, set: { editBench(index, value: $0) }))
                    Button(role: .destructive) { removeBench(index) } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("حذف البديل \(index + 1)")
                }.padding(10).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            Button("إضافة بديل") {
                var bench = draft.bench ?? []
                guard bench.count < 9 else { return }
                bench.append(""); draft.bench = bench; persist()
            }.disabled((draft.bench?.count ?? 0) >= 9).accessibilityIdentifier("lineup.addSubstitute")
            Button { export() } label: { Label("مشاركة التشكيلة كصورة", systemImage: "photo.on.rectangle") }
                .accessibilityIdentifier("lineup.shareImage")
            if exportError { Text("تعذر تجهيز الصورة. المشاركة النصية ما زالت متاحة.").font(.caption) }
        }
        .sheet(isPresented: $sharing) { if let rendered { PremiumImageShare(image: rendered) } }
    }
    private func player(_ index: Int) -> some View {
        VStack(spacing: 5) {
            Text("\(index + 1)\(draft.captainIndex == index ? " C" : "")")
                .font(.caption.bold()).frame(minWidth: 32, minHeight: 32).background(AppTheme.green.opacity(0.2), in: Circle()).foregroundStyle(AppTheme.green)
            Text(draft.names[index].isEmpty ? "—" : draft.names[index]).font(.caption2).foregroundStyle(.white).lineLimit(2)
        }.frame(maxWidth: .infinity)
    }
    @discardableResult private func swap(_ from: Int, _ to: Int) -> Bool {
        guard let names = PremiumLineupRules.swapped(draft.names, from: from, to: to) else { return false }
        draft.names = names
        if draft.captainIndex == from { draft.captainIndex = to } else if draft.captainIndex == to { draft.captainIndex = from }
        persist(); return true
    }
    private func benchName(_ index: Int) -> String {
        guard let bench = draft.bench, bench.indices.contains(index) else { return "" }
        return bench[index]
    }
    private func editBench(_ index: Int, value: String) {
        guard var bench = draft.bench, bench.indices.contains(index) else { return }
        bench[index] = String(value.prefix(80)); draft.bench = bench; persist()
    }
    private func removeBench(_ index: Int) {
        guard var bench = draft.bench, bench.indices.contains(index) else { return }
        bench.remove(at: index); draft.bench = bench; persist()
    }
    @MainActor private func export() {
        let renderer = ImageRenderer(content: PremiumLineupShareCard(draft: draft)
            .environment(\.locale, SportsDisplayDate.locale).environment(\.layoutDirection, .rightToLeft))
        renderer.scale = 2
        guard let image = renderer.uiImage else { exportError = true; return }
        rendered = image; exportError = false; sharing = true
    }
}

private struct PremiumLineupShareCard: View {
    let draft: V2LineupDraft
    var body: some View {
        VStack(spacing: 24) {
            BrandLogo()
            Text(draft.title.isEmpty ? "تشكيلتي" : draft.title).font(.title.bold())
            Text(draft.formation).font(.title2.bold()).monospacedDigit()
            ForEach(Array(draft.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row, id: \.self) { index in
                        VStack(spacing: 8) {
                            Text("\(index + 1)\(draft.captainIndex == index ? " C" : "")")
                                .font(.headline).padding(12).background(AppTheme.green.opacity(0.2), in: Circle())
                            Text(draft.names[index].isEmpty ? "—" : draft.names[index]).font(.subheadline.bold()).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            if let bench = draft.bench, !bench.isEmpty {
                Text("البدلاء: \(bench.filter { !$0.isEmpty }.joined(separator: " • "))").font(.caption)
            }
            Text("تشكيلة من إعداد المستخدم • ليست تشكيلة رسمية").font(.caption).foregroundStyle(AppTheme.muted)
        }.foregroundStyle(.white).padding(32).frame(width: 640).background(AppTheme.bg)
    }
}
private struct PremiumImageShare: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [image], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
