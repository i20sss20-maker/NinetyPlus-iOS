"""Run after the full release transform chain, against its actual Swift output."""
from pathlib import Path
import unittest
from v2_feature_completion import patch, once

ROOT = Path(__file__).resolve().parents[1]


class FeatureIntegrationTests(unittest.TestCase):
    def test_guard_rejects_unknown_or_duplicate_anchor(self):
        for text in ['other', 'old old', 'old new', 'new new']:
            with self.assertRaises(RuntimeError): once(text, 'old', 'new', 'test')

    def test_guard_idempotent(self):
        self.assertEqual(once('prefix new suffix', 'old', 'new', 'test'), 'prefix new suffix')

    def test_full_generated_output_is_idempotent(self):
        paths = ['Sources/Views/V2PowerCenter.swift', 'Sources/Views/RootView.swift',
                 'Sources/Core/V2ProductPlatform.swift', 'Sources/Views/V2MatchExperience.swift']
        before = {p: (ROOT / p).read_text(encoding='utf-8') for p in paths}
        self.assertEqual(patch(before), before)
        self.assertIn('V2SavedLineupsView()', before[paths[0]])
        self.assertIn('V2PlayerStatsComparisonView()', before[paths[0]])
        self.assertNotIn('struct PlayerCompareView:', before[paths[0]])
        self.assertNotIn('struct V2LineupBuilderView:', before[paths[0]])
        self.assertIn('.sheet(item: $linkedRoute)', before[paths[1]])
        self.assertIn('hidingScore: spoilerMode', before[paths[3]])
        self.assertIn('lowDataMode ? max(baseInterval, 120)', before[paths[3]])
        self.assertIn('progress.cancel(.fixture, token: token)', before[paths[3]])
        self.assertIn('for (section, token) in tokens { progress.cancel(section, token: token) }', before[paths[3]])


if __name__ == '__main__':
    unittest.main(verbosity=2)
