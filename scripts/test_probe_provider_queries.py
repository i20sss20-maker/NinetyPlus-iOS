"""Offline regression tests; these must not consume provider quota."""
import datetime
import unittest
from unittest.mock import Mock, patch

import probe_provider_queries as diagnostic


class ProviderDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.health = {
            'ok': True, 'providerConfigured': True, 'providerRemoteBlocked': False,
            'providerRequestsToday': 1, 'providerDailyBudget': 90, 'providerBudgetRemaining': 89,
        }
        self.today = datetime.date(2026, 9, 8)
        self.team = (200, {'errors': [], 'response': [{'team': {'id': 857, 'name': 'Al-Ittihad'}}]})
        self.empty_fixtures = (200, {'errors': [], 'response': []})

    def run_probe(self, *responses, health=None):
        fetch = Mock(side_effect=[(200, self.health if health is None else health), *responses])
        report = diagnostic.probe(fetch=fetch, today=self.today)
        return report, fetch

    def test_remote_block_is_skipped_without_provider_calls(self):
        self.health.update(providerRemoteBlocked=True, providerBudgetRemaining=0)
        report, fetch = self.run_probe()
        self.assertEqual(report['outcome'], 'skipped')
        self.assertIn('NOT verified', report['reason'])
        self.assertEqual(fetch.call_count, 1)
        self.assertEqual(diagnostic.exit_code(report), 0)

    def test_unconfigured_provider_is_skipped(self):
        self.health['providerConfigured'] = False
        report, fetch = self.run_probe()
        self.assertEqual(report['outcome'], 'skipped')
        self.assertEqual(fetch.call_count, 1)

    def test_low_local_or_remote_budget_is_skipped(self):
        for update in ({'providerRequestsToday': 88}, {'providerBudgetRemaining': 0}):
            with self.subTest(update=update):
                report, fetch = self.run_probe(health={**self.health, **update})
                self.assertEqual(report['outcome'], 'skipped')
                self.assertEqual(fetch.call_count, 1)

    def test_malformed_health_fails_without_provider_calls(self):
        for status, body in ((503, self.health), (200, []), (200, {'ok': False})):
            with self.subTest(status=status, body=body):
                fetch = Mock(return_value=(status, body))
                report = diagnostic.probe(fetch=fetch, today=self.today)
                self.assertEqual(report['outcome'], 'failed')
                self.assertEqual(fetch.call_count, 1)
                self.assertEqual(diagnostic.exit_code(report), 1)

    def test_invalid_budget_fails_closed(self):
        for value in (None, '89', True, -1):
            with self.subTest(value=value):
                report, fetch = self.run_probe(health={**self.health, 'providerBudgetRemaining': value})
                self.assertEqual(report['outcome'], 'failed')
                self.assertEqual(fetch.call_count, 1)

    def test_legacy_health_uses_local_budget(self):
        del self.health['providerBudgetRemaining']
        report, fetch = self.run_probe(self.team, self.empty_fixtures, self.empty_fixtures)
        self.assertEqual(report['outcome'], 'passed')
        self.assertEqual(fetch.call_count, 4)

    def test_valid_queries_pass_with_empty_fixture_days(self):
        report, fetch = self.run_probe(self.team, self.empty_fixtures, self.empty_fixtures)
        self.assertEqual(report['outcome'], 'passed')
        self.assertEqual(diagnostic.exit_code(report), 0)
        self.assertEqual(len(report['checks']), 3)
        self.assertIn('date=2026-09-09', fetch.call_args_list[2].args[0])
        self.assertIn('date=2026-09-07', fetch.call_args_list[3].args[0])

    def test_unexpected_http_failures_stop_and_fail(self):
        for status in (429, 500, None):
            with self.subTest(status=status):
                report, fetch = self.run_probe((status, {'response': [], 'message': 'blocked'}))
                self.assertEqual(report['outcome'], 'failed')
                self.assertEqual(diagnostic.exit_code(report), 1)
                self.assertEqual(fetch.call_count, 2)
                self.assertEqual(report['checks'][0]['responseBody']['message'], 'blocked')

    def test_http_200_plan_error_fails(self):
        report, fetch = self.run_probe((200, {'errors': {'plan': 'restricted'}, 'response': []}))
        self.assertEqual(report['outcome'], 'failed')
        self.assertEqual(fetch.call_count, 2)

    def test_invalid_response_shapes_fail(self):
        for payload in ([], {}, {'response': {}}, {'response': [None]}, {'response': [{'team': None}]}):
            with self.subTest(payload=payload):
                report, _ = self.run_probe((200, payload))
                self.assertEqual(report['outcome'], 'failed')

    def test_empty_known_team_search_is_not_success(self):
        report, _ = self.run_probe(self.empty_fixtures)
        self.assertEqual(report['outcome'], 'failed')

    def test_failure_after_success_stops_remaining_requests(self):
        report, fetch = self.run_probe(self.team, (429, {'errors': ['limit']}))
        self.assertEqual(report['outcome'], 'failed')
        self.assertEqual(len(report['checks']), 2)
        self.assertEqual(report['checks'][0]['outcome'], 'passed')
        self.assertEqual(fetch.call_count, 3)

    def test_http_error_body_is_preserved(self):
        import io
        import urllib.error
        error = urllib.error.HTTPError('https://example.invalid', 429, 'limit', {}, io.BytesIO(b'{"message":"quota"}'))
        with patch('urllib.request.urlopen', side_effect=error):
            status, payload = diagnostic.get_json('https://example.invalid')
        self.assertEqual(status, 429)
        self.assertEqual(payload, {'message': 'quota'})


if __name__ == '__main__':
    unittest.main()
