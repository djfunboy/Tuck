import XCTest
@testable import Tuck

/// Every fixture below is synthetic filler shaped like a real key. None is a credential.
final class KeyRecognizerTests: XCTestCase {
    private func filler(_ c: Character, _ n: Int) -> String { String(repeating: c, count: n) }

    func testEveryFormatCompilesAndIDsAreUnique() {
        XCTAssertEqual(KeyRecognizer.invalidFormatIDs, [], "patterns that fail to compile")
        let ids = KeyFormats.formats.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate format ids")
        XCTAssertGreaterThan(ids.count, 100)
    }

    func testWellKnownProvidersAreRecognized() {
        let samples: [(String, String)] = [
            ("openai", "sk-proj-" + filler("A", 74) + "T3BlbkFJ" + filler("A", 74)),
            ("anthropic", "sk-ant-api03-" + filler("A", 93) + "AA"),
            ("github", "ghp_" + filler("A", 36)),
            ("github", "github_pat_" + filler("A", 82)),
            ("gitlab", "glpat-" + filler("A", 20)),
            ("stripe", "sk_test_" + filler("A", 24)),
            ("aws", "AKIA" + filler("A", 16)),
            ("gcp", "AIza" + filler("A", 35)),
            ("slack", "xoxb-1234567890-1234567890-abcdefABCDEF"),
            ("sendgrid", "SG." + filler("a", 66)),
            ("twilio", "SK" + filler("a", 32)),
            ("huggingface", "hf_" + filler("a", 34)),
            ("perplexity", "pplx-" + filler("A", 48)),
            ("notion", "ntn_12345678901" + filler("A", 35)),
            ("linear", "lin_api_" + filler("a", 40)),
            ("npm", "npm_" + filler("a", 36)),
            ("digitalocean", "dop_v1_" + filler("a", 64)),
            ("vercel", "vcp_" + filler("A", 24)),
            ("supabase", "sb_secret_" + filler("A", 24)),
            ("groq", "gsk_" + filler("A", 52)),
            ("xai", "xai-" + filler("A", 80)),
            ("shopify", "shpat_" + filler("a", 32)),
            ("databricks", "dapi" + filler("a", 32)),
            ("sentry", "sntryu_" + filler("a", 64)),
            ("postman", "PMAK-" + filler("a", 24) + "-" + filler("a", 34)),
            ("pypi", "pypi-AgEIcHlwaS5vcmc" + filler("A", 60)),
            ("gcp", "{\"type\": \"service_account\", \"project_id\": \"public-fixture\"}"),
        ]
        for (family, value) in samples {
            let r = KeyRecognizer.recognize(value)
            XCTAssertEqual(r?.family, family, "expected \(family) for \(value.prefix(12))…")
            XCTAssertEqual(r?.isGeneric, false, family)
        }
    }

    func testGenericShapesAreRecognizedAsGeneric() {
        let jwt = "eyJ" + filler("A", 20) + ".eyJ" + filler("A", 20) + "." + filler("A", 20)
        XCTAssertEqual(KeyRecognizer.recognize(jwt)?.isGeneric, true)
        let pem = "-----BEGIN PRIVATE KEY-----\n" + filler("A", 64) + "\n-----END PRIVATE KEY-----\n"
        XCTAssertEqual(KeyRecognizer.recognize(pem)?.isGeneric, true)
    }

    func testBareFortyCharacterValueIsNotRecognized() {
        let oldStyleGitHubShapedPublicFixture = "0123456789abcdef0123456789abcdef01234567"
        XCTAssertEqual(oldStyleGitHubShapedPublicFixture.count, 40)
        XCTAssertNil(KeyRecognizer.recognize(oldStyleGitHubShapedPublicFixture))
        XCTAssertNil(KeyRecognizer.recognize(filler("A", 40)))
    }

    func testOrdinaryTextIsNotRecognized() {
        for value in ["", "   ", "hello world", "sk-", "123e4567-e89b-12d3-a456-426614174000",
                      "PUBLIC NON-CREDENTIAL UI FIXTURE 🌈", filler("a", 12)] {
            XCTAssertNil(KeyRecognizer.recognize(value), value)
        }
    }

    func testDestinationMismatch() {
        let github = KeyRecognition(provider: "GitHub token", family: "github", isGeneric: false)
        let openai = KeyRecognition(provider: "OpenAI API key", family: "openai", isGeneric: false)
        let jwt = KeyRecognition(provider: "a JSON Web Token", family: "jwt", isGeneric: true)
        XCTAssertEqual(DestinationMismatch.check(recognition: github, service: "openai-api-key", account: "chris"), "openai")
        XCTAssertNil(DestinationMismatch.check(recognition: openai, service: "OPENAI_API_KEY", account: "default"))
        XCTAssertNil(DestinationMismatch.check(recognition: github, service: "my-token", account: "me"))
        XCTAssertNil(DestinationMismatch.check(recognition: jwt, service: "openai", account: "me"))
        XCTAssertNil(DestinationMismatch.check(recognition: github, service: "github.com", account: "openai-bot"), "own family wins")
    }

    func testCommonWordsInDestinationsDoNotWarn() {
        let github = KeyRecognition(provider: "GitHub token", family: "github", isGeneric: false)
        for (service, account) in [("private-repo", "deploy"), ("age-verification", "svc"), ("storage-gem", "me"), ("do-not-share", "me"), ("op-tool", "me")] {
            XCTAssertNil(DestinationMismatch.check(recognition: github, service: service, account: account), "\(service)/\(account)")
        }
    }

    func testAdversarialLargeInputsStayFast() {
        _ = KeyRecognizer.recognize("warm")
        for value in ["{" + filler("A", 65_535), "{\"a\":" + filler("{", 30_000) + filler("}", 30_000), "-----BEGIN " + filler("A", 65_500), "eyJ" + filler("A", 65_500)] {
            let start = Date()
            _ = KeyRecognizer.recognize(value)
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.05, "slow on \(value.prefix(8))…")
        }
    }

    func testWhitespaceHints() {
        XCTAssertEqual(KeyRecognizer.whitespaceHint("abc\n"), "ends with a line break")
        XCTAssertEqual(KeyRecognizer.whitespaceHint("abc\r\n"), "ends with a line break")
        XCTAssertEqual(KeyRecognizer.whitespaceHint("abc "), "ends with a space")
        XCTAssertEqual(KeyRecognizer.whitespaceHint("\tabc"), "starts with whitespace")
        XCTAssertNil(KeyRecognizer.whitespaceHint("abc"))
        XCTAssertNil(KeyRecognizer.whitespaceHint(""))
    }

    func testArticle() {
        XCTAssertEqual(KeyRecognizer.article(for: "OpenAI API key"), "an")
        XCTAssertEqual(KeyRecognizer.article(for: "GitHub token"), "a")
    }

    func testLargeValueIsFast() {
        let value = filler("A", 65_536)
        _ = KeyRecognizer.recognize("warm") // compile once
        let start = Date()
        _ = KeyRecognizer.recognize(value)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }
}
