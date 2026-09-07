import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / 'scripts' / 'probe_service.py'
spec = importlib.util.spec_from_file_location('probe_service', path)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class ServiceProbeTests(unittest.TestCase):
    def test_http_200_provider_error_is_failure(self):
        result = probe.summarize({'status': 200, 'payload': {'errors': {'plan': 'unavailable'}, 'response': []}}, 'team')
        self.assertFalse(result['ok'])
        self.assertEqual(result['errorKeys'], ['plan'])

    def test_success_requires_real_named_records(self):
        self.assertFalse(probe.summarize({'status': 200, 'payload': {'response': []}}, 'team')['ok'])
        self.assertFalse(probe.summarize({'status': 200, 'payload': {'response': [{}]}}, 'team')['ok'])
        self.assertTrue(probe.summarize({'status': 200, 'payload': {'errors': [], 'response': [{'team': {'name': 'Test record'}}]}}, 'team')['ok'])

    def test_health_failure_consumes_no_football_requests(self):
        paths = []
        def fetch(path):
            paths.append(path)
            return {'status': 503}
        result = probe.probe(fetch)
        self.assertEqual(paths, ['/api/health'])
        self.assertEqual(result['footballRequests'], 0)
        self.assertFalse(result['ok'])

    def test_daily_budget_is_respected(self):
        paths = []
        def fetch(path):
            paths.append(path)
            return {'status': 200, 'payload': {'ok': True, 'providerConfigured': True, 'providerDailyBudget': 90, 'providerRequestsToday': 89}}
        self.assertEqual(probe.probe(fetch)['footballRequests'], 0)
        self.assertEqual(len(paths), 1)

    def test_healthy_probe_makes_exactly_two_football_requests(self):
        paths = []
        def fetch(path):
            paths.append(path)
            if path == '/api/health':
                return {'status': 200, 'payload': {'ok': True, 'providerConfigured': True, 'providerDailyBudget': 90, 'providerRequestsToday': 0}}
            entity = 'player' if 'players' in path else 'team'
            return {'status': 200, 'cache': 'HIT', 'payload': {'errors': {}, 'response': [{entity: {'name': 'Test record'}}]}}
        result = probe.probe(fetch)
        self.assertEqual(result['footballRequests'], 2)
        self.assertEqual(len(paths), 3)
        self.assertTrue(result['ok'])

if __name__ == '__main__':
    unittest.main()
