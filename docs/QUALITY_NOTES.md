# 90+ data and quality boundaries

The configured API-Football free account was tested on 2026-09-07. Search and dated fixtures work. Current-season standings and Next requests return HTTP 200 with plan errors. Such errors are not empty successful results.

Club fixtures now filter supported shared date requests, covering today plus seven future days, or seven past days plus today. This is a bounded published schedule, not the club's complete season. Successful day requests are shared between clubs and cached; provider daily limits still apply.

The native current-league table uses an additional public ESPN source with explicit attribution. It validates returned season start/end dates, preserves missing statistics and keeps ESPN identifiers separate from API-Football identifiers. Club links in this table go to the source's club page. This public endpoint is not a contracted data SLA; commercial redistribution permissions and production licensing still require review.

Article photos come only from each article's published RSS media fields or associated image element. The tested feeds are https://hihi2.com/feed and https://www.france24.com/ar/رياضة/rss. Headlines link to and credit their publishers. Google News remains a separate source of source-linked headlines; it is not claimed to supply photos. Publisher dates are never replaced with the current date.

Current-player season statistics and the API-Football scorers endpoint may remain restricted by the free plan. Restricted statistics are not replaced with old-season numbers. This version does not implement APNs/background push.

The visual QA workflow launches the actual SwiftUI app on an iPhone simulator with real network responses. It records screenshots and the accessibility tree for navigation, Arabic Saudi-club search, the club page, news imagery, the current Saudi table and the match center. CI success must be inspected separately from IPA compilation. A simulator run does not establish testing on a physical iPhone.
