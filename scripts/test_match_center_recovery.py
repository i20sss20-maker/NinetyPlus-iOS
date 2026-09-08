"""Test the generated production method with real resource state and a fake client.

No source provider or UI simulator is needed. The Swift test reuses the app's
PageResource and MatchCenterProgress implementations and injects the loader
literal from the release transform, rather than maintaining a second loader.
"""
import ast
from pathlib import Path
import subprocess
import tempfile
import unittest

from match_center_recovery import apply_match_center_recovery

ROOT = Path(__file__).resolve().parents[1]
MAP_ANCHOR = '    private func map(_ item: APIFixture) -> APIPlusMatch {'


def production_method() -> str:
    tree = ast.parse((ROOT / 'scripts/apply_release_ui_fixes.py').read_text(encoding='utf-8'))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'canonical_method' for t in node.targets):
            value = ast.literal_eval(node.value)
            if isinstance(value, str):
                return value
    raise RuntimeError('production canonical method literal not found')


class CanonicalTransformTests(unittest.TestCase):
    def setUp(self):
        self.source = production_method() + '\n' + MAP_ANCHOR + '\n'

    def test_idempotent(self):
        fixed = apply_match_center_recovery(self.source)
        self.assertEqual(fixed, apply_match_center_recovery(fixed))
        self.assertEqual(fixed.count('defer {'), 1)

    def test_outside_loader_unchanged(self):
        prefix = '// unrelated prefix\n'
        suffix = '// unrelated suffix\n'
        fixed = apply_match_center_recovery(prefix + self.source + suffix)
        self.assertTrue(fixed.startswith(prefix))
        self.assertTrue(fixed.endswith(MAP_ANCHOR + '\n' + suffix))

    def test_previous_fallback_upgraded(self):
        old = '            for (section, token) in tokens { progress.fail(section, token: token, message: error.localizedDescription) }'
        previous = '''            if let token = tokens[.fixture] {
                _ = progress.succeed(.fixture, token: token, hasContent: true)
            }
            for (section, token) in tokens where section != .fixture {
                progress.fail(section, token: token, message: error.localizedDescription)
            }'''
        self.assertEqual(apply_match_center_recovery(self.source), apply_match_center_recovery(self.source.replace(old, previous)))

    def test_missing_anchor_fails(self):
        with self.assertRaises(RuntimeError):
            apply_match_center_recovery(self.source.replace('guard !tokens.isEmpty else { return }', 'guard true else { return }'))

    def test_duplicate_loader_fails(self):
        with self.assertRaises(RuntimeError):
            apply_match_center_recovery(self.source + self.source)

    def test_swift_runtime(self):
        fixed = apply_match_center_recovery(self.source).split(MAP_ANCHOR)[0]
        # Widen visibility only, so the harness can call the production method.
        fixed = fixed.replace('private func loadCanonical', 'func loadCanonical', 1)
        template = (ROOT / 'Tests/CanonicalRecoveryHarness.swift').read_text(encoding='utf-8')
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            source = folder / 'CanonicalRecovery.swift'
            source.write_text(template.replace('    // INJECT_PRODUCTION_CANONICAL_METHOD', fixed), encoding='utf-8')
            binary = folder / 'canonical-recovery-tests'
            subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                            str(ROOT / 'Sources/Core/PageResource.swift'),
                            str(ROOT / 'Sources/Core/MatchCenterProgress.swift'),
                            str(source), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == '__main__':
    unittest.main(verbosity=2)
