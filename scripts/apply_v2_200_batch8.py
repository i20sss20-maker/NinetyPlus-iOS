from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "Sources/Views/V2200FeatureCenter.swift"
text = path.read_text(encoding="utf-8")

if "V2ReminderCenterView()" not in text:
    needle = '                section("الإدارة") {'
    block = '''                section("التذكيرات") {
                    NavigationLink { V2ReminderCenterView() } label: {
                        toolRow("مركز التذكيرات", "عرض وإدارة تنبيهات المباريات المجدولة", "bell.badge.fill")
                    }
                    .buttonStyle(.plain)
                }

'''
    if needle not in text:
        raise SystemExit("management section insertion point not found")
    text = text.replace(needle, block + needle, 1)

path.write_text(text, encoding="utf-8")
print("Applied eighth 200-feature batch: reminder center")
