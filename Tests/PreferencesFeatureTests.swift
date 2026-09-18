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

enum PreferencesFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: Registered defaults

        let registeredDefaults = Defaults.registeredDefaults
        suite.expect(registeredDefaults[DefaultsKey.monitorMemoryMetric] as? String == "used",
               "monitor memory metric defaults to memory used")
        suite.expect(Defaults.sanitizedMonitorMemoryMetric("app") == "app",
               "app is an allowed memory metric")
        suite.expect(Defaults.sanitizedMonitorMemoryMetric("bogus") == "used",
               "unknown memory metric values fall back to used")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.monitorMemoryMetric),
               "monitor memory metric is included in settings backups")
        suite.expect(registeredDefaults[DefaultsKey.appearance] as? String == AppAppearance.system.rawValue,
               "the app follows the system appearance until the user picks a side")
        suite.expect(registeredDefaults[DefaultsKey.liquidGlassEnabled] as? Bool == false,
               "liquid glass appearance is opt-in")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.liquidGlassEnabled),
               "liquid glass appearance follows settings backups")
        suite.expect(AppAppearance.sanitized(nil) == .system
                && AppAppearance.sanitized("nonsense") == .system,
               "an unknown stored appearance falls back to the system one")
        suite.expect(AppAppearance.sanitized("dark") == .dark && AppAppearance.sanitized("light") == .light,
               "stored appearance values survive a relaunch")
        suite.expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"],
               "appearance raw values are persisted keys and their order is the picker order")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeAutoStart] as? Bool == false,
               "Keep Awake launch restore is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeRightClickToggle] as? Bool == false,
               "right-click Keep Awake toggle is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeAllowDisplaySleep] as? Bool == false,
               "Keep Awake keeps the display on by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeRightClickToggle),
               "right-click Keep Awake preference follows settings backups")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeAllowDisplaySleep),
               "display sleep preference follows settings backups")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeExternalDisplay] as? Bool == false,
               "external-display Keep Awake is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeConnectedToPower] as? Bool == false,
               "power-connected Keep Awake is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeRunningApps] as? Bool == false,
               "running-apps Keep Awake is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeRunningAppBundleIDs] as? [String] == [],
               "running-apps Keep Awake starts with an empty app list")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeRunningApps),
               "running-apps Keep Awake preference follows settings backups")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeRunningAppBundleIDs),
               "running-apps Keep Awake app list follows settings backups")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakePauseWhenLocked] as? Bool == false,
               "pausing Keep Awake on screen lock is opt-in")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakePauseWhenLocked),
               "the Keep Awake screen-lock preference follows settings backups")
        suite.expect(registeredDefaults[DefaultsKey.hotkeyEnabled] as? Bool == true,
               "global hotkey is on for clean installs")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeShortcut] as? String == "control+option+command:40",
               "keep awake shortcut defaults to Ctrl+Opt+Cmd+K")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeIconTint] as? String == KeepAwakeIconTint.orange.rawValue,
               "keep-awake active icon tint defaults to orange")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeActiveIcon] as? String == KeepAwakeActiveIcon.vorssaint.rawValue,
               "keep-awake active icon defaults to the Vorssaint glyph")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeMouseJiggleEnabled] as? Bool == false,
               "Keep Awake mouse movement is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keepAwakeMouseJiggleInterval] as? Int == 5,
               "Keep Awake mouse movement defaults to five minutes")
        suite.expect(Defaults.sanitizedKeepAwakeMouseJiggleInterval(10) == 10,
               "valid Keep Awake mouse movement interval is preserved")
        suite.expect(Defaults.sanitizedKeepAwakeMouseJiggleInterval(3) == 5,
               "invalid Keep Awake mouse movement interval falls back to five minutes")
        suite.expect(Defaults.sanitizedKeepAwakeIconTint("pink") == .pink,
               "valid keep-awake active icon tint is preserved")
        suite.expect(Defaults.sanitizedKeepAwakeIconTint("bad") == .orange,
               "invalid keep-awake active icon tint falls back to orange")
        suite.expect(Defaults.sanitizedKeepAwakeActiveIcon("coffee") == .coffee,
               "valid keep-awake active icon is preserved")
        suite.expect(Defaults.sanitizedKeepAwakeActiveIcon("bad") == .vorssaint,
               "invalid keep-awake active icon falls back to the Vorssaint glyph")
        suite.expect(KeepAwakeActiveIcon.eye.systemSymbolName == "eye.fill",
               "keep-awake eye option maps to its menu bar symbol")
        suite.expect(!KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: []),
               "no online display does not count as an external display")
        suite.expect(!KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: [true]),
               "the built-in screen does not count as an external display")
        suite.expect(KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: [true, false]),
               "an online non-built-in screen counts as an external display")
        suite.expect(!KeepAwakeAutomationSupport.selectedAppsAreRunning(
            selectedBundleIDs: [],
            runningBundleIDs: ["com.example.app"]
        ), "an empty selected-app list never matches a running app")
        suite.expect(!KeepAwakeAutomationSupport.selectedAppsAreRunning(
            selectedBundleIDs: ["com.example.app"],
            runningBundleIDs: ["com.other.app"]
        ), "a selected app that is not running does not match")
        suite.expect(KeepAwakeAutomationSupport.selectedAppsAreRunning(
            selectedBundleIDs: ["com.example.app", "com.other.app"],
            runningBundleIDs: ["com.helper", "com.example.app"]
        ), "any selected app that is running matches, focused or not")
        let combinedKeepAwakeConditions = KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: true,
            externalDisplayConnected: true,
            powerEnabled: true,
            connectedToPower: true,
            runningAppsEnabled: true,
            selectedAppsRunning: true
        )
        suite.expect(combinedKeepAwakeConditions == [.externalDisplay, .power, .runningApps],
               "enabled Keep Awake conditions combine with OR behavior")
        suite.expect(KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: false,
            externalDisplayConnected: false,
            powerEnabled: false,
            connectedToPower: false,
            runningAppsEnabled: true,
            selectedAppsRunning: true
        ) == [.runningApps], "a running selected app matches the running-apps condition")
        suite.expect(KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: false,
            externalDisplayConnected: false,
            powerEnabled: false,
            connectedToPower: false,
            runningAppsEnabled: true,
            selectedAppsRunning: false
        ).isEmpty, "running-apps stays off when none of the selected apps are open")
        suite.expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [.externalDisplay],
            sessionActive: false,
            automaticSessionActive: false
        ) == .activate, "an external display starts the automatic session")
        suite.expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [],
            sessionActive: true,
            automaticSessionActive: true
        ) == .deactivate, "clearing every matching condition ends the automatic session")
        suite.expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [],
            sessionActive: true,
            automaticSessionActive: false
        ) == .none, "clearing automatic conditions does not end a manual session")
        suite.expect(KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: ["CGSSessionScreenIsLocked": true]
        ), "the Keep Awake lock guard reads a locked session")
        suite.expect(!KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: ["CGSSessionScreenIsLocked": false]
        ), "the Keep Awake lock guard reads an unlocked session")
        suite.expect(KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: ["CGSSessionScreenIsLocked": NSNumber(value: true)]
        ), "the Keep Awake lock guard accepts the session dictionary's numeric bridge")
        suite.expect(!KeepAwakeAutomationSupport.isScreenLocked(sessionDictionary: nil),
               "an unreadable lock state does not strand Keep Awake in a pause")
        let sleepDisabledReport = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
        """
        let sleepEnabledReport = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         standby              1
        """
        suite.expect(SudoersSupport.sleepDisabled(inPmsetOutput: sleepDisabledReport),
               "a pmset report with SleepDisabled 1 reads as lid sleep disabled")
        suite.expect(!SudoersSupport.sleepDisabled(inPmsetOutput: sleepEnabledReport),
               "a pmset report with SleepDisabled 0 reads as lid sleep enabled")
        suite.expect(!SudoersSupport.sleepDisabled(inPmsetOutput: ""),
               "an empty pmset report reads as lid sleep enabled")
        // The rule is granted by uid so every short name works, including the
        // email-style ones SSO enrollment produces (#915). The uid renders as
        // bare digits and the rest is a fixed literal, so the whole line must
        // stay inside a character set that neither sudoers nor a single-quoted
        // shell string can read as anything but itself.
        suite.expect(SudoersSupport.clamshellRule(uid: 501)
               == "#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0",
               "the closed-lid sudoers rule grants pmset disablesleep to the uid")
        suite.expect(SudoersSupport.clamshellRule(uid: uid_t.max)
               .range(of: #"^#[0-9]+ [A-Za-z0-9()=:,./ ]+$"#, options: .regularExpression) != nil,
               "the closed-lid sudoers rule never contains shell or sudoers metacharacters")
    }
}
