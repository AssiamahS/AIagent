# NOTES

- ASC API 401s from this Mac even with a good key: the Mac clock runs ~38h behind, so JWT iat/exp look expired. Mint tokens with real time pulled from an HTTP Date header (see session scripts), or fix the clock.
- Public repo = unlimited free GitHub Actions macOS minutes; private-repo minute caps don't apply. That's the whole free-CI strategy here.
- ASC record 6798731436 ("A.I.agents", SKU "agent") was created pointing at com.assiamah.aurora.watchkitapp; repointed to com.djsly.aiagents via POST /v1/bundleIds then PATCH /v1/apps (register first or the PATCH 500s).
- Brain = GitHub Models free API (models.github.ai, token with models:read pasted in app Settings). No token → built-in question bank + local heuristic report. ElevenLabs key optional for Victoria's voice; falls back to AVSpeechSynthesizer.
- JD scraping: never body.inner_text() — use the tier ladder (JSON-LD JobPosting first; iCIMS/LinkedIn/Lever embed it for Google Jobs). Lives in scipio auto-apply/jd_extract.py + app JDFetcher.swift.
- Walmart careers (and similar Next.js career sites): JD lives in __NEXT_DATA__ props.pageProps.jobDetails (id attr is UNQUOTED — regex quotes must be optional); /reviewCart-style cart/login URLs can never yield a JD, refuse them before fetch/queue.
- Feed data is app-fatal input: Dictionary(uniqueKeysWithValues:) on any remote JSON = crash bomb; always uniquingKeysWith. F500.json had exact-dup rows (Regions Financial, Host Hotels) since day one.
- Resumes tab (1.2.0): reads assiamahs.github.io/scipio/resume_review.json (built by auto-apply/resume_review.py each CI wake); ✓/✗ POSTs to scipio-api /api/resume-verdict and is kept in UserDefaults until the worker answers 200, so the tab works before the worker is deployed. PDFs render in a WKWebView straight off the Pages site.
