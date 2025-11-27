//
//  GeneralSettings.swift
//  Ice
//

import Combine
import OSLog
import SwiftUI

// MARK: - GeneralSettings

/// Model for the app's General settings.
@MainActor
final class GeneralSettings: ObservableObject {
    /// A Boolean value that indicates whether the Ice icon
    /// should be shown.
    @Published var showIceIcon = true

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var iceIcon: ControlItemImageSet = .defaultIceIcon

    /// The last user-selected custom Ice icon.
    @Published var lastCustomIceIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom Ice icons
    /// should be rendered as template images.
    @Published var customIceIconIsTemplate = false

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    @Published var useIceBar = false

    /// The location where the Ice Bar appears.
    @Published var iceBarLocation: IceBarLocation = .dynamic

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    @Published var showOnClick = true

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = false

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    @Published var showOnScroll = true

    /// The offset to apply to the menu bar item spacing and padding.
    @Published var itemSpacingOffset: Double = 0

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    @Published var autoRehide = true

    /// A strategy that determines how the auto-rehide feature works.
    @Published var rehideStrategy: RehideStrategy = .smart

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    @Published var rehideInterval: TimeInterval = 15

    /// A Boolean value that indicates whether Ice should bypass
    /// hiding when the screen is wider than the threshold.
    @Published var enableWideScreenBypass = false

    /// The screen width threshold for the wide screen bypass feature.
    /// When any connected screen's width exceeds this value, Ice will
    /// show all menu bar items without hiding.
    @Published var wideScreenBypassThreshold: Double = 1920

    /// A Boolean value that indicates whether Ice should only hide
    /// menu bar items on screens with a notch.
    @Published var onlyShowOnScreensWithNotch = false

    /// A Boolean value that indicates whether screens with a notch
    /// should be excluded from the wide screen bypass check.
    ///
    /// When enabled, Ice will not consider screens with a notch when
    /// determining if the wide screen bypass should be active. This
    /// allows users to keep Ice Bar functionality on built-in MacBook
    /// displays (which have notches) while still bypassing on external
    /// wide monitors.
    @Published var excludeNotchScreensFromBypass = false

    /// A Boolean value that indicates whether the wide screen bypass
    /// is currently active based on the current screen configuration.
    var isWideScreenBypassActive: Bool {
        guard enableWideScreenBypass else {
            return false
        }
        return NSScreen.screens.contains { screen in
            let meetsWidthThreshold = screen.frame.width >= wideScreenBypassThreshold
            if excludeNotchScreensFromBypass && screen.hasNotch {
                return false
            }
            return meetsWidthThreshold
        }
    }

    /// A Boolean value that indicates whether the Ice Bar should only
    /// be used on screens with a notch.
    var shouldUseIceBarOnCurrentScreen: Bool {
        guard useIceBar else {
            return false
        }
        guard onlyShowOnScreensWithNotch else {
            return true
        }
        let activeScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        return activeScreen?.hasNotch ?? false
    }

    /// Encoder for properties.
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showIceIcon, assign: &showIceIcon)
        Defaults.ifPresent(key: .customIceIconIsTemplate, assign: &customIceIconIsTemplate)
        Defaults.ifPresent(key: .useIceBar, assign: &useIceBar)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        Defaults.ifPresent(key: .itemSpacingOffset, assign: &itemSpacingOffset)
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval, assign: &rehideInterval)
        Defaults.ifPresent(key: .enableWideScreenBypass, assign: &enableWideScreenBypass)
        Defaults.ifPresent(key: .wideScreenBypassThreshold, assign: &wideScreenBypassThreshold)
        Defaults.ifPresent(key: .onlyShowOnScreensWithNotch, assign: &onlyShowOnScreensWithNotch)
        Defaults.ifPresent(key: .excludeNotchScreensFromBypass, assign: &excludeNotchScreensFromBypass)

        Defaults.ifPresent(key: .iceBarLocation) { rawValue in
            if let location = IceBarLocation(rawValue: rawValue) {
                iceBarLocation = location
            }
        }
        Defaults.ifPresent(key: .rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }

        if let data = Defaults.data(forKey: .iceIcon) {
            do {
                iceIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                Logger.serialization.error("Error decoding Ice icon: \(error, privacy: .public)")
            }
            if case .custom = iceIcon.name {
                lastCustomIceIcon = iceIcon
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $showIceIcon
            .receive(on: DispatchQueue.main)
            .sink { showIceIcon in
                Defaults.set(showIceIcon, forKey: .showIceIcon)
            }
            .store(in: &c)

        $iceIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iceIcon in
                guard let self else {
                    return
                }
                if case .custom = iceIcon.name {
                    lastCustomIceIcon = iceIcon
                }
                do {
                    let data = try encoder.encode(iceIcon)
                    Defaults.set(data, forKey: .iceIcon)
                } catch {
                    Logger.serialization.error("Error encoding Ice icon: \(error, privacy: .public)")
                }
            }
            .store(in: &c)

        $customIceIconIsTemplate
            .receive(on: DispatchQueue.main)
            .sink { isTemplate in
                Defaults.set(isTemplate, forKey: .customIceIconIsTemplate)
            }
            .store(in: &c)

        $useIceBar
            .receive(on: DispatchQueue.main)
            .sink { useIceBar in
                Defaults.set(useIceBar, forKey: .useIceBar)
            }
            .store(in: &c)

        $iceBarLocation
            .receive(on: DispatchQueue.main)
            .sink { location in
                Defaults.set(location.rawValue, forKey: .iceBarLocation)
            }
            .store(in: &c)

        $showOnClick
            .receive(on: DispatchQueue.main)
            .sink { showOnClick in
                Defaults.set(showOnClick, forKey: .showOnClick)
            }
            .store(in: &c)

        $showOnHover
            .receive(on: DispatchQueue.main)
            .sink { showOnHover in
                Defaults.set(showOnHover, forKey: .showOnHover)
            }
            .store(in: &c)

        $showOnScroll
            .receive(on: DispatchQueue.main)
            .sink { showOnScroll in
                Defaults.set(showOnScroll, forKey: .showOnScroll)
            }
            .store(in: &c)

        $itemSpacingOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] offset in
                Defaults.set(offset, forKey: .itemSpacingOffset)
                appState?.spacingManager.offset = Int(offset)
            }
            .store(in: &c)

        $autoRehide
            .receive(on: DispatchQueue.main)
            .sink { autoRehide in
                Defaults.set(autoRehide, forKey: .autoRehide)
            }
            .store(in: &c)

        $rehideStrategy
            .receive(on: DispatchQueue.main)
            .sink { strategy in
                Defaults.set(strategy.rawValue, forKey: .rehideStrategy)
            }
            .store(in: &c)

        $rehideInterval
            .receive(on: DispatchQueue.main)
            .sink { interval in
                Defaults.set(interval, forKey: .rehideInterval)
            }
            .store(in: &c)

        $enableWideScreenBypass
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Defaults.set(enabled, forKey: .enableWideScreenBypass)
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        $wideScreenBypassThreshold
            .receive(on: DispatchQueue.main)
            .sink { [weak self] threshold in
                Defaults.set(threshold, forKey: .wideScreenBypassThreshold)
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        $onlyShowOnScreensWithNotch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Defaults.set(enabled, forKey: .onlyShowOnScreensWithNotch)
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        $excludeNotchScreensFromBypass
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Defaults.set(enabled, forKey: .excludeNotchScreensFromBypass)
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        // Monitor app activation to detect when user switches between screens
        // by clicking on windows on different monitors.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyBypassIfNeeded()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Applies bypass settings by showing all menu bar sections
    /// when the wide screen bypass is active for the current screen.
    private func applyBypassIfNeeded() {
        guard let menuBarManager = appState?.menuBarManager else {
            return
        }
        guard isWideScreenBypassActive else {
            return
        }
        // When excludeNotchScreensFromBypass is enabled, don't apply bypass
        // on screens with a notch.
        if excludeNotchScreensFromBypass {
            let currentScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
            if currentScreen?.hasNotch == true {
                // On notched screens, ensure the icon reflects the Ice Bar state.
                // If Ice Bar is not presented, set the icon to collapsed state.
                if !menuBarManager.iceBarPanel.isVisible {
                    if let visibleSection = menuBarManager.section(withName: .visible) {
                        visibleSection.controlItem.state = .hideSection
                    }
                }
                return
            }
            // On non-notched screens with excludeNotchScreensFromBypass enabled,
            // show all items (bypass mode) but keep icon in collapsed state
            // to maintain consistency when switching between screens.
            menuBarManager.iceBarPanel.close()
            for section in menuBarManager.sections where section.name != .visible {
                section.controlItem.state = .showSection
            }
            return
        }
        menuBarManager.iceBarPanel.close()
        for section in menuBarManager.sections {
            section.controlItem.state = .showSection
        }
    }
}

// MARK: - RehideStrategy

/// A type that determines how the auto-rehide feature works.
enum RehideStrategy: Int, CaseIterable, Identifiable {
    /// Menu bar items are rehidden using a smart algorithm.
    case smart = 0
    /// Menu bar items are rehidden after a given time interval.
    case timed = 1
    /// Menu bar items are rehidden when the focused app changes.
    case focusedApp = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .smart: "Smart"
        case .timed: "Timed"
        case .focusedApp: "Focused app"
        }
    }
}
