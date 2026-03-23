import SwiftUI

extension CodeScreen {

    // MARK: - Find/Replace Bar

    var findReplaceBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                // Toggle replace visibility
                Button {
                    withAnimation(DesignSystem.Motion.detail) { isReplaceVisible.toggle() }
                } label: {
                    Image(systemName: isReplaceVisible ? "chevron.down" : "chevron.right")
                        .font(DesignSystem.Typography.metaBold)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 24)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 26)
                .contentShape(Rectangle())
                .help(L10n("editor.replace.placeholder"))

                // Search field
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    FindSearchTextField(
                        text: $searchQuery,
                        placeholder: L10n("editor.search.placeholder"),
                        focusRequestID: findSearchFocusRequestID,
                        onEnter: { navigateToNextMatch() },
                        onShiftEnter: { navigateToPreviousMatch() },
                        onCancel: { closeSearch() }
                    )
                    .frame(height: 18)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                .frame(maxWidth: 280)

                // Search option toggles
                HStack(spacing: 2) {
                    findOptionToggle(icon: "textformat", isOn: $isMatchCase, tooltip: L10n("editor.search.matchCase"))
                    findOptionToggle(icon: "textformat.abc", isOn: $isWholeWord, tooltip: L10n("editor.search.wholeWord"))
                    findOptionToggle(icon: "curlybraces", isOn: $isRegexSearch, tooltip: L10n("editor.search.regex"))
                }

                // Match count
                if !searchQuery.isEmpty {
                    Text(matchCount > 0 ? "\(currentMatchIndex + 1)/\(matchCount)" : L10n("editor.search.noResults"))
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }

                // Nav buttons
                Button { navigateToPreviousMatch() } label: {
                    Image(systemName: "chevron.up").font(DesignSystem.Typography.labelMedium)
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .help(L10n("editor.search.previous") + " (⇧Enter)")
                .accessibilityLabel(L10n("editor.search.previous"))

                Button { navigateToNextMatch() } label: {
                    Image(systemName: "chevron.down").font(DesignSystem.Typography.labelMedium)
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .help(L10n("editor.search.next") + " (Enter)")
                .accessibilityLabel(L10n("editor.search.next"))

                Spacer()

                // Close
                Button { closeSearch() } label: {
                    Image(systemName: "xmark").font(DesignSystem.Typography.labelBold).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .help(L10n("Esc"))
                .accessibilityLabel(L10n("Esc"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if isReplaceVisible {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    Spacer().frame(width: 32)

                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                        TextField(L10n("editor.replace.placeholder"), text: $replaceQuery)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Typography.body)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                    .frame(maxWidth: 280)

                    Button(L10n("editor.replace.one")) { replaceCurrent() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(matchCount == 0)

                    Button(L10n("editor.replace.all")) { replaceAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(matchCount == 0)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
        }
    }

    @ViewBuilder
    func findOptionToggle(icon: String, isOn: Binding<Bool>, tooltip: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            recomputeFindMatches()
            searchScrollRequestID += 1
        } label: {
            Image(systemName: icon)
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .background(isOn.wrappedValue ? DesignSystem.Colors.glassSubtle : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    func openSearch(applySeedIfPresent: Bool) {
        withAnimation(DesignSystem.Motion.detail) {
            isSearchVisible = true
        }

        if applySeedIfPresent, !seededFindQuery.isEmpty, searchQuery != seededFindQuery {
            searchQuery = seededFindQuery
            currentMatchIndex = 0
        }

        recomputeFindMatches()
        searchScrollRequestID += 1
        findSearchFocusRequestID += 1
    }

    func toggleSearch() {
        if isSearchVisible {
            withAnimation(DesignSystem.Motion.detail) {
                closeSearch()
            }
        } else {
            openSearch(applySeedIfPresent: true)
        }
    }

    func toggleReplace() {
        withAnimation(DesignSystem.Motion.detail) {
            if !isSearchVisible { isSearchVisible = true }
            isReplaceVisible.toggle()
        }
    }

    func closeSearch() {
        isSearchVisible = false
        isReplaceVisible = false
        searchQuery = ""
        replaceQuery = ""
        matchCount = 0
        currentMatchIndex = 0
    }

    func navigateToNextMatch() {
        if matchCount == 0 {
            recomputeFindMatches()
        }
        guard matchCount > 0 else { return }
        if currentMatchIndex < 0 || currentMatchIndex >= matchCount {
            currentMatchIndex = 0
        }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
        searchScrollRequestID += 1
    }

    func navigateToPreviousMatch() {
        if matchCount == 0 {
            recomputeFindMatches()
        }
        guard matchCount > 0 else { return }
        if currentMatchIndex < 0 || currentMatchIndex >= matchCount {
            currentMatchIndex = 0
        }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        searchScrollRequestID += 1
    }

    // MARK: - Search Regex Builder

    private func buildSearchRegex() -> NSRegularExpression? {
        guard !searchQuery.isEmpty else { return nil }
        var pattern: String
        if isRegexSearch {
            pattern = searchQuery
        } else {
            pattern = NSRegularExpression.escapedPattern(for: searchQuery)
        }
        if isWholeWord {
            pattern = "\\b\(pattern)\\b"
        }
        var options: NSRegularExpression.Options = []
        if !isMatchCase { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    func recomputeFindMatches() {
        guard isSearchVisible, !searchQuery.isEmpty else {
            matchCount = 0
            currentMatchIndex = 0
            return
        }
        guard let regex = buildSearchRegex() else {
            matchCount = 0
            currentMatchIndex = 0
            return
        }
        let nsString = model.codeFileContent as NSString
        let matches = regex.matches(in: model.codeFileContent, options: [], range: NSRange(location: 0, length: nsString.length))
        matchCount = matches.count
        if matchCount == 0 {
            currentMatchIndex = 0
        } else if currentMatchIndex >= matchCount {
            currentMatchIndex = matchCount - 1
        }
    }

    func replaceCurrent() {
        guard matchCount > 0, !searchQuery.isEmpty else { return }
        guard let regex = buildSearchRegex() else { return }
        let nsString = model.codeFileContent as NSString
        let matches = regex.matches(in: model.codeFileContent, options: [], range: NSRange(location: 0, length: nsString.length))
        guard currentMatchIndex < matches.count else { return }

        let range = matches[currentMatchIndex].range
        guard let swiftRange = Range(range, in: model.codeFileContent) else { return }
        let replacement = isRegexSearch ? replaceQuery : replaceQuery
        model.codeFileContent.replaceSubrange(swiftRange, with: replacement)

        // Recalculate after replacement
        if currentMatchIndex >= matchCount - 1 {
            currentMatchIndex = max(0, matchCount - 2)
        }
    }

    func replaceAll() {
        guard !searchQuery.isEmpty else { return }
        guard let regex = buildSearchRegex() else { return }
        let nsString = model.codeFileContent as NSString
        let template = isRegexSearch ? replaceQuery : NSRegularExpression.escapedTemplate(for: replaceQuery)
        model.codeFileContent = regex.stringByReplacingMatches(in: model.codeFileContent, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: template)
        currentMatchIndex = 0
    }
}
