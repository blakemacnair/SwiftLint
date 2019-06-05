import Foundation
import SourceKittenFramework

public struct LineLengthRule: CorrectableRule, ConfigurationProviderRule {
    public var configuration = LineLengthConfiguration(warning: 120, error: 200)

    public init() {}

    private let commentKinds = SyntaxKind.commentKinds
    private let nonCommentKinds = SyntaxKind.allKinds.subtracting(SyntaxKind.commentKinds)
    private let functionKinds = SwiftDeclarationKind.functionKinds

    public static let description = RuleDescription(
        identifier: "line_length",
        name: "Line Length",
        description: "Lines should not span too many characters.",
        kind: .metrics,
        nonTriggeringExamples: [
            String(repeating: "/", count: 120) + "\n",
            String(repeating: "#colorLiteral(red: 0.9607843161, green: 0.7058823705, blue: 0.200000003, alpha: 1)", count: 120) + "\n",
            String(repeating: "#imageLiteral(resourceName: \"image.jpg\")", count: 120) + "\n"
        ],
        triggeringExamples: [
            String(repeating: "/", count: 121) + "\n",
            String(repeating: "#colorLiteral(red: 0.9607843161, green: 0.7058823705, blue: 0.200000003, alpha: 1)", count: 121) + "\n",
            String(repeating: "#imageLiteral(resourceName: \"image.jpg\")", count: 121) + "\n"
        ],
        corrections: [
            "func thisIsAVeryStrangeFuncThatHasAReallySeriouslyStupidlyLongNameSoThatNowYaKnow(val1: String, val2: Bool, val3: (String, Bool)) { \n":
            "func thisIsAVeryStrangeFuncThatHasAReallySeriouslyStupidlyLongNameSoThatNowYaKnow(val1: String,\nval2: Bool,\nval3: (String, Bool)) { \n",
            "func externalAndInternalNamingParametersBoiiiiiiiiiiii(_ val1: String, leValue val2: Bool, perperper val3: (String, Bool)) { \n":
            "func externalAndInternalNamingParametersBoiiiiiiiiiiii(_ val1: String,\nleValue val2: Bool,\nperperper val3: (String, Bool)) { \n",
        ]
    )

    public func validate(file: File) -> [StyleViolation] {
        let minValue = configuration.params.map({ $0.value }).min() ?? .max
        let swiftDeclarationKindsByLine = Lazy(file.swiftDeclarationKindsByLine() ?? [])
        let syntaxKindsByLine = Lazy(file.syntaxKindsByLine() ?? [])

        return file.lines.compactMap { line in
            // `line.content.count` <= `line.range.length` is true.
            // So, `check line.range.length` is larger than minimum parameter value.
            // for avoiding using heavy `line.content.count`.
            if line.range.length < minValue {
                return nil
            }

            if configuration.ignoresFunctionDeclarations &&
                lineHasKinds(line: line,
                             kinds: functionKinds,
                             kindsByLine: swiftDeclarationKindsByLine.value) {
                return nil
            }

            if configuration.ignoresComments &&
                lineHasKinds(line: line,
                             kinds: commentKinds,
                             kindsByLine: syntaxKindsByLine.value) &&
                !lineHasKinds(line: line,
                              kinds: nonCommentKinds,
                              kindsByLine: syntaxKindsByLine.value) {
                return nil
            }

            if configuration.ignoresInterpolatedStrings &&
                lineHasKinds(line: line,
                             kinds: [.stringInterpolationAnchor],
                             kindsByLine: syntaxKindsByLine.value) {
                return nil
            }

            var strippedString = line.content
            if configuration.ignoresURLs {
                strippedString = strippedString.strippingURLs
            }
            strippedString = stripLiterals(fromSourceString: strippedString,
                                           withDelimiter: "#colorLiteral")
            strippedString = stripLiterals(fromSourceString: strippedString,
                                           withDelimiter: "#imageLiteral")

            let length = strippedString.count

            for param in configuration.params where length > param.value {
                let reason = "Line should be \(configuration.length.warning) characters or less: " +
                             "currently \(length) characters"
                return StyleViolation(ruleDescription: type(of: self).description,
                                      severity: param.severity,
                                      location: Location(file: file.path, line: line.index),
                                      reason: reason)
            }
            return nil
        }
    }

    public func correct(file: File) -> [Correction] {
        // TODO: Add corrections key to description with examples
        let minValue = configuration.params.map({ $0.value }).min() ?? .max
        let swiftDeclarationKindsByLine = Lazy(file.swiftDeclarationKindsByLine() ?? [])
        let regexString = "(.*[a-zA-Z\\.]+\\(|[a-zA-Z ]{3,}+\\(|([\\S]+ ?[\\S]+: ([A-Za-z]+|\\({1,2}[^\\(^\\)]+\\){1,2}|\\[{1,2}[^\\[^\\]]+\\]{1,2})(, |\\) \\{.*|\\) \\-\\>.*|\\).*)))"
        let regex = try! NSRegularExpression(pattern: regexString)

        var correctedLines = [String]()
        var corrections = [Correction]()

        for line in file.lines {
            // `line.content.count` <= `line.range.length` is true.
            // So, `check line.range.length` is larger than minimum parameter value.
            // for avoiding using heavy `line.content.count`.
            if line.range.length < minValue {
                correctedLines.append(line.content)
                continue
            }

            var correctedLine = line.content

            if lineHasKinds(line: line,
                            kinds: functionKinds,
                            kindsByLine: swiftDeclarationKindsByLine.value) {
                guard !configuration.ignoresFunctionDeclarations else {
                    correctedLines.append(line.content)
                    continue
                }

                // Split string into components based on function-splitting regex
                var components = regex.matches(in: correctedLine, options: [], range: correctedLine.fullNSRange)
                    .map { $0.range }
                    .map { correctedLine.substring(from: $0.location, length: $0.length) }
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                // Ignore single-parameter functions or zero-parameter functions
                guard components.count > 2 else {
                    correctedLines.append(line.content)
                    continue
                }

                components = components
                    .map { comp -> String in
                        guard comp != components.last else { return comp }
                        return comp + "\n"
                }

                // Rejoin components to make the new corrected line OR do we need to make new Line objects?????
                correctedLine = components.joined()
            }

            if line.content != correctedLine {
                let description = type(of: self).description
                let location = Location(file: file.path, line: line.index)
                corrections.append(Correction(ruleDescription: description, location: location))
            }
            correctedLines.append(correctedLine)
            continue
        }

        if !corrections.isEmpty {
            // join and re-add trailing newline
            file.write(correctedLines.joined(separator: "\n") + "\n")
            return corrections
        }
        return []
    }

    /// Takes a string and replaces any literals specified by the `delimiter` parameter with `#`
    ///
    /// - parameter sourceString: Original string, possibly containing literals
    /// - parameter delimiter:    Delimiter of the literal
    ///     (characters before the parentheses, e.g. `#colorLiteral`)
    ///
    /// - returns: sourceString with the given literals replaced by `#`
    private func stripLiterals(fromSourceString sourceString: String,
                               withDelimiter delimiter: String) -> String {
        var modifiedString = sourceString

        // While copy of content contains literal, replace with a single character
        while modifiedString.contains("\(delimiter)(") {
            if let rangeStart = modifiedString.range(of: "\(delimiter)("),
                let rangeEnd = modifiedString.range(of: ")",
                                                    options: .literal,
                                                    range:
                    rangeStart.lowerBound..<modifiedString.endIndex) {
                modifiedString.replaceSubrange(rangeStart.lowerBound..<rangeEnd.upperBound,
                                               with: "#")
            } else { // Should never be the case, but break to avoid accidental infinity loop
                break
            }
        }

        return modifiedString
    }

    private func lineHasKinds<Kind>(line: Line, kinds: Set<Kind>, kindsByLine: [[Kind]]) -> Bool {
        let index = line.index
        if index >= kindsByLine.count {
            return false
        }
        return !kinds.isDisjoint(with: kindsByLine[index])
    }
}

// extracted from https://forums.swift.org/t/pitch-declaring-local-variables-as-lazy/9287/3
private class Lazy<Result> {
    private var computation: () -> Result
    fileprivate private(set) lazy var value: Result = computation()

    init(_ computation: @escaping @autoclosure () -> Result) {
        self.computation = computation
    }
}

private extension String {
    var strippingURLs: String {
        let range = NSRange(location: 0, length: bridge().length)
        // Workaround for Linux until NSDataDetector is available
        #if os(Linux)
            // Regex pattern from http://daringfireball.net/2010/07/improved_regex_for_matching_urls
            let pattern = "(?i)\\b((?:[a-z][\\w-]+:(?:/{1,3}|[a-z0-9%])|www\\d{0,3}[.]|[a-z0-9.\\-]+[.][a-z]{2,4}/)" +
                "(?:[^\\s()<>]+|\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\))+(?:\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*" +
                "\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’]))"
            let urlRegex = regex(pattern)
            return urlRegex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
        #else
            let types = NSTextCheckingResult.CheckingType.link.rawValue
            guard let urlDetector = try? NSDataDetector(types: types) else {
                return self
            }
            return urlDetector.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
        #endif
    }
}
