"""Guarded, idempotent transformation of the generated canonical match loader."""


def apply_match_center_recovery(source: str) -> str:
    start_marker = '    private func loadCanonical(_ match: APIPlusMatch, force: Bool) async {'
    end_marker = '    private func map(_ item: APIFixture) -> APIPlusMatch {'
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise RuntimeError('canonical recovery: expected exactly one loader and map anchor')
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    method = source[start:end]

    original = '''            for (section, token) in tokens { progress.fail(section, token: token, message: error.localizedDescription) }'''
    previous = '''            if let token = tokens[.fixture] {
                _ = progress.succeed(.fixture, token: token, hasContent: true)
            }
            for (section, token) in tokens where section != .fixture {
                progress.fail(section, token: token, message: error.localizedDescription)
            }'''
    replacement = '''            // Keep the header snapshot without claiming a successful refresh.
            // Cancellation preserves the last successful value and timestamp.
            if let token = tokens[.fixture] {
                progress.cancel(.fixture, token: token)
            }
            for (section, token) in tokens where section != .fixture {
                progress.fail(section, token: token, message: error.localizedDescription)
            }'''
    if replacement not in method:
        if previous in method:
            method = method.replace(previous, replacement, 1)
        elif original in method:
            method = method.replace(original, replacement, 1)
        else:
            raise RuntimeError('canonical recovery: failure handler anchor missing')

    original_guard = '''        guard !tokens.isEmpty else { return }
        do {'''
    cleanup_guard = '''        guard !tokens.isEmpty else { return }
        defer {
            // Only release this request's tokens, never a newer refresh's tokens.
            for (section, token) in tokens { progress.cancel(section, token: token) }
        }
        do {'''
    if cleanup_guard not in method:
        if original_guard not in method:
            raise RuntimeError('canonical recovery: token cleanup anchor missing')
        method = method.replace(original_guard, cleanup_guard, 1)
    return source[:start] + method + source[end:]
