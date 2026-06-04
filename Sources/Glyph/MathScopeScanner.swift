import Foundation

struct MathScopeScanner {
    static let mathKeywords: Set<String> = [
        "integral", "integrals", "derivative", "derivatives", "sum", "sums", "product", "products",
        "limit", "limits", "lim", "liminf", "limsup", "infinity", "inf", "infty", "pi", 
        "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", 
        "lambda", "mu", "nu", "xi", "omicron", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega",
        "sin", "cos", "tan", "csc", "sec", "cot", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
        "arcsinh", "arccosh", "arctanh", "sech", "csch", "coth", "log", "ln", "lg", "exp", "matrix", "matrices",
        "vector", "tensor", "determinant", "det", "transpose", "inverse", "inv", "trace", "tr",
        "eigenvalue", "eigenvalues", "eigenvector", "eigenvectors", "dimension", "dim", "rank",
        "kernel", "ker", "image", "im", "fraction", "frac", "over", "divided", "plus", "minus", "times",
        "multiplied", "equals", "equal", "squared", "cubed", "power", "root", "sqrt", "cbrt", "modulo", "mod",
        "dot", "cross", "gradient", "grad", "divergence", "div", "curl", "laplacian", "partial", "del", "nabla",
        "dx", "dy", "dz", "dt", "du", "dv", "dw", "dr", "dtheta", "dphi", "dpsi", "deta", "dxi",
        "union", "intersection", "subset", "subseteq", "supset", "supseteq", "element", "notin", "exists", "forall",
        "implies", "iff", "evaluate", "evaluated", "from", "to", "choose", "binom", "expected", "variance", "cov",
        "probability", "prob", "mean", "median", "mode", "stddev", "distribution", "normal", "binomial", "poisson",
        "uniform", "exponential", "approx", "approximately", "factorial", "prime", "emptyset", "varnothing", "setminus",
        "parallel", "perp", "orthogonal", "orthonormal", "convolution", "convolute", "fourier", "laplace", "transform",
        "ceiling", "ceil", "floor", "abs", "absolute", "norm", "real", "imaginary", "imag", "re", "arg", "argument",
        "conjugate", "conj", "sign", "sgn", "min", "max", "sup", "supremum", "infimum", "deg", "degree", "degrees",
        "rad", "radian", "radians"
    ]
    
    static let stopWords: Set<String> = [
        "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "a", "an", "this", "that", "these", "those",
        "i", "you", "he", "she", "it", "we", "they",
        "my", "your", "his", "her", "its", "our", "their",
        "but", "by", "concerning", "except", "into", "like", "near", 
        "regarding", "since", "through", "throughout", "till", "toward", "under",
        "until", "upon", "without",
        "so", "yet", "because", "although", "while", "if", "unless",
        "there", "here", "where", "when", "why", "how", "what", "which", "who", "whom",
        "very", "quite", "rather", "somewhat", "too", "also", "just", "only", "even",
        "really", "actually", "literally", "simply", "mostly", "almost", "always",
        "never", "sometimes", "often", "usually", "generally", "frequently", "rarely",
        "suddenly", "quickly", "slowly", "carefully", "easily", "hardly", "scarcely",
        "well", "poorly", "good", "bad", "great", "terrible", "excellent", "awful",
        "beautiful", "ugly", "happy", "sad", "angry", "calm", "excited", "bored",
        "tired", "awake", "hungry", "thirsty", "full", "empty", "hot", "cold",
        "warm", "cool", "wet", "dry", "soft", "hard", "heavy", "light", "big",
        "small", "large", "tiny", "huge", "massive", "gigantic", "minuscule",
        "long", "short", "tall", "high", "low", "deep", "shallow", "wide", "narrow",
        "thick", "thin", "fat", "skinny", "fast", "slow", "early", "late", "old",
        "new", "young", "ancient", "modern", "recent", "current", "past", "future"
    ]
    
    static let allowedStopWordsInMath: Set<String> = [
        "from", "to", "over", "of", "and", "in", "by", "for", "with", "evaluate", "evaluated", "as", "at", "on",
        "gives", "yields", "get", "we", "obtain", "obtaining", "substituting", "substitution", "solving", "solve",
        "then", "therefore", "thus", "hence"
    ]
    
    struct Token {
        let text: String
        let nsRange: NSRange
        let isPunctuationBoundary: Bool
        let isWhitespace: Bool
    }
    
    static func extractMath(from text: String) -> NSRange? {
        let lines = text.components(separatedBy: .newlines)
        guard let lastLine = lines.last, !lastLine.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        
        let tokens = tokenize(lastLine)
        let words = tokens.filter { !$0.isWhitespace }
        guard !words.isEmpty else { return nil }
        
        var foundStrongIndicator = false
        var startIndex = words.count - 1
        var nonMathConsecutiveCount = 0
        
        for i in stride(from: words.count - 1, through: 0, by: -1) {
            let token = words[i]
            
            if token.isPunctuationBoundary {
                break
            }
            
            let isMath = isMathToken(token.text)
            if isMath {
                nonMathConsecutiveCount = 0
                if isStrongMathIndicator(token.text) {
                    foundStrongIndicator = true
                }
            } else {
                let lower = token.text.lowercased()
                let isAllowedStopWord = allowedStopWordsInMath.contains(lower)
                
                if stopWords.contains(lower) && !isAllowedStopWord {
                    break
                }
                
                if !isAllowedStopWord {
                    nonMathConsecutiveCount += 1
                }
                
                if nonMathConsecutiveCount >= 3 {
                    startIndex = i + nonMathConsecutiveCount - 1
                    break
                }
            }
            
            startIndex = i
        }
        
        guard foundStrongIndicator else { return nil }
        
        var finalStartIndex = startIndex
        for i in startIndex..<words.count {
            let tokenText = words[i].text
            if isMathToken(tokenText) || isStrongMathIndicator(tokenText) {
                finalStartIndex = i
                break
            }
        }
        
        var adjustedStartIndex = finalStartIndex
        if adjustedStartIndex > 0 {
            let prevWord = words[adjustedStartIndex - 1].text.lowercased()
            if prevWord == "the" || prevWord == "a" || prevWord == "an" {
                adjustedStartIndex -= 1
            }
        }
        
        let phraseTokens = words[adjustedStartIndex...]
        guard !phraseTokens.isEmpty else { return nil }
        
        let startToken = phraseTokens.first!
        let endToken = phraseTokens.last!
        
        let prefixLength = text.utf16.count - lastLine.utf16.count
        let finalLocation = startToken.nsRange.location
        let finalLength = (endToken.nsRange.location + endToken.nsRange.length) - finalLocation
        
        let extractedTokens = phraseTokens.map { $0.text }
        let hasMathOperatorOrKeyword = extractedTokens.contains { token in
            let lower = token.lowercased()
            return mathKeywords.contains(lower) || ["+", "-", "=", "/", "*", "^", "_", "\\", "(", ")", "[", "]"].contains(token)
        }
        
        guard hasMathOperatorOrKeyword else { return nil }
        
        return NSRange(location: prefixLength + finalLocation, length: finalLength)
    }
    
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let nsString = text as NSString
        // Regex matches words, decimals, whitespace, or single symbol chars
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z]+|[0-9]+(?:\\.[0-9]+)?|\\s+|[^\\s\\w])", options: []) else { return [] }
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let str = nsString.substring(with: match.range)
            let isPunc = str == "." || str == "?" || str == "!" || str == ";" || str == ":" || str == "\"" || str == "'"
            let isWhitespace = str.trimmingCharacters(in: .whitespaces).isEmpty
            tokens.append(Token(text: str, nsRange: match.range, isPunctuationBoundary: isPunc, isWhitespace: isWhitespace))
        }
        return tokens
    }
    
    static func isMathToken(_ text: String) -> Bool {
        let lower = text.lowercased()
        if mathKeywords.contains(lower) { return true }
        if Double(text) != nil { return true }
        if text.count == 1 && text.first!.isLetter { return true }
        
        let mathSymbols: Set<Character> = ["+", "-", "=", "/", "*", "^", "_", "<", ">", "(", ")", "[", "]", "{", "}", "\\", "|", "~", ","]
        if text.count == 1 && mathSymbols.contains(text.first!) { return true }
        
        return false
    }
    
    static func isStrongMathIndicator(_ text: String) -> Bool {
        let lower = text.lowercased()
        let nonStrongKeywords: Set<String> = ["from", "to", "over", "of", "and", "in", "by", "for", "with", "as", "at", "on"]
        if mathKeywords.contains(lower) && !nonStrongKeywords.contains(lower) { return true }
        
        let mathSymbols: Set<Character> = ["+", "=", "/", "*", "^", "\\"]
        if text.count == 1 && mathSymbols.contains(text.first!) { return true }
        
        if Double(text) != nil { return true }
        
        return false
    }
}
