// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum LocalizationFeatureContractTests {
    static func run(_ suite: TestSuite) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) {
            let actual = TestFormat.parse(format)?.conversions ?? ["invalid format"]
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        // MARK: Localization format contracts

        let localizedStrings = LocalizationTests.languages
        // Thirty-six feature string sets were held to the no-em-dash rule and
        // the main one never was, so a caption in every language carried a
        // pair of them.
        for (language, strings) in localizedStrings {
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") },
                   "no em-dash in visible strings (\(language.rawValue))")
        }
        // The system writes an apostrophe as a curled mark, and so does every
        // string here now: five hundred and ninety-nine of them were typewriter
        // straight, and eleven quoted a setting with straight pairs instead of
        // the marks their language uses.
        var typewriterMarks: [String] = []
        for folder in ["Sources/Vorssaint/Core", "Sources/Vorssaint/Core/Localizations"] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
                guard name.hasSuffix("Strings.swift") || name.hasPrefix("Strings+")
                        || name == "Localization.swift" else { continue }
                let full = folder + "/" + name
                for (index, line) in (((try? String(contentsOfFile: full, encoding: .utf8)) ?? "")
                    .components(separatedBy: "\n")).enumerated() {
                    guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                    guard let opening = line.firstIndex(of: "\""),
                          let closing = line.lastIndex(of: "\""), opening < closing else { continue }
                    if line[opening..<closing].contains("'") {
                        typewriterMarks.append("\(full):\(index + 1)")
                    }
                }
            }
        }
        suite.expect(typewriterMarks.isEmpty,
               "visible text curls its apostrophes (\(typewriterMarks.prefix(6).joined(separator: ", ")))")
        // French sets a space before its double punctuation and inside its
        // quotes, and that space must not break: a plain one lets a colon or a
        // closing guillemet fall alone onto the next line of a narrow panel.
        // Written as an escape so the character stays visible in the source.
        func frenchLines(_ path: String) -> ArraySlice<String> {
            let lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            guard !path.hasSuffix("Strings+French.swift") else { return lines[...] }
            guard let start = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("static let fr = ")
            }) else { return [][...] }
            let end = lines[(start + 1)...].firstIndex {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("static let ")
            } ?? lines.endIndex
            return lines[start..<end]
        }
        var breakingFrench: [String] = []
        var frenchSources = ["Sources/Vorssaint/Core/Localizations/Strings+French.swift"]
        frenchSources += ((try? FileManager.default
            .contentsOfDirectory(atPath: "Sources/Vorssaint/Core")) ?? [])
            .filter { $0.hasSuffix("Strings.swift") }
            .sorted()
            .map { "Sources/Vorssaint/Core/" + $0 }
        for path in frenchSources {
            for line in frenchLines(path) {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                guard let opening = line.firstIndex(of: "\""),
                      let closing = line.lastIndex(of: "\""), opening < closing else { continue }
                let body = String(line[line.index(after: opening)..<closing])
                let breaks = [" ;", " :", " !", " ?", " \u{00BB}", "\u{00AB} "]
                if breaks.contains(where: { body.contains($0) }) {
                    breakingFrench.append(path.components(separatedBy: "/").last ?? path)
                }
            }
        }
        suite.expect(breakingFrench.isEmpty,
               "French keeps its punctuation on the line it belongs to (\(Set(breakingFrench).sorted().prefix(4).joined(separator: ", ")))")
        let themeSource = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Theme.swift",
                                       encoding: .utf8)) ?? ""
        let raisedReads = themeSource
            .components(separatedBy: "accessibilityDisplayShouldIncreaseContrast").count - 1
        suite.expect(raisedReads == 2,
               "both panel outlines answer raised contrast, and nothing else pretends to")
        // A decimal built without a region is always written with a point, so
        // the panel, the menu bar and the editors were showing one to readers
        // whose system writes a comma. Every float says which region it is in;
        // the two that feed a command line say so out loud.
        var regionlessDecimals: [String] = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let full = "Sources/" + path
            let lines = ((try? String(contentsOfFile: full, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                // A long call puts the region on the next line, so the whole
                // statement is read, not the first line of it.
                let statement = lines[index...min(index + 2, lines.count - 1)].joined()
                guard line.contains("String(format:"), !statement.contains("locale:") else { continue }
                let piece = line.components(separatedBy: "String(format:").dropFirst().first ?? ""
                let format = piece.components(separatedBy: "\"").dropFirst().first ?? ""
                if format.contains("f") && format.contains("%") {
                    regionlessDecimals.append("\(full):\(index + 1)")
                }
            }
        }
        suite.expect(regionlessDecimals.isEmpty,
               "a decimal on screen names its region (\(regionlessDecimals.joined(separator: ", ")))")
        // Purgeable space is a question for a writable volume. Asked of every
        // mounted one, an attached disk image answered with an error on every
        // sample; the bulk fetch no longer carries the key at all.
        let samplerCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Metrics/DiskSampler.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!samplerCode.isEmpty, "the disk sampler reads back for its shape check")
        let bulkKeys = samplerCode.components(separatedBy: "let keys: Set<URLResourceKey>")
            .dropFirst().first?.components(separatedBy: "]").first ?? ""
        suite.expect(!bulkKeys.contains("volumeAvailableCapacityForImportantUsageKey")
                && bulkKeys.contains("volumeIsReadOnlyKey"),
               "the bulk volume fetch asks nothing that only a writable volume can answer")
        suite.expect(samplerCode.contains("guard !isReadOnly,"),
               "purgeable space is read only where there is something to purge")
        // A format string whose placeholders differ between languages feeds
        // String(format:) arguments it was not written for, and the result is
        // garbage or worse. Only fields that really reach a format are read:
        // one caption documents the app's own file-name tokens in prose and
        // its percent signs mean nothing here.
        var formatFields: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for piece in text.components(separatedBy: "String(format:").dropFirst() {
                let head = piece.prefix(120)
                guard let comma = head.firstIndex(of: ",") else { continue }
                // The last dot BEFORE the comma: a dot in the arguments that
                // follow belongs to something else entirely.
                let expression = head[head.startIndex..<comma]
                guard let dot = expression.lastIndex(of: ".") else { continue }
                let name = expression[expression.index(after: dot)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    formatFields.insert(name)
                }
            }
        }
        suite.expect(formatFields.count > 10, "the format fields were found to compare (\(formatFields.count))")
        var mismatched: [String] = []
        for (language, strings) in localizedStrings where language != .enUS {
            let mine = Mirror(reflecting: strings).children
            let base = Mirror(reflecting: Strings.enUS).children
            for (left, right) in zip(base, mine) {
                guard let label = left.label, formatFields.contains(label),
                      let english = left.value as? String,
                      let other = right.value as? String else { continue }
                if TestFormat.parse(english) == nil
                    || TestFormat.parse(english)?.arguments != TestFormat.parse(other)?.arguments {
                    mismatched.append("\(label)/\(language.rawValue)")
                }
            }
        }
        suite.expect(mismatched.isEmpty,
               "every language fills a format the same way (\(mismatched.prefix(5).joined(separator: ", ")))")
        // Quotation marks are part of looking native and each language has its
        // own. Checked against what the system itself ships on this Mac: French
        // and Russian use the angled pair, German pairs a low opening mark with
        // a high closing one, and every other language here uses the curly
        // pair. Spanish, Italian, Portuguese and Turkish had picked up the
        // angled pair, which reads as a translation from somewhere else.
        // A label that says work is under way ends with the ellipsis character,
        // the way the system's own do, not with three periods. Ten of the
        // thirteen languages had the periods while three already had the
        // character, which is the tell that it was never a decision.
        for (language, strings) in localizedStrings {
            let working = [strings.homebrewOperationPreparing, strings.homebrewOperationDownloading,
                           strings.homebrewOperationInstalling, strings.homebrewOperationUninstalling,
                           strings.homebrewOperationUpgrading, strings.homebrewOperationFinalizing,
                           strings.homebrewOperationRefreshing]
            suite.expect(working.allSatisfy { !$0.contains("...") && $0.contains("…") },
                   "work in progress ends with the ellipsis character in \(language.rawValue)")
        }
        for (language, strings) in localizedStrings {
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            let anglesUsed = values.contains { $0.contains("«") || $0.contains("»") }
            suite.expect(anglesUsed == (language == .fr || language == .ru),
                   "only French and Russian quote with angled marks (\(language.rawValue))")
            let lowOpenUsed = values.contains { $0.contains("„") }
            suite.expect(lowOpenUsed == (language == .de),
                   "only German opens a quote with the low mark (\(language.rawValue))")
        }
        for (language, strings) in localizedStrings {
            let prefix = "localization \(language.rawValue)"
            suite.expect(!strings.smoothScrollStepLabel.isEmpty
                   && !strings.smoothScrollResponseLabel.isEmpty
                   && !strings.smoothScrollStepLabel.contains("—")
                   && !strings.smoothScrollResponseLabel.contains("—"),
                   "\(prefix) smooth scrolling controls are present without em dash")
            suite.expect(strings.quickToolsTab == strings.launcherName,
                   "\(prefix) Quick panel keeps the same name in Settings")
            expectFormat(strings.cutMovedPluralFormat, ["d"], "\(prefix) cut plural format")
            expectFormat(strings.uninstallerSelectedFormat, ["d", "d"], "\(prefix) uninstaller selected format")
            expectFormat(strings.uninstallerFreedFormat, ["@"], "\(prefix) uninstaller freed format")
            expectFormat(strings.shelfSelectedFormat, ["d"], "\(prefix) shelf selection format")
            suite.expect(!strings.shelfClearOnClose.isEmpty
                   && !strings.shelfClearOnCloseCaption.isEmpty
                   && !strings.shelfClearOnClose.contains("—")
                   && !strings.shelfClearOnCloseCaption.contains("—"),
                   "\(prefix) shelf clear-on-close labels are present without em dash")
            expectFormat(strings.powerAdapterMaxFormat, ["@"], "\(prefix) adapter max format")
            expectFormat(strings.mixerInputErrorFormat, ["@"], "\(prefix) mixer input error format")
            suite.expect(!strings.mixerSoundEffectsOutputTitle.isEmpty
                   && !strings.mixerSoundEffectsOutputTooltip.isEmpty
                   && !strings.mixerSoundEffectsOutputTitle.contains("—")
                   && !strings.mixerSoundEffectsOutputTooltip.contains("—"),
                   "\(prefix) system sound output labels are present without em dash")
            suite.expect(!strings.keepAwakeRightClickToggle.isEmpty
                   && !strings.keepAwakeRightClickToggleCaption.isEmpty
                   && !strings.keepAwakeRightClickToggle.contains("—")
                   && !strings.keepAwakeRightClickToggleCaption.contains("—"),
                   "\(prefix) right-click Keep Awake labels are present without em dash")
            expectFormat(strings.homebrewConfirmInstallBodyFormat, ["@"], "\(prefix) Homebrew install format")
            expectFormat(strings.homebrewConfirmUninstallBodyFormat, ["@"], "\(prefix) Homebrew uninstall format")
            expectFormat(strings.homebrewConfirmUpgradeBodyFormat, ["@"], "\(prefix) Homebrew upgrade format")
            suite.expect(!strings.homebrewUpgradeAll.isEmpty, "\(prefix) Homebrew update all title is present")
            suite.expect(!strings.homebrewUpdateHomebrew.isEmpty, "\(prefix) Homebrew update Homebrew title is present")
            expectFormat(strings.switcherIconRowMode, ["@"], "\(prefix) App Switcher icon-row title format")
            suite.expect(!strings.switcherIconRowModeCaption.isEmpty, "\(prefix) App Switcher icon-row caption is present")
            suite.expect(!strings.switcherSimpleMode.isEmpty, "\(prefix) App Switcher simple-mode title is present")
            suite.expect(!strings.switcherSimpleModeCaption.isEmpty, "\(prefix) App Switcher simple-mode caption is present")
            suite.expect(!strings.switcherCurrentSpaceOnly.isEmpty
                   && !strings.switcherCurrentSpaceOnly.contains("—"),
                   "\(prefix) App Switcher current-desktop title is present without em dash")
            suite.expect(!strings.switcherCurrentSpaceOnlyCaption.isEmpty
                   && !strings.switcherCurrentSpaceOnlyCaption.contains("—"),
                   "\(prefix) App Switcher current-desktop caption is present without em dash")
            suite.expect(!strings.switcherCurrentDisplayOnly.isEmpty
                   && !strings.switcherCurrentDisplayOnly.contains("—"),
                   "\(prefix) App Switcher current-display title is present without em dash")
            suite.expect(!strings.switcherCurrentDisplayOnlyCaption.isEmpty
                   && !strings.switcherCurrentDisplayOnlyCaption.contains("—"),
                   "\(prefix) App Switcher current-display caption is present without em dash")
            suite.expect([strings.switcherScreenPlacementLabel,
                    strings.switcherScreenPlacementPointer,
                    strings.switcherScreenPlacementMenuBar,
                    strings.switcherScreenPlacementActiveWindow,
                    strings.switcherScreenPlacementCaption]
                   .allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) App Switcher screen placement labels are present without em dash")
            suite.expect(!strings.switcherOtherDesktop.isEmpty
                   && !strings.switcherOtherDesktop.contains("—"),
                   "\(prefix) App Switcher other-desktop label is present without em dash")
            suite.expect(!strings.switcherSearchPin.isEmpty
                   && !strings.switcherSearchPinCaption.isEmpty
                   && !strings.switcherSearchPin.contains("—")
                   && !strings.switcherSearchPinCaption.contains("—"),
                   "\(prefix) App Switcher pinned-search labels are present without em dash")
            suite.expect(!strings.switcherShowShortcutHints.isEmpty
                   && !strings.switcherShowShortcutHintsCaption.isEmpty
                   && !strings.switcherShowShortcutHints.contains("—")
                   && !strings.switcherShowShortcutHintsCaption.contains("—"),
                   "\(prefix) App Switcher shortcut-hint labels are present without em dash")
            suite.expect(!strings.switcherAppearanceDelay.isEmpty
                   && !strings.switcherAppearanceDelayCaption.isEmpty
                   && !strings.switcherAppearanceDelay.contains("—")
                   && !strings.switcherAppearanceDelayCaption.contains("—"),
                   "\(prefix) App Switcher appearance-delay labels are present without em dash")
            suite.expect(!strings.switcherWindowlessApps.isEmpty
                   && !strings.switcherWindowlessApps.contains("—"),
                   "\(prefix) App Switcher windowless apps title is present without em dash")
            suite.expect(!strings.switcherWindowlessAppsCaption.isEmpty
                   && !strings.switcherWindowlessAppsCaption.contains("—"),
                   "\(prefix) App Switcher windowless apps caption is present without em dash")
            suite.expect(!strings.dockClickHide.isEmpty
                   && !strings.dockClickHideCaption.isEmpty
                   && !strings.dockClickHide.contains("—")
                   && !strings.dockClickHideCaption.contains("—"),
                   "\(prefix) Dock hide labels are present without em dash")
            suite.expect(!strings.switcherWindowlessAppsOff.isEmpty
                   && !strings.switcherWindowlessAppsFinder.isEmpty
                   && !strings.switcherWindowlessAppsAll.isEmpty
                   && !strings.switcherWindowlessAppsOff.contains("—")
                   && !strings.switcherWindowlessAppsFinder.contains("—")
                   && !strings.switcherWindowlessAppsAll.contains("—"),
                   "\(prefix) App Switcher windowless apps choices are all present without em dash")
            suite.expect(!strings.diskAvailable.isEmpty
                   && !strings.diskPurgeable.isEmpty
                   && !strings.diskAvailable.contains("—")
                   && !strings.diskPurgeable.contains("—"),
                   "\(prefix) disk available and purgeable labels are present without em dash")
            suite.expect(!strings.switcherNoOpenWindow.isEmpty
                   && !strings.switcherNoOpenWindow.contains("—"),
                   "\(prefix) App Switcher no-open-window tile label is present without em dash")
            suite.expect(!strings.dockPreviewBackgroundOpacity.isEmpty
                   && !strings.dockPreviewBackgroundOpacity.contains("—"),
                   "\(prefix) Dock Preview background title is present without em dash")
            suite.expect(!strings.dockPreviewBackgroundOpacityCaption.isEmpty
                   && !strings.dockPreviewBackgroundOpacityCaption.contains("—"),
                   "\(prefix) Dock Preview background caption is present without em dash")
            suite.expect(!strings.dockPreviewCurrentSpaceOnlyCaption.isEmpty
                   && !strings.dockPreviewCurrentSpaceOnlyCaption.contains("—")
                   && strings.dockPreviewCurrentSpaceOnlyCaption != strings.switcherCurrentSpaceOnlyCaption,
                   "\(prefix) Dock Preview explains its own desktop scope")
            suite.expect(!strings.dockPreviewOpenDelay.isEmpty
                   && !strings.dockPreviewOpenDelay.contains("—"),
                   "\(prefix) Dock Preview open delay title is present without em dash")
            suite.expect(!strings.dockPreviewOpenDelayCaption.isEmpty
                   && !strings.dockPreviewOpenDelayCaption.contains("—"),
                   "\(prefix) Dock Preview open delay caption is present without em dash")
            suite.expect(!strings.minimalWindowPreviews.isEmpty && !strings.minimalWindowPreviewsCaption.isEmpty
                   && !strings.minimalWindowPreviews.contains("—") && !strings.minimalWindowPreviewsCaption.contains("—"),
                   "\(prefix) minimal previews have a localized title and explanation")
            suite.expect(!strings.dockPreviewQuitAppOnClose.isEmpty
                   && !strings.dockPreviewQuitAppOnClose.contains("—")
                   && !strings.dockPreviewQuitAppOnCloseCaption.isEmpty
                   && !strings.dockPreviewQuitAppOnCloseCaption.contains("—"),
                   "\(prefix) Dock Preview quit-on-close labels are present without em dash")
            suite.expect(!strings.switcherShortcutHintApps.isEmpty, "\(prefix) App Switcher app shortcut hint is present")
            suite.expect(!strings.switcherShortcutHintWindows.isEmpty, "\(prefix) App Switcher window shortcut hint is present")
            suite.expect(!strings.networkApps.isEmpty, "\(prefix) network app usage title is present")
            suite.expect(!strings.networkAppsIdle.isEmpty, "\(prefix) network app idle text is present")
            suite.expect(!strings.monitorOpenActivityMonitor.isEmpty
                   && !strings.monitorOpenActivityMonitor.contains("—"),
                   "\(prefix) Activity Monitor action is present without em dash")
            suite.expect(!strings.memoryCompressed.isEmpty
                   && !strings.memoryCompressed.contains("—")
                   && !strings.memoryCachedFiles.isEmpty
                   && !strings.memoryCachedFiles.contains("—"),
                   "\(prefix) memory compressed and cached labels are present without em dash")
            suite.expect(!strings.launchAtLoginNeedsApplications.isEmpty
                   && !strings.launchAtLoginNeedsApplications.contains("—"),
                   "\(prefix) launch at login location note is present without em dash")
            // Shortcut recording: the waiting cap, the two hints under the row
            // and the honest message for a combination that never arrived (#308).
            let shortcutCaptureStrings = [strings.shortcutPressKeys, strings.shortcutEscapeHint,
                                          strings.shortcutDeleteHint, strings.shortcutNotCaptured,
                                          strings.shortcutRecording, strings.shortcutInvalid]
            suite.expect(shortcutCaptureStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) shortcut recording strings are present without em dash")
            suite.expect(!ShortcutRecordingCaption.text(strings, canClear: false).isEmpty
                   && !ShortcutRecordingCaption.text(strings, canClear: false)
                       .contains(strings.shortcutDeleteHint),
                   "\(prefix) a field that cannot clear never promises that Delete clears")
            suite.expect(ShortcutRecordingCaption.text(strings, canClear: true)
                       .contains(strings.shortcutDeleteHint),
                   "\(prefix) a field that can clear says so")
            suite.expect(strings.shortcutPressKeys.count <= 16,
                   "\(prefix) the waiting cap stays short enough for the field")
            let ocrStrings = [strings.ocrRemoveLineBreaksToggle, strings.ocrRemoveLineBreaksCaption,
                              strings.ocrQRToggle, strings.ocrQRCaption, strings.ocrQRCopied,
                              strings.qrResultTitle, strings.qrResultCopy, strings.qrResultOpen]
            suite.expect(ocrStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) screen OCR strings are present without em dash")
            let cleaningStrings = [strings.cleaningKeepScreenVisibleToggle, strings.cleaningKeepScreenVisibleCaption,
                                   strings.cleaningStartNow, strings.cleaningOverlayTitle,
                                   strings.cleaningOverlaySubtitle, strings.cleaningOverlayUnlock,
                                   strings.cleaningOverlayMouseHint, strings.cleaningPanelCaption]
            suite.expect(cleaningStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) cleaning mode strings are present without em dash")
            let highlightsStrings = [strings.highlightsTitle, strings.highlightsTitleClipboardRedesign,
                                     strings.highlightsCaptionDockPreview,
                                     strings.highlightsCaptionScreenshot,
                                     strings.highlightsCaptionSnippetLibrary,
                                     strings.highlightsCaptionCapturePalette,
                                     strings.highlightsCaptionClipboardRedesign,
                                     strings.highlightsConfigure,
                                     strings.highlightsTry, strings.highlightsSeeAll,
                                     strings.reviewIntro, strings.reviewHighlights]
            suite.expect(highlightsStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) update highlights strings are present without em dash")
            let officialHomebrewIntroStrings = [
                strings.homebrewOfficialIntroTitle,
                strings.homebrewOfficialIntroMessage,
                strings.homebrewOfficialIntroInstallLabel,
                strings.homebrewOfficialIntroMigrationTitle,
                strings.homebrewOfficialIntroMigrationMessage,
                strings.homebrewOfficialIntroCopyButton,
                strings.supportIntroDoneButton,
            ]
            suite.expect(officialHomebrewIntroStrings.allSatisfy { !$0.isEmpty },
                   "\(prefix) official Homebrew intro is complete")
            let supportCommunityStrings = [
                strings.donateHeading,
                strings.donateMessage,
                strings.donateButton,
                strings.supportIntroTitle,
                strings.supportIntroMessage,
                strings.supportIntroStarButton,
                strings.supportIntroStarMessage,
                strings.supportIntroCoffeeButton,
                strings.discordIntroTitle,
                strings.discordIntroMessage,
                strings.discordIntroJoinButton,
                strings.communityIntroTitle,
                strings.communityIntroMessage,
                strings.communityIntroFollowButton,
            ]
            suite.expect(supportCommunityStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) support and community strings are complete without em dash")
            suite.expect(strings.donateButton.contains("Buy Me a Coffee")
                   && strings.supportIntroCoffeeButton.contains("Buy Me a Coffee"),
                   "\(prefix) financial support points only to Buy Me a Coffee")
            suite.expect(strings.supportIntroStarMessage.localizedCaseInsensitiveContains("GitHub")
                   && strings.discordIntroJoinButton.localizedCaseInsensitiveContains("Discord"),
                   "\(prefix) non-financial support and community actions name their destinations")
            suite.expect(strings.discordIntroMessage.count <= 320,
                   "\(prefix) Discord introduction stays concise")
            suite.expect(!strings.communityIntroMessage.isEmpty
                   && strings.communityIntroMessage.contains("X"),
                   "\(prefix) community intro invites users to follow previews on X")
            let retiredWeeklyPhrases = [
                "uma vez por semana", "once a week", "haftada bir", "раз в неделю",
                "una vez por semana", "einmal pro Woche", "une fois par semaine",
                "una volta a settimana", "週1回", "매주 한 번", "每周更新一次", "每週更新一次",
            ]
            suite.expect(retiredWeeklyPhrases.allSatisfy {
                !strings.communityIntroMessage.localizedCaseInsensitiveContains($0)
            }, "\(prefix) community intro no longer promises weekly updates")
            suite.expect(!strings.communityIntroMessage.contains("—")
                   && strings.communityIntroMessage.count <= 320,
                   "\(prefix) community intro stays concise and has no em dash")
            if language == .enUS {
                suite.expect(strings.discordIntroMessage.contains("new")
                       && strings.discordIntroMessage.contains("still being built"),
                       "English Discord introduction says the community is new and in development")
            } else if language == .ptBR {
                suite.expect(strings.discordIntroMessage.contains("nova")
                       && strings.discordIntroMessage.contains("em desenvolvimento"),
                       "Portuguese Discord introduction says the community is new and in development")
            }
            suite.expect(!strings.updateShowcaseTitle.isEmpty, "\(prefix) update showcase title is present")
            suite.expect(!strings.updateShowcaseMessage.isEmpty, "\(prefix) update showcase message is present")
            suite.expect(!strings.updateShowcaseUnavailable.isEmpty, "\(prefix) update showcase fallback is present")
            suite.expect(!strings.updateShowcaseRestart.isEmpty, "\(prefix) update showcase restart control is present")
            suite.expect(!strings.homebrewConfirmUpgradeAllTitle.isEmpty, "\(prefix) Homebrew update all confirmation title is present")
            suite.expect(!strings.homebrewConfirmUpgradeAllBody.isEmpty, "\(prefix) Homebrew update all confirmation body is present")
            suite.expect(!strings.homebrewConfirmUpdateHomebrewTitle.isEmpty, "\(prefix) Homebrew update Homebrew confirmation title is present")
            suite.expect(!strings.homebrewConfirmUpdateHomebrewBody.isEmpty, "\(prefix) Homebrew update Homebrew confirmation body is present")
            expectFormat(strings.homebrewPopularityFormat, ["@", "@"], "\(prefix) Homebrew popularity format")
            expectFormat(strings.homebrewOperationInstallFormat, ["@"], "\(prefix) Homebrew operation install format")
            expectFormat(strings.homebrewOperationUninstallFormat, ["@"], "\(prefix) Homebrew operation uninstall format")
            expectFormat(strings.homebrewOperationUpgradeFormat, ["@"], "\(prefix) Homebrew operation upgrade format")
            suite.expect(!strings.homebrewOperationUpgradeAll.isEmpty, "\(prefix) Homebrew operation update all is present")
            suite.expect(!strings.homebrewOperationUpdateHomebrew.isEmpty, "\(prefix) Homebrew operation update Homebrew is present")
            expectFormat(strings.homebrewOperationInstalledFormat, ["@"], "\(prefix) Homebrew operation installed format")
            expectFormat(strings.homebrewOperationUninstalledFormat, ["@"], "\(prefix) Homebrew operation uninstalled format")
            expectFormat(strings.homebrewOperationUpgradedFormat, ["@"], "\(prefix) Homebrew operation upgraded format")
            suite.expect(!strings.homebrewOperationUpgradedAll.isEmpty, "\(prefix) Homebrew operation updated all is present")
            suite.expect(!strings.homebrewOperationUpdatedHomebrew.isEmpty, "\(prefix) Homebrew operation updated Homebrew is present")
            expectFormat(strings.homebrewOperationFailedFormat, ["@"], "\(prefix) Homebrew operation failed format")
            expectFormat(strings.homebrewOperationElapsedFormat, ["@"], "\(prefix) Homebrew operation elapsed format")

            let rendered = [
                String(format: strings.cutMovedPluralFormat, 2),
                String(format: strings.uninstallerSelectedFormat, 1, 3),
                String(format: strings.uninstallerFreedFormat, "1 MB"),
                String(format: strings.shelfSelectedFormat, 2),
                String(format: strings.powerAdapterMaxFormat, "30 W"),
                String(format: strings.mixerInputErrorFormat, "OSStatus -1"),
                String(format: strings.homebrewConfirmInstallBodyFormat, "jq"),
                String(format: strings.homebrewConfirmUninstallBodyFormat, "jq"),
                String(format: strings.homebrewPopularityFormat, "1,234", "30"),
                String(format: strings.homebrewOperationInstallFormat, "jq"),
                String(format: strings.homebrewOperationUninstallFormat, "jq"),
                String(format: strings.homebrewOperationInstalledFormat, "jq"),
                String(format: strings.homebrewOperationUninstalledFormat, "jq"),
                String(format: strings.homebrewOperationFailedFormat, "jq"),
                String(format: strings.homebrewOperationElapsedFormat, "10s"),
            ]
            for value in rendered {
                suite.expect(!value.isEmpty && !value.contains("%"), "\(prefix) renders format strings")
            }
        }
        let infoPlist = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        let bundleLocalizations = infoPlist?["CFBundleLocalizations"] as? [String] ?? []
        suite.expect(bundleLocalizations.contains("tr"), "Info.plist declares Turkish as a bundle localization")
        suite.expect(bundleLocalizations.contains("ko"), "Info.plist declares Korean as a bundle localization")
        let baseAudioPrompt = infoPlist?["NSAudioCaptureUsageDescription"] as? String ?? ""
        suite.expect(baseAudioPrompt.contains("Vorssaint uses each app's audio"),
               "base audio permission prompt is an English fallback")
        let organizerFolderPromptKeys = [
            "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
            "NSNetworkVolumesUsageDescription", "NSRemovableVolumesUsageDescription",
        ]
        suite.expect(organizerFolderPromptKeys.allSatisfy {
                   !(infoPlist?[$0] as? String ?? "").isEmpty
               },
               "the organizer declares every supported custom destination permission")
        let localizedInfoPlists = (try? FileManager.default.contentsOfDirectory(
            atPath: "Resources"))?.filter { $0.hasSuffix(".lproj") } ?? []
        suite.expect(localizedInfoPlists.allSatisfy { folder in
            let value = (try? String(contentsOfFile: "Resources/\(folder)/InfoPlist.strings",
                                     encoding: .utf8)) ?? ""
            return organizerFolderPromptKeys.allSatisfy(value.contains)
        }, "every localization explains custom organizer folder access")
        // What the bundle says it speaks and what it ships have to be the same
        // list: a language declared without its folder makes the system offer
        // the app in it and then show every permission prompt in English.
        let shippedFolders = Set(localizedInfoPlists.map {
            $0.replacingOccurrences(of: ".lproj", with: "")
        })
        let declared = Set(bundleLocalizations).subtracting(["en"])
        suite.expect(declared == shippedFolders,
               "the bundle ships a folder for every language it claims "
               + "(claimed only: \(declared.subtracting(shippedFolders).sorted()), "
               + "shipped only: \(shippedFolders.subtracting(declared).sorted()))")
        suite.expect(bundleLocalizations.count == AppLanguage.allCases.count,
               "the bundle speaks exactly the languages the app does")
        // A symbol name that does not exist draws an empty box, and nobody
        // notices until someone opens that screen. Every name the app asks
        // for is resolved here instead.
        var missingSymbols: [String] = []
        var symbolNames: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for piece in text.components(separatedBy: "systemName: \"").dropFirst() {
                guard let end = piece.firstIndex(of: "\"") else { continue }
                let name = String(piece[piece.startIndex..<end])
                // Names built at run time are checked where they are built.
                if !name.isEmpty, !name.contains("\\") { symbolNames.insert(name) }
            }
        }
        suite.expect(symbolNames.count > 80, "the symbol names were found (\(symbolNames.count))")
        for name in symbolNames.sorted()
        where NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            missingSymbols.append(name)
        }
        suite.expect(missingSymbols.isEmpty,
               "every symbol the app draws exists (\(missingSymbols.joined(separator: ", ")))")
        // Same blind spot, other half: a file asked for by name is nil at run
        // time if it was renamed or dropped, and nothing says so until the
        // screen that needs it is opened.
        var namedResources: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for marker in ["url(forResource: \"", "path(forResource: \"", "NSImage(named: \""] {
                for piece in text.components(separatedBy: marker).dropFirst() {
                    guard let end = piece.firstIndex(of: "\"") else { continue }
                    let name = String(piece[piece.startIndex..<end])
                    if !name.isEmpty, !name.contains("\\") { namedResources.insert(name) }
                }
            }
        }
        suite.expect(namedResources.count >= 5, "the named resources were found (\(namedResources.count))")
        var shippedNames: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Resources")) ?? [] {
            let file = (path as NSString).lastPathComponent
            shippedNames.insert((file as NSString).deletingPathExtension)
            shippedNames.insert(file)
        }
        // The brand images are drawn during the build and staged from there,
        // so the build script is where their names live.
        let stagingScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        suite.expect(!stagingScript.isEmpty, "the build script reads back for its resource names")
        for word in stagingScript.components(separatedBy: CharacterSet(charactersIn: " \n\t\"'()")) {
            let file = (word as NSString).lastPathComponent
            guard !file.isEmpty else { continue }
            shippedNames.insert((file as NSString).deletingPathExtension)
            shippedNames.insert(file)
        }
        shippedNames.insert("CHANGELOG")
        let absentResources = namedResources.filter { !shippedNames.contains($0) }.sorted()
        suite.expect(absentResources.isEmpty,
               "every file the app asks for by name is in the bundle (\(absentResources.joined(separator: ", ")))")
        // The scripts that drive the Finder are compiled when they run, so an
        // unbalanced block fails in silence exactly where it matters most:
        // these are the ones that delete files and empty the trash. The
        // one-line form, "tell application X to do something", closes itself
        // and is not counted as an opening.
        var unbalancedScripts: [String] = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for chunk in text.components(separatedBy: "\"\"\"").enumerated()
            where chunk.offset % 2 == 1 && chunk.element.contains("tell application") {
                let body = chunk.element.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                func opens(_ word: String, closing: String, inline: (String) -> Bool) -> Bool {
                    let started = body.filter { $0.hasPrefix(word + " ") && !inline($0) }.count
                    let ended = body.filter { $0 == closing }.count
                    return started != ended
                }
                let name = (path as NSString).lastPathComponent
                if opens("tell", closing: "end tell", inline: { $0.contains(" to ") }) {
                    unbalancedScripts.append("\(name):tell")
                }
                if opens("repeat", closing: "end repeat", inline: { _ in false }) {
                    unbalancedScripts.append("\(name):repeat")
                }
            }
        }
        suite.expect(unbalancedScripts.isEmpty,
               "every embedded script closes what it opens (\(unbalancedScripts.joined(separator: ", ")))")
        // The command line tools the app shells out to. If macOS moves or drops
        // one, the feature that calls it fails without a word, so their absence
        // should fail here first. Framework paths are left out on purpose: they
        // are opened with dlopen and live in the shared cache, not on disk.
        var missingTools: [String] = []
        var toolPaths: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for piece in text.components(separatedBy: "\"/").dropFirst() {
                guard let end = piece.firstIndex(of: "\"") else { continue }
                let candidate = "/" + piece[piece.startIndex..<end]
                guard candidate.hasPrefix("/bin/") || candidate.hasPrefix("/usr/bin/")
                        || candidate.hasPrefix("/usr/sbin/") else { continue }
                guard !candidate.contains(" "), !candidate.contains("\\") else { continue }
                toolPaths.insert(candidate)
            }
        }
        suite.expect(toolPaths.count >= 15, "the system tools were found (\(toolPaths.count))")
        for tool in toolPaths.sorted() where !FileManager.default.fileExists(atPath: tool) {
            missingTools.append(tool)
        }
        suite.expect(missingTools.isEmpty,
               "every system tool the app runs is where it expects (\(missingTools.joined(separator: ", ")))")
        // The fan helper's launchd plist ships with the release identifier in
        // three places, and the Developer build rewrites each one so the two
        // apps can run side by side. A fourth mention added without a matching
        // rewrite would leave the Developer build asking launchd for a service
        // that is registered under the other name, and fan control would just
        // never answer.
        let helperTemplate = (try? String(
            contentsOfFile: "Resources/com.vorssaint.utils.fan-control.plist",
            encoding: .utf8)) ?? ""
        suite.expect(!helperTemplate.isEmpty, "the helper template reads back")
        let releaseHelperID = "com.vorssaint.utils.fan-control"
        let mentions = helperTemplate.components(separatedBy: releaseHelperID).count - 1
        suite.expect(mentions == 3,
               "the helper template names the release service exactly where the build rewrites it (\(mentions))")
        let buildText = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        for key in ["Set :Label $FAN_HELPER_ID",
                    "Set :BundleProgram Contents/Library/LaunchServices/$FAN_HELPER_ID",
                    "Delete :MachServices:" + releaseHelperID,
                    "Add :MachServices:$FAN_HELPER_ID"] {
            suite.expect(buildText.contains(key), "the Developer build rewrites \(key)")
        }
        // Every shortcut the app ships with is written to disk as a string and
        // read back on the next launch. One that does not survive the trip
        // would leave that feature with no shortcut at all, on a fresh install,
        // with nothing to show for it.
        let defaultShortcuts: [(String, GlobalShortcut)] = [
            ("cameraPreviewDefault", GlobalShortcut.cameraPreviewDefault),
            ("clipboardDefault", GlobalShortcut.clipboardDefault),
            ("colorPickerDefault", GlobalShortcut.colorPickerDefault),
            ("commandBarDefault", GlobalShortcut.commandBarDefault),
            ("finderRenameDefault", GlobalShortcut.finderRenameDefault),
            ("keepAwakeDefault", GlobalShortcut.keepAwakeDefault),
            ("micMuteDefault", GlobalShortcut.micMuteDefault),
            ("pastePlainDefault", GlobalShortcut.pastePlainDefault),
            ("quickLauncherDefault", GlobalShortcut.quickLauncherDefault),
            ("radialMenuDefault", GlobalShortcut.radialMenuDefault),
            ("scratchpadDefault", GlobalShortcut.scratchpadDefault),
            ("screenOCRDefault", GlobalShortcut.screenOCRDefault),
            ("screenRecorderDefault", GlobalShortcut.screenRecorderDefault),
            ("screenshotClipboardDefault", GlobalShortcut.screenshotClipboardDefault),
            ("screenshotDefault", GlobalShortcut.screenshotDefault),
            ("screenshotFullScreenDefault", GlobalShortcut.screenshotFullScreenDefault),
            ("screenshotLastCaptureDefault", GlobalShortcut.screenshotLastCaptureDefault),
            ("shelfDefault", GlobalShortcut.shelfDefault),
            ("snippetLibraryDefault", GlobalShortcut.snippetLibraryDefault),
            ("soundOutputSwitcherDefault", GlobalShortcut.soundOutputSwitcherDefault),
            ("switcherDefault", GlobalShortcut.switcherDefault),
            ("switcherWindowDefault", GlobalShortcut.switcherWindowDefault),
            ("windowDirectionalDefault", GlobalShortcut.windowDirectionalDefault),
            ("windowLayoutBottomDefault", GlobalShortcut.windowLayoutBottomDefault),
            ("windowLayoutBottomLeftDefault", GlobalShortcut.windowLayoutBottomLeftDefault),
            ("windowLayoutBottomRightDefault", GlobalShortcut.windowLayoutBottomRightDefault),
            ("windowLayoutCenterDefault", GlobalShortcut.windowLayoutCenterDefault),
            ("windowLayoutCenterThirdDefault", GlobalShortcut.windowLayoutCenterThirdDefault),
            ("windowLayoutLeftDefault", GlobalShortcut.windowLayoutLeftDefault),
            ("windowLayoutLeftThirdDefault", GlobalShortcut.windowLayoutLeftThirdDefault),
            ("windowLayoutLeftTwoThirdsDefault", GlobalShortcut.windowLayoutLeftTwoThirdsDefault),
            ("windowLayoutMaximizeDefault", GlobalShortcut.windowLayoutMaximizeDefault),
            ("windowLayoutNextDisplayDefault", GlobalShortcut.windowLayoutNextDisplayDefault),
            ("windowLayoutRestoreDefault", GlobalShortcut.windowLayoutRestoreDefault),
            ("windowLayoutRightDefault", GlobalShortcut.windowLayoutRightDefault),
            ("windowLayoutRightThirdDefault", GlobalShortcut.windowLayoutRightThirdDefault),
            ("windowLayoutRightTwoThirdsDefault", GlobalShortcut.windowLayoutRightTwoThirdsDefault),
            ("windowLayoutTopDefault", GlobalShortcut.windowLayoutTopDefault),
            ("windowLayoutTopLeftDefault", GlobalShortcut.windowLayoutTopLeftDefault),
            ("windowLayoutTopRightDefault", GlobalShortcut.windowLayoutTopRightDefault),
        ]
        suite.expect(defaultShortcuts.count == 40, "every default shortcut is in the round trip")
        var brokenShortcuts: [String] = []
        for (name, shortcut) in defaultShortcuts {
            guard let restored = GlobalShortcut(storageValue: shortcut.storageValue),
                  restored.storageValue == shortcut.storageValue else {
                brokenShortcuts.append(name)
                continue
            }
        }
        suite.expect(brokenShortcuts.isEmpty,
               "a default shortcut survives being written and read back (\(brokenShortcuts.joined(separator: ", ")))")
        // A restored backup is filtered by valueLooksRight, so a setting whose
        // own registered default fails that filter would be dropped on import
        // and come back at its factory value with nothing said. The app's own
        // defaults are the one set guaranteed to be valid, so they are the
        // honest fixture for it.
        var rejectedByOwnFilter: [String] = []
        for key in SettingsBackupSupport.exportKeys().sorted() {
            guard let value = Defaults.registeredDefaults[key] else { continue }
            if !SettingsBackupSupport.valueLooksRight(key, value) {
                rejectedByOwnFilter.append(key)
            }
        }
        suite.expect(rejectedByOwnFilter.isEmpty,
               "a restored backup keeps every setting the app itself ships (\(rejectedByOwnFilter.prefix(6).joined(separator: ", ")))")
        // The two services that hold files for the user delete only what they
        // put there themselves, and they check ownership again at the moment
        // of deletion. An unguarded removeItem added here would be the one bug
        // in this app that costs somebody a file, so it fails the suite first.
        var ungardedDeletes: [String] = []
        let ownershipGuards = ["isShelfOwnedFile", "discardablePaths", "ownedPayloadURLs",
                               "isRegularFile", "tempDir", "legacyDir", "root", "uuidString",
                               "storeRoot", "contentsOfDirectory"]
        for path in ["Sources/Vorssaint/Services/Shelf/ShelfService.swift",
                     "Sources/Vorssaint/Services/QuickTools/RecentCaptureService.swift",
                     "Sources/Vorssaint/Services/QuickTools/RecentCaptureStore.swift"] {
            let lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            suite.expect(!lines.isEmpty, "the store source reads back for its deletion check")
            for (index, line) in lines.enumerated() where line.contains("removeItem(at:") {
                let scope = lines[max(0, index - 10)...index].joined(separator: "\n")
                if !ownershipGuards.contains(where: scope.contains) {
                    ungardedDeletes.append("\((path as NSString).lastPathComponent):\(index + 1)")
                }
            }
        }
        suite.expect(ungardedDeletes.isEmpty,
               "a file is deleted only after the app checks it owns it (\(ungardedDeletes.joined(separator: ", ")))")
        let turkishInfoPlistStrings = (try? String(contentsOfFile: "Resources/tr.lproj/InfoPlist.strings",
                                                   encoding: .utf8)) ?? ""
        suite.expect(turkishInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && turkishInfoPlistStrings.contains("Hiçbir şey kaydedilmez"),
               "Turkish InfoPlist.strings localizes the audio permission prompt")
        let koreanInfoPlistStrings = (try? String(contentsOfFile: "Resources/ko.lproj/InfoPlist.strings",
                                                  encoding: .utf8)) ?? ""
        suite.expect(koreanInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && koreanInfoPlistStrings.contains("Mac 밖으로 나가지"),
               "Korean InfoPlist.strings localizes the audio permission prompt")

    }
}
