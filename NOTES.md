# NOTES

- ASC API 401s from this Mac even with a good key: the Mac clock runs ~38h behind, so JWT iat/exp look expired. Mint tokens with real time pulled from an HTTP Date header (see session scripts), or fix the clock.
- Public repo = unlimited free GitHub Actions macOS minutes; private-repo minute caps don't apply. That's the whole free-CI strategy here.
- ASC record 6798731436 ("A.I.agents", SKU "agent") was created pointing at com.assiamah.aurora.watchkitapp; repointed to com.djsly.aiagents via POST /v1/bundleIds then PATCH /v1/apps (register first or the PATCH 500s).
- Brain = GitHub Models free API (models.github.ai, token with models:read pasted in app Settings). No token → built-in question bank + local heuristic report. ElevenLabs key optional for Victoria's voice; falls back to AVSpeechSynthesizer.
