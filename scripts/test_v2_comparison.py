"""Compile and exercise the actual coordinator with deterministic client doubles."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Sources/Views/V2PlayerStatsComparisonView.swift').read_text(encoding='utf-8')
start = '@MainActor final class V2ComparisonSide: ObservableObject {'
end = '@MainActor struct V2PlayerStatsComparisonView: View {'
if source.count(start) != 1 or source.count(end) != 1:
    raise RuntimeError('Comparison coordinator extraction anchors changed')
coordinator = source[source.index(start):source.index(end)]
template = (ROOT / 'Tests/V2ComparisonHarness.swift').read_text(encoding='utf-8')
marker = '// INJECT_PRODUCTION_COMPARISON_CLASS'
if template.count(marker) != 1:
    raise RuntimeError('Comparison harness injection anchor changed')
with tempfile.TemporaryDirectory() as directory:
    folder = Path(directory)
    test = folder / 'ComparisonRuntime.swift'
    test.write_text(template.replace(marker, coordinator), encoding='utf-8')
    binary = folder / 'comparison-tests'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                    str(ROOT / 'Sources/Core/PageResource.swift'), str(test), '-o', str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
