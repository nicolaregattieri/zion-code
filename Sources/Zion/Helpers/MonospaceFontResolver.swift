import AppKit

enum MonospaceFontResolver {
    struct ResolvedFont {
        let font: NSFont
        let isAvailable: Bool
    }

    static func resolve(name: String, size: CGFloat) -> ResolvedFont {
        let candidates = fontCandidates(for: name)
        for candidate in candidates {
            if let font = NSFont(name: candidate, size: size) {
                return ResolvedFont(font: font, isAvailable: true)
            }
        }

        if isSFMonoAlias(name) {
            return ResolvedFont(
                font: .monospacedSystemFont(ofSize: size, weight: .regular),
                isAvailable: true
            )
        }

        return ResolvedFont(
            font: .monospacedSystemFont(ofSize: size, weight: .regular),
            isAvailable: false
        )
    }

    static func isAvailable(name: String) -> Bool {
        resolve(name: name, size: 13).isAvailable
    }

    static func migratedTerminalName(_ storedName: String) -> String {
        switch normalized(storedName) {
        case "hacknerdfont", "hacknerdfontmono", "hacknerdfontmonoregular", "hacknfm":
            return "Hack"
        default:
            return storedName
        }
    }

    private static func fontCandidates(for name: String) -> [String] {
        let key = normalized(name)
        var candidates = [name]

        switch key {
        case "sfmono", "sfmonoregular", "sfnsmonoregular", "sfpromono":
            candidates += ["SF Mono", "SFMono-Regular", ".SFNSMono-Regular", "SF Pro Mono Regular"]
        case "firacode", "firacoderegular":
            candidates += ["Fira Code", "FiraCode-Regular", "FiraCode-Retina"]
        case "jetbrainsmono", "jetbrainsmonoregular":
            candidates += ["JetBrains Mono", "JetBrainsMono-Regular"]
        case "hack", "hackregular":
            candidates += ["Hack", "Hack-Regular"]
        case "robotomono", "robotomonoregular":
            candidates += ["Roboto Mono", "RobotoMono-Regular"]
        case "menlo", "menloregular":
            candidates += ["Menlo", "Menlo-Regular"]
        case "courier", "couriernewpsmt":
            candidates += ["Courier", "CourierNewPSMT"]
        case "hacknerdfont", "hacknerdfontmono", "hacknerdfontmonoregular", "hacknfm":
            candidates += ["HackNerdFontMono-Regular", "Hack Nerd Font Mono", "Hack", "Hack-Regular"]
        default:
            break
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private static func isSFMonoAlias(_ name: String) -> Bool {
        let key = normalized(name)
        return key == "sfmono" || key == "sfmonoregular" || key == "sfnsmonoregular" || key == "sfpromono"
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
