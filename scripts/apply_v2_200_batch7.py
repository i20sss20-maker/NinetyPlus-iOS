from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "Sources/Views/V2200FeatureCenter.swift"
text = path.read_text(encoding="utf-8")

if "V2PreferencesBackupView()" not in text:
    needle = '                section("سياسة البيانات") {'
    block = '''                section("الإدارة") {
                    NavigationLink { V2PreferencesBackupView() } label: {
                        toolRow("النسخ والاستعادة", "احفظ تفضيلاتك ومتابعاتك ومثبتاتك محليًا", "externaldrive.badge.icloud")
                    }
                    .buttonStyle(.plain)
                }

'''
    if needle not in text:
        raise SystemExit("feature center insertion point not found")
    text = text.replace(needle, block + needle, 1)

path.write_text(text, encoding="utf-8")
print("Applied seventh 200-feature batch: safe preferences backup and restore")
