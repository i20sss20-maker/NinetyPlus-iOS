from pathlib import Path
from premium_experiences import apply_premium, once
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PremiumIntegrationTests(unittest.TestCase):
    def test_anchors_fail_closed(self):
        for text in ['missing', 'old old', 'new new', 'old new']:
            with self.assertRaises(RuntimeError): once(text, 'old', 'new', 'test')
    def test_generated_chain_is_idempotent(self):
        before = {p: p.read_bytes() for p in (ROOT / 'Sources').rglob('*.swift')}
        apply_premium(ROOT)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
    def test_real_feature_wiring(self):
        def source(p): return (ROOT / p).read_text()
        self.assertIn('home.pulse', source('Sources/Views/V2HomeView.swift'))
        self.assertIn('PremiumFootballStore.shared.observe', source('Sources/Views/RootView.swift'))
        self.assertIn('PremiumMatchExperience(seed: match, store: store)', source('Sources/Views/V2MatchExperience.swift'))
        self.assertIn('team.dna', source('Sources/Views/V2Discovery.swift'))
        lineup = source('Sources/Views/V2SavedLineupsView.swift')
        self.assertIn('PremiumInteractivePitch(draft: $draft, persist: persist)', lineup)
        self.assertNotIn('private var pitch:', lineup)
        self.assertIn('more.power', source('Sources/Views/V2Personalization.swift'))
    def test_shared_platform_guards_still_present(self):
        match = (ROOT / 'Sources/Views/V2MatchExperience.swift').read_text()
        self.assertIn('progress.cancel(.fixture, token: token)', match)
        self.assertIn('hidingScore: spoilerMode', match)
        self.assertIn('for (section, token) in tokens { progress.cancel(section, token: token) }', match)

if __name__ == '__main__': unittest.main(verbosity=2)
