"""Compile production free-source code and exercise disk recovery and real DTOs."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    store = (root / 'Sources/Core/APISportsStore.swift').read_text()
    client = (root / 'Sources/Core/APIFootballClient.swift').read_text()
    models = store[:store.index('private actor SharedFixtureDays')]
    models += client[client.index('struct APIEnvelope'):]
    models += '''
enum APIFootballError: Error { case badResponse, serviceUnavailable, missingConfiguration, rateLimited }
enum APIFootballClient { static var backendURL: URL? { nil } }
enum SportsArabic { static func team(_ value: String) -> String { value } }
'''
    (tmp / 'Models.swift').write_text(models)
    files = ['PublicLeagueTable', 'EnglishDigits', 'PageResource', 'PublicScoreboard', 'CanonicalSportsClient', 'FreeCoverageError', 'FreeSportsDirectory', 'FreeFixtureFeed', 'FreeMatchDetail']
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(tmp / 'Models.swift')] +
        [str(root / 'Sources/Core' / (f + '.swift')) for f in files] +
        [str(root / 'Tests/FreeSourcesTests.swift'), '-o', str(tmp / 'tests')], check=True)
    subprocess.run([str(tmp / 'tests')], cwd=root, check=True)
