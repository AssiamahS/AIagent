import Foundation

/// Paste a job URL → company, role, and a clean job description.
///
/// Same tier ladder scipio's jd_extract.py uses:
///   1. Greenhouse/Lever public APIs when the URL is theirs (cleanest)
///   2. schema.org/JobPosting JSON-LD in the page HTML (iCIMS, LinkedIn…)
///   3. og:description meta tag
///   4. page text with the nav/cookie-wall junk lines dropped
enum JDFetcher {

    struct Result {
        var company: String?
        var role: String?
        var jobDescription: String?
    }

    /// Which ATS a URL belongs to and whether scipio can actually auto-submit there.
    static func atsInfo(for urlString: String) -> (name: String, autoSubmit: Bool)? {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return nil }
        if host.contains("greenhouse.io") { return ("Greenhouse", true) }
        if host.contains("lever.co") { return ("Lever", true) }
        if host.contains("icims.com") { return ("iCIMS", false) }
        if host.contains("myworkdayjobs.com") { return ("Workday", false) }
        if host.contains("ashbyhq.com") { return ("Ashby", false) }
        if host.contains("smartrecruiters.com") { return ("SmartRecruiters", false) }
        if host.contains("taleo.net") { return ("Taleo", false) }
        if host.contains("workable.com") { return ("Workable", false) }
        return nil
    }

    static func fetch(from urlString: String) async -> Result {
        guard let url = URL(string: urlString) else { return Result() }

        if let api = apiResult(for: url), let r = await api() { return r }

        guard let html = await fetchHTML(url) else { return Result() }
        if let r = fromJSONLD(html) { return r }
        if let r = fromOGDescription(html) { return r }
        let text = cleanLines(JobSearchView.stripHTML(html))
        return Result(company: nil, role: nil,
                      jobDescription: text.count > 300 ? String(text.prefix(8000)) : nil)
    }

    // MARK: - Tier 1: ATS public APIs

    /// Greenhouse: boards.greenhouse.io/<slug>/jobs/<id> has a public JSON API.
    /// Lever: jobs.lever.co/<slug>/<posting-id> likewise.
    private static func apiResult(for url: URL) -> (() async -> Result?)? {
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        if host.contains("greenhouse.io"),
           let idx = parts.firstIndex(of: "jobs"), idx > 0, idx + 1 < parts.count {
            let slug = parts[idx - 1], id = parts[idx + 1]
            return {
                struct GH: Codable { let title: String?; let content: String?; let company_name: String? }
                guard let api = URL(string: "https://boards-api.greenhouse.io/v1/boards/\(slug)/jobs/\(id)"),
                      let (data, _) = try? await URLSession.shared.data(from: api),
                      let job = try? JSONDecoder().decode(GH.self, from: data),
                      let content = job.content else { return nil }
                return Result(company: job.company_name ?? slug.capitalized,
                              role: job.title,
                              jobDescription: String(JobSearchView.stripHTML(content).prefix(8000)))
            }
        }
        if host.contains("lever.co"), parts.count >= 2 {
            let slug = parts[0], id = parts[1]
            return {
                struct LV: Codable { let text: String?; let descriptionPlain: String? }
                guard let api = URL(string: "https://api.lever.co/v0/postings/\(slug)/\(id)"),
                      let (data, _) = try? await URLSession.shared.data(from: api),
                      let job = try? JSONDecoder().decode(LV.self, from: data),
                      let desc = job.descriptionPlain else { return nil }
                return Result(company: slug.capitalized, role: job.text,
                              jobDescription: String(desc.prefix(8000)))
            }
        }
        return nil
    }

    // MARK: - Tier 2: JSON-LD JobPosting

    private static func fromJSONLD(_ html: String) -> Result? {
        let pattern = "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let ns = html as NSString
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: m.range(at: 1))
            guard let data = raw.data(using: .utf8),
                  let doc = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let posting = findJobPosting(doc) else { continue }
            let desc = JobSearchView.stripHTML(posting["description"] as? String ?? "")
            guard desc.count > 200 else { continue }
            var company: String?
            if let org = posting["hiringOrganization"] as? [String: Any] {
                company = org["name"] as? String
            } else {
                company = posting["hiringOrganization"] as? String
            }
            return Result(company: company,
                          role: posting["title"] as? String,
                          jobDescription: String(desc.prefix(8000)))
        }
        return nil
    }

    private static func findJobPosting(_ node: Any) -> [String: Any]? {
        if let list = node as? [Any] {
            for item in list { if let hit = findJobPosting(item) { return hit } }
            return nil
        }
        guard let dict = node as? [String: Any] else { return nil }
        let types: [String]
        if let t = dict["@type"] as? String { types = [t] }
        else if let t = dict["@type"] as? [String] { types = t }
        else { types = [] }
        if types.contains("JobPosting") { return dict }
        if let graph = dict["@graph"] { return findJobPosting(graph) }
        return nil
    }

    // MARK: - Tier 3 + 4: meta tag, filtered text

    private static func fromOGDescription(_ html: String) -> Result? {
        let pattern = "<meta[^>]+property\\s*=\\s*[\"']og:description[\"'][^>]+content\\s*=\\s*[\"']([^\"']{300,})[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return Result(company: nil, role: nil,
                      jobDescription: String(JobSearchView.stripHTML(String(html[r])).prefix(8000)))
    }

    private static let junkLine = try? NSRegularExpression(
        pattern: "^(login|log in|sign in|sign up|register|welcome page|enter your information"
            + "|email|password|apply now|save job|share|print|back to search"
            + "|please enable cookies.*|cookie.*polic.*|accept.*cookies.*|privacy policy"
            + "|terms of use|skip to (main )?content|menu|search jobs?|home|careers?|faq|help)$",
        options: [.caseInsensitive])

    private static func cleanLines(_ text: String) -> String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty, let junk = junkLine else { return !line.isEmpty }
                return junk.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil
            }
            .joined(separator: "\n")
    }

    private static func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
