import Foundation

/// 見出し語が例文中にどの語形で現れているかを探す。
///
/// 例文が見出し語（活用形を含む）を含むことは Node 側のデータ検証で保証済みなので、
/// ここでは規則変化 + よく使う不規則変化だけを見る。
/// 見つからなかった場合、穴埋めクイズは英→日にフォールバックする。
enum Inflector {
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    /// A1〜A2 で出てくる不規則変化（動詞・複数形・比較級）
    private static let irregular: [String: [String]] = [
        "be": ["am", "is", "are", "was", "were", "been", "being"],
        "become": ["became"], "begin": ["began", "begun"], "break": ["broke", "broken"],
        "bring": ["brought"], "build": ["built"], "buy": ["bought"], "catch": ["caught"],
        "choose": ["chose", "chosen"], "come": ["came"], "cost": ["cost"], "cut": ["cut"],
        "do": ["does", "did", "done"], "draw": ["drew", "drawn"], "drink": ["drank", "drunk"],
        "drive": ["drove", "driven"], "eat": ["ate", "eaten"], "fall": ["fell", "fallen"],
        "feel": ["felt"], "find": ["found"], "fly": ["flew", "flown"],
        "forget": ["forgot", "forgotten"], "get": ["got", "gotten"], "give": ["gave", "given"],
        "go": ["goes", "went", "gone"], "grow": ["grew", "grown"], "have": ["has", "had", "having"],
        "hear": ["heard"], "hit": ["hit"], "hold": ["held"], "keep": ["kept"],
        "know": ["knew", "known"], "lead": ["led"], "learn": ["learnt"], "leave": ["left"],
        "lend": ["lent"], "lie": ["lay", "lain", "lying"], "lose": ["lost"], "make": ["made"],
        "mean": ["meant"], "meet": ["met"], "pay": ["paid"], "put": ["put"], "read": ["read"],
        "ride": ["rode", "ridden"], "ring": ["rang", "rung"], "rise": ["rose", "risen"],
        "run": ["ran"], "say": ["said"], "see": ["saw", "seen"], "sell": ["sold"],
        "send": ["sent"], "set": ["set"], "shoot": ["shot"], "show": ["shown"], "shut": ["shut"],
        "sing": ["sang", "sung"], "sit": ["sat"], "sleep": ["slept"], "speak": ["spoke", "spoken"],
        "spend": ["spent"], "stand": ["stood"], "steal": ["stole", "stolen"],
        "swim": ["swam", "swum"], "take": ["took", "taken"], "teach": ["taught"], "tell": ["told"],
        "think": ["thought"], "throw": ["threw", "thrown"], "understand": ["understood"],
        "wake": ["woke", "woken"], "wear": ["wore", "worn"], "weep": ["wept"], "win": ["won"],
        "write": ["wrote", "written"],
        "child": ["children"], "foot": ["feet"], "goose": ["geese"],
        "grandchild": ["grandchildren"], "man": ["men"], "mouse": ["mice"], "person": ["people"],
        "schoolchild": ["schoolchildren"], "tooth": ["teeth"], "woman": ["women"],
        "good": ["better", "best"], "bad": ["worse", "worst"], "many": ["more", "most"],
        "much": ["more", "most"], "little": ["less", "least"], "far": ["further", "farther"],
    ]

    /// 1 語の活用形候補（規則変化 + 不規則変化）
    static func forms(of word: String) -> [String] {
        let base = word.lowercased()
        var out = Set([base])
        out.formUnion(irregular[base] ?? [])

        let chars = Array(base)
        guard let last = chars.last else { return Array(out) }
        let prev = chars.count >= 2 ? chars[chars.count - 2] : nil

        if last == "e" {
            let stem = String(chars.dropLast())
            out.formUnion([base + "s", stem + "ing", base + "d", base + "r", base + "st"])
        } else if last == "y", let prev, !vowels.contains(prev) {
            let stem = String(chars.dropLast())
            out.formUnion([
                stem + "ies", stem + "ied", stem + "ier", stem + "iest", base + "ing",
            ])
        } else {
            out.formUnion([
                base + "s", base + "es", base + "ed", base + "ing", base + "er", base + "est",
            ])
        }

        if last == "f" { out.insert(String(chars.dropLast()) + "ves") }
        if base.hasSuffix("fe") { out.insert(String(chars.dropLast(2)) + "ves") }

        // CVC で終わる語は子音を重ねる（stop → stopped）
        if chars.count >= 3, !vowels.contains(last), !"wxy".contains(last),
           let prev, vowels.contains(prev), !vowels.contains(chars[chars.count - 3]) {
            let doubled = base + String(last)
            out.formUnion([doubled + "ed", doubled + "ing", doubled + "er", doubled + "est"])
        }
        return Array(out)
    }

    /// 熟語・句動詞: 先頭語（動詞）または末尾語（名詞）を活用させた形を作る
    static func phraseForms(of parts: [String]) -> [String] {
        var out = Set([parts.joined(separator: " ")])
        for form in forms(of: parts[0]) {
            out.insert(([form] + parts.dropFirst()).joined(separator: " "))
        }
        for form in forms(of: parts[parts.count - 1]) {
            out.insert((parts.dropLast() + [form]).joined(separator: " "))
        }
        return Array(out)
    }

    /// 例文中で見出し語が現れている範囲を返す。見つからなければ nil
    static func findHeadword(in example: String, headword: String) -> Range<String.Index>? {
        let parts = headword.lowercased().split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return nil }
        let candidates = parts.count > 1 ? phraseForms(of: parts) : forms(of: parts[0])
        // 長い形から試して "play" が "playing" に先に当たらないようにする
        for form in candidates.sorted(by: { $0.count > $1.count }) {
            let pattern = boundedPattern(for: form)
            if let range = example.range(
                of: pattern, options: [.regularExpression, .caseInsensitive]
            ) {
                return range
            }
        }
        return nil
    }

    private static func boundedPattern(for form: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: form)
        let isWordChar = { (char: Character?) in char?.isLetter == true || char?.isNumber == true }
        let lead = isWordChar(form.first) ? "\\b" : ""
        let trail = isWordChar(form.last) ? "\\b" : ""
        return lead + escaped + trail
    }
}
