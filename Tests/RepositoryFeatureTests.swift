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

enum RepositoryFeatureTests {
    static func run(_ suite: TestSuite) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        // MARK: URL cleaning

        expectEqual(URLCleaning.clean("https://example.com/path?utm_source=news&id=42&fbclid=abc")?.url ?? "",
                    "https://example.com/path?id=42",
                    "URL cleaner removes tracking and preserves useful query")
        expectEqual(URLCleaning.clean(" https://example.com/?GCLID=one&utm_campaign=x#section ")?.url ?? "",
                    "https://example.com/#section",
                    "URL cleaner is case-insensitive and preserves fragments")
        expectEqual(URLCleaning.clean("https://example.com/?id=42")?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner leaves clean URLs alone")
        let customURLParameters = URLCleaning.customParameters(from: " Ref, source\nref,  ")
        suite.expect(customURLParameters == ["ref", "source"],
               "URL cleaner normalizes comma-separated custom parameter names")
        let customURLRules = URLCleaning.rules(globalNames: " Ref, source\nref,  ",
                                               siteNames: nil, disabledNames: nil)
        expectEqual(URLCleaning.clean("https://example.com/?REF=one&id=42&source=two",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner removes custom parameters by exact case-insensitive name")
        expectEqual(URLCleaning.clean("https://example.com/?reference=one",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?reference=one",
                    "URL cleaner does not treat custom parameter names as prefixes")
        // A grouped Form keeps a label column even for an empty label, which
        // left every field on the right half of its row. The hint has to
        // travel as `prompt:` and the label has to be hidden for a field to
        // own its whole row.
        let urlCleanerSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/URLCleanerSettings.swift",
            encoding: .utf8)) ?? ""
        suite.expect(!urlCleanerSettingsSource.contains("TextField(l10n.s."),
               "no Clean URL field spends its row on a label instead of the field")
        suite.expect(urlCleanerSettingsSource.components(separatedBy: "TextField(").count
                == urlCleanerSettingsSource.components(separatedBy: ".labelsHidden()").count,
               "every Clean URL field hides its label so the field owns the row")

        // Rules are stored as a difference from the built-in tables, never as
        // a copy of them, so names a later version adds still reach someone
        // who has already edited their rules.
        let keptUTM = URLCleaning.rules(globalNames: nil, siteNames: nil, disabledNames: "|utm_*")
        expectEqual(URLCleaning.clean("https://example.com/?utm_source=news&fbclid=abc&id=1",
                                      rules: keptUTM)?.url ?? "",
                    "https://example.com/?utm_source=news&id=1",
                    "switching the utm row off keeps every utm name and leaves the rest cleaning")
        let keptShareToken = URLCleaning.rules(globalNames: nil, siteNames: nil,
                                               disabledNames: "youtube.com|si")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=1&si=x&feature=share",
                                      rules: keptShareToken)?.url ?? "",
                    "https://www.youtube.com/watch?v=1&si=x",
                    "a switched off site name stays in the link while its siblings still go")
        let addedSiteRule = URLCleaning.rules(globalNames: nil, siteNames: "weibo.com|sudaref",
                                              disabledNames: nil)
        expectEqual(URLCleaning.clean("https://weibo.com/a?sudaref=x&id=1", rules: addedSiteRule)?.url ?? "",
                    "https://weibo.com/a?id=1",
                    "a name added to one site cleans that site")
        expectEqual(URLCleaning.clean("https://example.com/?sudaref=x", rules: addedSiteRule)?.url ?? "",
                    "https://example.com/?sudaref=x",
                    "a name added to one site never reaches another")
        suite.expect(URLCleaning.clean("https://example.com/?utm_source=a&fbclid=b&id=1")?.removed
                == ["utm_source", "fbclid"],
               "cleaning answers with the names it took out, in the order the link carried them")
        suite.expect(URLCleaning.outcome(for: nil, input: "nope") == .notAURL,
               "text that is not a link reads as no URL")
        let paddedLink = " https://example.com/?id=1 "
        suite.expect(URLCleaning.outcome(for: URLCleaning.clean(paddedLink), input: paddedLink) == .unchanged,
               "trimming alone does not count as a clean")

        let editedRules = URLCleaning.rules(globalNames: "ref", siteNames: "weibo.com|sudaref",
                                            disabledNames: "|fbclid")
        let ruleGroups = URLCleaning.ruleGroups(rules: editedRules)
        suite.expect(ruleGroups.first?.site == URLCleaning.allSites,
               "the rules that apply everywhere lead the list")
        suite.expect(ruleGroups.first?.entries.first?.name == URLCleaning.utmWildcard,
               "one row stands for every utm name")
        suite.expect(ruleGroups.first?.entries.allSatisfy {
            $0.name == URLCleaning.utmWildcard || !$0.name.hasPrefix("utm_")
        } == true, "the utm names that row already covers are not listed again")
        suite.expect(ruleGroups.first?.entries.contains { $0.name == "fbclid" && !$0.isEnabled } == true,
               "a switched off built-in stays listed so it can be switched back on")
        suite.expect(ruleGroups.first?.entries.contains { $0.name == "ref" && !$0.isBuiltIn } == true,
               "names the user added share the list with the built-in ones")
        suite.expect(ruleGroups.contains { $0.site == "weibo.com" },
               "a site the user added gets a row of its own")
        suite.expect(ruleGroups.contains { $0.site == "youtube.com" },
               "every built-in site is listed")
        expectEqual(URLCleaning.siteKey(from: " https://WWW.Weibo.com/path?x=1 ") ?? "",
                    "weibo.com", "the site field takes a pasted link and keeps the host")
        suite.expect(URLCleaning.siteKey(from: "not a host") == nil,
               "text that is not a host is refused rather than stored")
        expectEqual(URLCleaning.parameterName(from: " Ref ") ?? "", "ref",
                    "a parameter name is trimmed and lowercased")
        suite.expect(URLCleaning.parameterName(from: "a=b") == nil,
               "a name a query cannot carry as one parameter is refused")
        suite.expect(URLCleaning.tokens(from: "youtube.com|si, |ref") == ["youtube.com": ["si"], "": ["ref"]],
               "stored tokens read back as site and global names")
        expectEqual(URLCleaning.storageValue(forTokens: URLCleaning.tokens(from: "youtube.com|si, |ref")),
                    "|ref,youtube.com|si", "tokens are stored in a stable order")

        suite.expect([DefaultsKey.urlCleanerCustomParameters,
                DefaultsKey.urlCleanerSiteParameters,
                DefaultsKey.urlCleanerDisabledParameters].allSatisfy {
                    Defaults.registeredDefaults[$0] as? String == ""
                        && SettingsBackupSupport.exportKeys().contains($0)
                },
               "URL cleaner rules start empty and travel in Settings backups")
        suite.expect(URLCleaning.clean("not a url") == nil,
               "URL cleaner rejects plain text")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1TY8J67EUB/?spm_id_from=333.1007.tianma.1-1-1.click&vd_source=3b2eea5")?.url ?? "",
                    "https://www.bilibili.com/video/BV1TY8J67EUB/",
                    "URL cleaner strips Bilibili share tracking")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90&vd_source=abc")?.url ?? "",
                    "https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90",
                    "URL cleaner keeps the Bilibili part number and playback position")
        expectEqual(URLCleaning.clean("https://search.bilibili.com/all?keyword=swift&from_source=webtop_search")?.url ?? "",
                    "https://search.bilibili.com/all?keyword=swift",
                    "URL cleaner keeps the Bilibili search keyword")
        expectEqual(URLCleaning.clean("https://youtu.be/TImSMeurR84?si=Xq1&t=42")?.url ?? "",
                    "https://youtu.be/TImSMeurR84?t=42",
                    "URL cleaner strips the YouTube share token and keeps the timestamp")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=TImSMeurR84")?.url ?? "",
                    "https://www.youtube.com/watch?v=TImSMeurR84",
                    "URL cleaner leaves a bare YouTube watch link alone")
        expectEqual(URLCleaning.clean("https://x.com/user/status/1?s=20&t=abc")?.url ?? "",
                    "https://x.com/user/status/1",
                    "URL cleaner strips X share tracking")
        expectEqual(URLCleaning.clean("https://example.com/?si=keep&t=keep&s=keep")?.url ?? "",
                    "https://example.com/?si=keep&t=keep&s=keep",
                    "site rules never leak onto other hosts")
        expectEqual(URLCleaning.clean("https://open.spotify.com/track/abc?si=xyz")?.url ?? "",
                    "https://open.spotify.com/track/abc",
                    "site rules match subdomains")
        expectEqual(URLCleaning.clean("https://www.reddit.com/r/swift/comments/abc/?%24deep_link=true&%243p=x&share_id=y&sort=new")?.url ?? "",
                    "https://www.reddit.com/r/swift/comments/abc/?sort=new",
                    "URL cleaner strips Reddit's deep-link tracking in either spelling")

        // MARK: Homebrew command building and parsing

        let homebrewManagerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Homebrew/HomebrewManager.swift",
            encoding: .utf8)) ?? ""
        let homebrewRunStreaming = homebrewManagerSource.components(separatedBy: "func runStreaming(")
            .dropFirst().first?.components(separatedBy: "private func appendLog").first ?? ""
        suite.expect(homebrewRunStreaming.contains("brewSilenceTimeout")
                && !homebrewRunStreaming.contains("waitUntilExit"),
               "Homebrew operations wait on a bounded semaphore, not waitUntilExit")

        suite.expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        suite.expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        suite.expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "Error: Refusing to load formula foo from untrusted tap someone/sometap.\nRun `brew trust someone/sometap` to trust it.")
            == "someone/sometap",
               "untrusted tap name is extracted from Homebrew's refusal")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput: "Error: no such formula") == nil,
               "other Homebrew errors extract no tap")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "from untrusted tap ../evil") == nil,
               "a tap name that fails token validation is rejected")
        let trustCommand = HomebrewCommandBuilder.trustTap(brewPath: "/opt/homebrew/bin/brew", tap: "someone/sometap")
        suite.expect(trustCommand.arguments == ["trust", "--tap", "someone/sometap"],
               "trust command targets the tap explicitly")
        suite.expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        suite.expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        suite.expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "sample-tool",
                                   displayName: "Sample Tool", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        suite.expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        suite.expect(HomebrewCommandBuilder.outdated(brewPath: brewPath).arguments
               == ["outdated", "--json=v2"],
               "Homebrew outdated command uses read-only JSON v2 output")
        suite.expect(HomebrewCommandBuilder.update(brewPath: brewPath).arguments
               == ["update"],
               "Homebrew update command refreshes Homebrew metadata")
        suite.expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "sample-tool"],
               "cask install command uses --cask")
        suite.expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "sample-tool"],
               "cask uninstall command uses --cask")
        suite.expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: cask).arguments
               == ["upgrade", "--cask", "sample-tool"],
               "cask upgrade command uses --cask")
        let formula = HomebrewPackage(kind: .formula, name: "jq",
                                      displayName: "jq", desc: nil,
                                      installedVersion: "1.8.1", stableVersion: nil, homepage: nil)
        suite.expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: formula).arguments
               == ["upgrade", "jq"],
               "formula upgrade command uses separated arguments")
        suite.expect(HomebrewCommandBuilder.upgradeAll(brewPath: brewPath).arguments
               == ["upgrade"],
               "Homebrew update all command upgrades all outdated packages")

        // brew exits non-zero when it could not do all of a run, not only when it
        // did none of it, so the installed and outdated lists have to be re-read
        // after a failed operation too. Read from the source: the refresh happens
        // inside a completion closure that no unit test can drive.
        let managerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Homebrew/HomebrewManager.swift",
            encoding: .utf8)) ?? ""
        suite.expect(!managerSource.isEmpty, "HomebrewManager source is readable for the refresh checks")
        let managerCode = managerSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let refreshCalls = managerCode
            .components(separatedBy: "self.refreshInstalled(clearingError: false)").count - 1
        suite.expect(refreshCalls == 3,
               "the cancelled, needs-terminal and failed operation paths all re-read, "
               + "found \(refreshCalls)")
        let guardedBannerClears = managerCode
            .components(separatedBy: "if clearingError { errorMessage = nil }").count - 1
        suite.expect(guardedBannerClears == 2,
               "both banner clears in refreshInstalled are behind its parameter, so the reason "
               + "a failed operation gave survives the refresh that follows it, found "
               + "\(guardedBannerClears)")
        suite.expect(HomebrewOperation.Action.install.runningSystemImage == "arrow.down.circle.fill",
               "Homebrew install status uses a download icon")
        suite.expect(HomebrewOperation.Action.uninstall.runningSystemImage == "trash.circle.fill",
               "Homebrew uninstall status uses a trash icon")
        suite.expect(HomebrewOperation.Action.upgrade.runningSystemImage == "arrow.up.circle.fill",
               "Homebrew package update status uses an update icon")
        suite.expect(HomebrewOperation.Action.updateHomebrew.runningSystemImage == "arrow.triangle.2.circlepath",
               "Homebrew metadata refresh status uses a refresh icon")
        suite.expect(HomebrewOperation.Action.uninstall.clearsSelectionOnSuccess,
               "Homebrew uninstall clears details for the package that left the installed list")
        suite.expect(!HomebrewOperation.Action.install.clearsSelectionOnSuccess
                && !HomebrewOperation.Action.upgrade.clearsSelectionOnSuccess,
               "Homebrew install and upgrade preserve package details after success")
        suite.expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        suite.expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
               "Homebrew installer command matches the official install script entrypoint")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/zsh"),
                    "/Users/test/.zprofile",
                    "Homebrew shell setup uses zprofile for zsh")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/bash"),
                    "/Users/test/.bash_profile",
                    "Homebrew shell setup uses bash_profile for bash")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/opt/homebrew/bin/fish"),
                    "/Users/test/.config/fish/config.fish",
                    "Homebrew shell setup uses the interactive shell config")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/bin/zsh"),
                    #"eval "$(/opt/homebrew/bin/brew shellenv)""#,
                    "Homebrew shell setup line uses brew shellenv")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/opt/homebrew/bin/fish"),
                    "eval (/opt/homebrew/bin/brew shellenv fish)",
                    "Homebrew shell setup line matches the interactive shell")
        expectEqual(HomebrewAnalytics.url(kind: .formula).absoluteString,
                    "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json",
                    "Homebrew formula popularity uses install-on-request analytics")
        expectEqual(HomebrewAnalytics.url(kind: .cask).absoluteString,
                    "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json",
                    "Homebrew cask popularity uses cask install analytics")
        expectEqual(HomebrewAnalytics.compactCount(999), "999", "Homebrew popularity under 1K stays plain")
        expectEqual(HomebrewAnalytics.compactCount(1_250), "1.2K", "Homebrew popularity compacts thousands")
        expectEqual(HomebrewAnalytics.compactCount(1_200_000), "1.2M", "Homebrew popularity compacts millions")
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        suite.expect(shellSetupCommand.hasPrefix("/bin/sh -c ")
                && shellSetupCommand.contains("PROFILE=/Users/test/.zprofile")
                && shellSetupCommand.hasSuffix(#"; eval "$(/opt/homebrew/bin/brew shellenv)"; brew --version"#),
               "Homebrew shell setup command targets the detected profile")
        suite.expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        let alternateShellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(
            brewPath: brewPath,
            homeDirectory: "/Users/test",
            shellPath: "/opt/homebrew/bin/fish"
        )
        suite.expect(alternateShellSetupCommand.hasPrefix("/bin/sh -c ")
                && alternateShellSetupCommand.contains("/bin/mkdir -p /Users/test/.config/fish")
                && alternateShellSetupCommand.hasSuffix("; eval (/opt/homebrew/bin/brew shellenv fish); brew --version"),
               "Homebrew shell setup creates and activates the interactive shell config")
        suite.expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        suite.expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        suite.expect(HomebrewProgressParser.phase(in: "==> Installing Cask sample-tool",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        suite.expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask sample-tool",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        suite.expect(HomebrewProgressParser.phase(in: "==> Upgrading sample-formula",
                                            action: .upgrade) == .upgrading,
               "Homebrew progress parser detects upgrades")
        suite.expect(HomebrewProgressParser.phase(in: "Already up-to-date.",
                                            action: .updateHomebrew) == .refreshing,
               "Homebrew progress parser detects metadata refresh")
        suite.expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Sample.app'\u{001B}[0m")
               == "Moving App 'Sample.app'",
               "Homebrew progress parser cleans activity lines")
        suite.expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
               == "Error: Cask failed",
               "Homebrew progress parser hides command lines from visible errors")

        let homebrewJSON = """
        {
          "formulae": [
            {
              "name": "sample-formula",
              "full_name": "sample-formula",
              "desc": "Sample formula",
              "homepage": "https://example.com/sample-formula",
              "versions": { "stable": "1.8.1" },
              "installed": [{ "version": "1.8.1" }]
            },
            {
              "name": "tapped-formula",
              "full_name": "example/tap/tapped-formula",
              "desc": "Formula from a third-party tap",
              "homepage": "https://example.com/tapped-formula",
              "versions": { "stable": "2.0.0" },
              "installed": [{ "version": "1.0.0" }]
            }
          ],
          "casks": [
            {
              "token": "sample-tool",
              "name": ["Sample Tool"],
              "desc": "Sample cask",
              "homepage": "https://example.com/sample-tool",
              "version": "1.108.1",
              "installed": "1.107.0"
            },
            {
              "token": "tapped-tool",
              "full_token": "example/tap/tapped-tool",
              "name": ["Tapped Tool"],
              "desc": "Cask from a third-party tap",
              "homepage": "https://example.com/tapped-tool",
              "version": "2.0.0",
              "installed": "1.0.0"
            }
          ]
        }
        """
        let homebrewPackages = (try? HomebrewParser.parseInfoJSON(Data(homebrewJSON.utf8))) ?? []
        suite.expect(homebrewPackages.count == 4, "Homebrew JSON parser keeps formulae and casks")
        suite.expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        suite.expect(homebrewPackages.first(where: { $0.name == "sample-formula" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        let tappedFormula = homebrewPackages.first { $0.name == "example/tap/tapped-formula" }
        suite.expect(tappedFormula?.displayName == "example/tap/tapped-formula",
               "Homebrew parser keeps the canonical name for a formula from a tap")
        suite.expect(homebrewPackages.first(where: { $0.name == "sample-tool" })?.displayName == "Sample Tool",
               "Homebrew parser reads cask display name")
        let tappedCask = homebrewPackages.first { $0.name == "tapped-tool" }
        suite.expect(tappedCask != nil,
               "Homebrew parser identifies a cask from a tap by its short token")
        suite.expect(tappedCask?.displayName == "Tapped Tool",
               "Homebrew parser keeps the human-readable name for a cask from a tap")
        let cleanCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(homebrewJSON)) ?? []
        suite.expect(cleanCommandPackages.count == 4,
               "Homebrew command output parser keeps clean JSON")
        let noisyHomebrewOutput = """
        Warning: Skipping some beta metadata
        {"notice": "not package data"}
        \(homebrewJSON)
        Warning: A newer Homebrew beta changed an optional field
        """
        let noisyCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(noisyHomebrewOutput)) ?? []
        suite.expect(noisyCommandPackages.count == 4,
               "Homebrew command output parser accepts warnings around JSON")
        suite.expect(noisyCommandPackages.first(where: { $0.name == "sample-tool" })?.installedVersion == "1.107.0",
               "Homebrew command output parser keeps package data from noisy output")
        suite.expect((try? HomebrewParser.parseInfoCommandOutput("Warning: no JSON here")) == nil,
               "Homebrew command output parser rejects output without valid JSON")
        let outdatedJSON = """
        {
          "formulae": [
            {
              "name": "fmt",
              "installed_versions": ["12.1.0"],
              "current_version": "12.2.0",
              "pinned": false
            },
            {
              "name": "example/tap/tapped-formula",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ],
          "casks": [
            {
              "name": "sample-tool",
              "installed_versions": ["1.107.0"],
              "current_version": "1.108.1",
              "pinned": true
            },
            {
              "name": "tapped-tool",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ]
        }
        """
        let outdatedPackages = (try? HomebrewParser.parseOutdatedJSON(Data(outdatedJSON.utf8))) ?? [:]
        suite.expect(outdatedPackages.count == 4,
               "Homebrew outdated parser keeps formulae and casks")
        suite.expect(outdatedPackages["formula:fmt"]?.versionSummary == "12.1.0 -> 12.2.0",
               "Homebrew outdated parser renders installed to current version")
        suite.expect(outdatedPackages["cask:sample-tool"]?.isPinned == true,
               "Homebrew outdated parser reads pinned status")
        suite.expect(tappedFormula.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same ID for tapped formulae")
        suite.expect(tappedCask?.id == "cask:tapped-tool",
               "Homebrew installed cask data stays on the short token brew outdated reports")
        suite.expect(tappedCask.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same short-token ID for tapped casks")
        let noisyOutdatedOutput = """
        Warning: Homebrew updated metadata
        {"notice": "not outdated data"}
        \(outdatedJSON)
        """
        let noisyOutdatedPackages = (try? HomebrewParser.parseOutdatedCommandOutput(noisyOutdatedOutput)) ?? [:]
        suite.expect(noisyOutdatedPackages["formula:fmt"]?.currentVersion == "12.2.0",
               "Homebrew outdated command output parser accepts warnings around JSON")
        let orderingPackages = [
            HomebrewPackage(kind: .cask, name: "alpha-tool", displayName: "Alpha Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil),
            HomebrewPackage(kind: .cask, name: "beta-tool", displayName: "Beta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .cask, name: "beta-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "gamma-tool", displayName: "Gamma Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .formula, name: "gamma-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "delta-tool", displayName: "Delta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil)
        ]
        suite.expect(HomebrewPackageOrdering.updatesFirst(orderingPackages).map(\.name)
               == ["beta-tool", "gamma-tool", "alpha-tool", "delta-tool"],
               "Homebrew installed packages keep all pending updates first without reordering either group")
        let searchPackages = HomebrewParser.parseSearchOutput("sample-formula\nbad token\nsample-filter\nsample-tool\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        suite.expect(searchPackages.map(\.name) == ["sample-formula", "sample-filter", "sample-tool"],
               "Homebrew search parser keeps valid one-token results")
        let analyticsJSON = """
        {
          "category": "formula_install_on_request",
          "formulae": {
            "sample-formula": [
              { "formula": "sample-formula", "count": "21,557" },
              { "formula": "sample-formula --HEAD", "count": "30" }
            ],
            "sample-filter": [
              { "formula": "sample-filter", "count": "42,001" }
            ]
          }
        }
        """
        let popularity = (try? HomebrewAnalytics.parse(Data(analyticsJSON.utf8), kind: .formula)) ?? [:]
        suite.expect(popularity["sample-formula"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        suite.expect(popularity["sample-filter"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        suite.expect(rankedPackages.map(\.name) == ["sample-filter", "sample-formula", "sample-tool"],
               "Homebrew search results sort by popularity first")
        suite.expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")

        // MARK: Result

        // MARK: Every defaults suite stays inside a namespace build.sh sweeps
        // A UserDefaults suite leaves an empty plist in ~/Library/Preferences
        // even after `removePersistentDomain`, and cfprefsd writes that file
        // back out around the time this process exits, so the run cannot delete
        // it itself. `build.sh --test` clears them afterwards, by name prefix.
        // A suite named outside those prefixes survives every run instead.
        let testSource = ((try? FileManager.default.contentsOfDirectory(atPath: "Tests")) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .compactMap { try? String(contentsOfFile: "Tests/" + $0, encoding: .utf8) }
            .joined(separator: "\n")
        suite.expect(!testSource.isEmpty, "the test file reads back for its own source checks")
        // The prefixes are read out of the sweep itself, so the check and the
        // thing it guards cannot drift apart.
        let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        let sweepBody = buildScript.components(separatedBy: "discard_test_preferences() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let sweptNamespaces = sweepBody.components(separatedBy: "\"")
            .enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            .filter { $0.hasSuffix(".") }
        suite.expect(!sweptNamespaces.isEmpty, "the swept namespaces read back out of build.sh")
        suite.expect(sweepBody.contains("rm -f \"$preferences\"/$name*.plist(N)"),
               "the defaults preference sweep tolerates an already-empty namespace")
        // Split so this needle is not itself a match in the text it scans.
        let suiteCall = "UserDefaults(suiteName" + ": "
        let suiteArguments = testSource.components(separatedBy: suiteCall)
            .dropFirst()
            .map { String($0.prefix { $0 != ")" && $0 != "," && !$0.isNewline }) }
        suite.expect(!suiteArguments.isEmpty, "the namespace check finds the suites it guards")
        for argument in Set(suiteArguments) {
            let name: String?
            if argument.hasPrefix("\"") {
                name = String(argument.dropFirst().prefix { $0 != "\"" })
            } else {
                name = testSource.components(separatedBy: "let \(argument) = \"")
                    .dropFirst().first
                    .map { String($0.prefix { $0 != "\"" }) }
            }
            suite.expect(name.map { value in sweptNamespaces.contains { value.hasPrefix($0) } } == true,
                   "defaults suite \(argument) is named inside a namespace build.sh sweeps")
        }

        // MARK: Every temp dir build.sh stages in is swept when the script ends
        // `mktemp -d` lands outside the repo, so a dir the script does not
        // remove survives the run — a successful one as much as a failed one.
        // The sweep is therefore a trap, and a staging dir added later leaks on
        // every build until it is named in cleanup(). The names are read out of
        // the script so the two cannot drift apart.
        // The trap has to be installed before the first dir exists: a failure
        // between `mktemp -d` and a later `trap` leaks exactly as before.
        let sweepInstalled = buildScript.range(of: "trap cleanup EXIT")?.lowerBound
        let firstStaged = buildScript.range(of: "mktemp -d")?.lowerBound
        suite.expect(sweepInstalled != nil && firstStaged != nil && sweepInstalled! < firstStaged!,
               "build.sh installs the temp dir sweep before it stages the first dir")
        // zsh runs the EXIT trap on HUP but not on INT or TERM, so the signals
        // have to reach it through `exit` or Ctrl-C leaks the staged bundle.
        let signalsRouted = buildScript.range(of: "trap 'exit 1' INT TERM HUP")?.lowerBound
        suite.expect(signalsRouted != nil && firstStaged != nil && signalsRouted! < firstStaged!,
               "build.sh routes interrupts through the sweep before it stages the first dir")
        let cleanupBody = buildScript.components(separatedBy: "cleanup() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let stagedTempDirs = buildScript.components(separatedBy: "=\"$(mktemp -d)\"")
            .dropLast()
            .compactMap {
                $0.split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "\t" })
                    .last.map(String.init)
            }
        suite.expect(!stagedTempDirs.isEmpty, "the staged temp dirs read back out of build.sh")
        // A dir reached through a path suffix — `X="$(mktemp -d)/name"` — puts
        // the parent in no variable at all, which is how the bundle staging dir
        // leaked. Every call has to be captured whole to be sweepable.
        suite.expect(buildScript.components(separatedBy: "mktemp -d").count - 1 == stagedTempDirs.count,
               "every mktemp -d in build.sh is a whole capture — no path suffix, no other spelling")
        for variable in Set(stagedTempDirs) {
            suite.expect(cleanupBody.contains("\"$\(variable)\""),
                   "temp dir \(variable) is swept by build.sh cleanup()")
            // The sweep runs under `set -u` before the dir is staged: an entry
            // whose variable is not empty first aborts cleanup() at that line,
            // leaving everything listed below it unswept and the exit status
            // untouched. The empty assignment is the third line of the pattern.
            // The leading newline keeps ICON_TMP off STAGE_ICON_TMP.
            let initialized = buildScript.range(of: "\n\(variable)=\"\"")?.lowerBound
            suite.expect(initialized != nil && sweepInstalled != nil && initialized! < sweepInstalled!,
                   "temp dir \(variable) is empty before the sweep is installed")
        }

        // MARK: An identity-less build that installs creates its stable signing identity
        // An ad-hoc signature changes hash on every build, so macOS orphans
        // Accessibility and Screen Recording grants on each rebuild while
        // System Settings keeps showing them as granted. build.sh therefore
        // routes identity-less installs through Tools/setup-signing.sh before
        // signing. The needle is the invocation at the start of a command
        // line: the ad-hoc fallback's advice string also names the script, and
        // must not satisfy this check.
        let runsSigningSetup = buildScript.components(separatedBy: "\n").contains {
            $0.range(of: #"^\s*(if\s+!?\s*)?\./Tools/setup-signing\.sh"#,
                     options: .regularExpression) != nil
        }
        suite.expect(runsSigningSetup,
               "an identity-less build that installs invokes Tools/setup-signing.sh itself")
        // The guard is on the install, not on the variant: a plain --install
        // replaces the bundle under the released id, so it strands the grants
        // on the app people actually use. CI never passes --install.
        let buildScriptCode = buildScript.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        suite.expect(buildScriptCode.contains { $0.contains("(( DEV || INSTALL ))")
                                            && $0.contains("developer_id_identity") },
               "the signing setup guard covers every install, not only the Developer variant")
        // The setup script must run against the stock /usr/bin/openssl, which
        // is LibreSSL: it rejects OpenSSL 3's -legacy flag outright, and the
        // script once died on exactly that with its stderr discarded. The
        // portable spelling names the PBE algorithms instead of the flag.
        let signingSetup = (try? String(contentsOfFile: "Tools/setup-signing.sh",
                                         encoding: .utf8)) ?? ""
        suite.expect(!signingSetup.isEmpty, "the signing setup script reads back for its shape check")
        let signingSetupCode = signingSetup.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        suite.expect(!signingSetupCode.contains("-legacy"),
               "setup-signing.sh avoids the -legacy flag the stock LibreSSL openssl rejects")

        // MARK: The stable identity is judged by whether codesign can sign with it
        // A find-identity listing names certificates codesign then rejects, and
        // -v excludes every self-signed one, so neither spelling may decide.
        for (script, code, identity) in [("build.sh", buildScriptCode, "$LEGACY_IDENTITY"),
                                         ("Tools/setup-signing.sh", signingSetupCode.components(separatedBy: "\n"),
                                          "$IDENTITY")] {
            suite.expect(!code.contains { $0.contains("find-identity") && $0.contains(identity) },
                   "\(script) never decides the stable identity by a find-identity listing")
            suite.expect(code.contains { $0.contains("cp /bin/echo") }
                    && code.contains { $0.contains("--sign \"\(identity)\" \"$probe\"") },
                   "\(script) asks codesign to sign a throwaway copy of /bin/echo with the stable identity")
        }

        // MARK: Uninstallation paths stay aligned across SelfUninstall and Tools/uninstall.sh
        let selfUninstallSource = (try? String(contentsOfFile: "Sources/Vorssaint/Services/SelfUninstall.swift",
                                              encoding: .utf8)) ?? ""
        let uninstallScriptSource = (try? String(contentsOfFile: "Tools/uninstall.sh",
                                                encoding: .utf8)) ?? ""
        suite.expect(!selfUninstallSource.isEmpty && !uninstallScriptSource.isEmpty,
               "uninstall sources read back for uninstallation alignment check")
        let queryHabitSupportSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarSupport.swift",
            encoding: .utf8)) ?? ""
        suite.expect(selfUninstallSource.contains("CommandBarQueryHabits.removeInstallationKey()")
                && queryHabitSupportSource.contains("installationKeyCache.stopAndRemove {")
                && queryHabitSupportSource.contains("SecItemDelete([")
                && queryHabitSupportSource.contains("kSecClass: kSecClassGenericPassword")
                && queryHabitSupportSource.contains("kSecAttrService: keyService")
                && queryHabitSupportSource.contains("kSecAttrAccount: keyAccount")
                && queryHabitSupportSource.contains("keyService = installationKeyService(")
                && queryHabitSupportSource.contains("keyAccount = \"hmac-key\"")
                && uninstallScriptSource.contains("/usr/bin/security delete-generic-password")
                && uninstallScriptSource.contains("-s \"$BUNDLE.command-bar-query-habits\" -a \"hmac-key\""),
               "both uninstall paths remove only the query-learning Keychain item")
        let requiredSubpaths = ["Library/Application Support", "Library/Caches", "Library/HTTPStorages"]
        for subpath in requiredSubpaths {
            suite.expect(selfUninstallSource.contains(subpath) && uninstallScriptSource.contains(subpath),
                   "both in-app and script uninstall sweep \(subpath)")
        }
        suite.expect(uninstallScriptSource.contains("Library/Preferences/ByHost"),
               "script uninstall sweeps ByHost preferences")
        // Restoring sleep used to be fired and forgotten at both exits. A
        // failure there leaves `pmset disablesleep 1` set system-wide, and
        // removal deletes the flag that launch-time recovery reads before it
        // reads the setting, so nothing repairs it afterwards — a reinstall
        // included.
        let uninstallerSource = (try? String(contentsOfFile: "Sources/Vorssaint/Support/Uninstaller.swift",
                                             encoding: .utf8)) ?? ""
        suite.expect(!uninstallerSource.isEmpty,
               "uninstaller entry point reads back for the sleep restore check")
        suite.expect(!selfUninstallSource.contains("_ = Sudoers.pmsetDisableSleep")
                && !uninstallerSource.contains("_ = Sudoers.pmsetDisableSleep"),
               "neither uninstall path discards the result of restoring sleep")
        suite.expect(selfUninstallSource.contains("guard detachFromSystem() else")
                && selfUninstallSource.contains("restoreSleepBeforeRemoval() -> Bool")
                && selfUninstallSource.contains("guard FanControlService.restoreAndUnregisterForRemoval() else")
                && selfUninstallSource.contains("adminPromptRecover")
                && selfUninstallSource.contains("verification.status == 0"),
               "in-app uninstall aborts unless fans and normal sleep are restored before removal")
        suite.expect(uninstallScriptSource.contains("SleepDisabled"),
               "script uninstall reads the sleep setting back for itself")

    }
}
