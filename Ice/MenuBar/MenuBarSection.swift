//
//  MenuBarSection.swift
//  Ice
//

import SwiftUI

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of a menu bar section.
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface.
        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }

        /// Localized string key representation.
        var localized: LocalizedStringKey {
            LocalizedStringKey(displayString)
        }
    }

    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// The shared app state.
    private weak var appState: AppState?

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: EventMonitor?

    /// A Boolean value that indicates whether the Ice Bar should be used.
    private var useIceBar: Bool {
        guard let appState else {
            return false
        }
        if isBypassActiveForCurrentScreen {
            return false
        }
        return appState.settings.general.shouldUseIceBarOnCurrentScreen
    }

    /// A Boolean value that indicates whether hiding is bypassed
    /// due to wide screen settings for the current screen.
    ///
    /// When `excludeNotchScreensFromBypass` is enabled, screens with a notch
    /// will not be affected by the wide screen bypass, allowing Ice Bar to
    /// remain functional on those screens.
    private var isBypassActiveForCurrentScreen: Bool {
        guard let appState else {
            return false
        }
        let settings = appState.settings.general
        guard settings.isWideScreenBypassActive else {
            return false
        }
        if settings.excludeNotchScreensFromBypass {
            let currentScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
            if currentScreen?.hasNotch == true {
                return false
            }
        }
        return true
    }

    /// A Boolean value that indicates whether hiding is bypassed
    /// due to wide screen settings.
    private var isBypassActive: Bool {
        isBypassActiveForCurrentScreen
    }

    /// A weak reference to the menu bar manager.
    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
    }

    /// The best screen to show the Ice Bar on.
    private weak var screenForIceBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.activeSpace.isFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            // Use the screen with the active menu bar to ensure consistency
            // with shouldUseIceBarOnCurrentScreen, especially when the
            // "Only on screens with a notch" option is enabled.
            return NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        }
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if isBypassActive {
            return false
        }
        // When preserving menu bar state (bypass active + excluding notched screens),
        // items are always visible. On notched screens, use Ice Bar panel state
        // to determine if the "hidden" items are being shown in Ice Bar.
        if shouldPreserveMenuBarState {
            let currentScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
            if currentScreen?.hasNotch == true {
                switch name {
                case .visible, .hidden:
                    return menuBarManager?.iceBarPanel.currentSection != .hidden
                case .alwaysHidden:
                    return menuBarManager?.iceBarPanel.currentSection != .alwaysHidden
                }
            }
            // On non-notched screens with preserve state, items are never hidden
            return false
        }
        if useIceBar {
            if controlItem.state == .showSection {
                return false
            }
            switch name {
            case .visible, .hidden:
                return menuBarManager?.iceBarPanel.currentSection != .hidden
            case .alwaysHidden:
                return menuBarManager?.iceBarPanel.currentSection != .alwaysHidden
            }
        }
        return controlItem.state == .hideSection
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// The hotkey to toggle the section.
    var hotkey: Hotkey? {
        guard let hotkeys = appState?.settings.hotkeys else {
            return nil
        }
        return switch name {
        case .visible: nil
        case .hidden: hotkeys.hotkey(withAction: .toggleHiddenSection)
        case .alwaysHidden: hotkeys.hotkey(withAction: .toggleAlwaysHiddenSection)
        }
    }

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .visible)
        case .hidden:
            ControlItem(identifier: .hidden)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden)
        }
        self.init(name: name, controlItem: controlItem)
    }

    /// Performs the initial setup of the section.
    func performSetup(with appState: AppState) {
        self.appState = appState
        controlItem.performSetup(with: appState)
    }

    /// Shows the section.
    func show() {
        guard let menuBarManager else {
            return
        }

        if isBypassActive {
            menuBarManager.iceBarPanel.close()
            for section in menuBarManager.sections {
                section.controlItem.state = .showSection
            }
            return
        }

        guard isHidden else {
            return
        }

        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            // TODO: Can we use isEnabled for this check?
            return
        }

        if useIceBar {
            // Update control item states. In preserve mode, we only update the
            // visible section's Ice icon to show its alternate state, but don't
            // collapse hidden/always-hidden sections since items stay visible.
            for section in menuBarManager.sections {
                switch section.name {
                case .visible:
                    // Always update Ice icon to show "expanded" state
                    section.controlItem.state = .showSection
                case .hidden, .alwaysHidden:
                    // Only collapse sections when not preserving menu bar state
                    if !shouldPreserveMenuBarState {
                        section.controlItem.state = .hideSection
                    }
                }
            }

            if let screen = screenForIceBar {
                Task {
                    switch name {
                    case .visible, .hidden:
                        await menuBarManager.iceBarPanel.show(section: .hidden, on: screen)
                    case .alwaysHidden:
                        await menuBarManager.iceBarPanel.show(section: .alwaysHidden, on: screen)
                    }
                    startRehideChecks()
                }
            }

            return // We're done.
        }

        // If we made it here, we're not using the Ice Bar.
        // Make sure it's closed.
        menuBarManager.iceBarPanel.close()

        switch name {
        case .visible, .hidden:
            for section in menuBarManager.sections where section.name != .alwaysHidden {
                section.controlItem.state = .showSection
            }
        case .alwaysHidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .showSection
            }
        }

        startRehideChecks()
    }

    /// Hides the section.
    func hide() {
        guard let menuBarManager else {
            return
        }

        if isBypassActive {
            return
        }

        guard !isHidden else {
            return
        }

        menuBarManager.iceBarPanel.close() // Make sure Ice Bar is always closed.
        menuBarManager.showOnHoverAllowed = true

        // When using Ice Bar on a notched screen while bypass is globally active,
        // don't change the menu bar item states. This prevents affecting the
        // menu bar appearance on non-notched screens that are under bypass.
        // However, we still need to update the visible section's icon to show
        // the "collapsed" state.
        if shouldPreserveMenuBarState {
            if let visibleSection = menuBarManager.sections.first(where: { $0.name == .visible }) {
                visibleSection.controlItem.state = .hideSection
            }
            stopRehideChecks()
            return
        }

        switch name {
        case _ where useIceBar, .visible, .hidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .hideSection
            }
        case .alwaysHidden:
            controlItem.state = .hideSection
        }

        stopRehideChecks()
    }

    /// A Boolean value that indicates whether the menu bar state should be
    /// preserved (not hidden) regardless of screen.
    ///
    /// This is true when wide screen bypass is globally active AND notched
    /// screens are excluded from bypass. In this mode, menu bar items stay
    /// visible at all times, and Ice Bar acts as an overlay for convenience
    /// on notched screens without affecting the global menu bar state.
    private var shouldPreserveMenuBarState: Bool {
        guard let appState else {
            return false
        }
        let settings = appState.settings.general
        return settings.isWideScreenBypassActive && settings.excludeNotchScreensFromBypass
    }

    /// Toggles the visibility of the section.
    func toggle() {
        if isHidden { show() } else { hide() }
    }

    /// Starts running checks to determine when to rehide the section.
    private func startRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()

        guard
            let appState,
            appState.settings.general.autoRehide,
            case .timed = appState.settings.general.rehideStrategy
        else {
            return
        }

        rehideMonitor = EventMonitor.universal(for: .mouseMoved) { [weak self] event in
            guard
                let self,
                let screen = NSScreen.main
            else {
                return event
            }
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                if rehideTimer == nil {
                    rehideTimer = .scheduledTimer(
                        withTimeInterval: appState.settings.general.rehideInterval,
                        repeats: false
                    ) { [weak self] _ in
                        guard
                            let self,
                            let screen = NSScreen.main
                        else {
                            return
                        }
                        if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                            Task {
                                await self.hide()
                            }
                        } else {
                            Task {
                                await self.startRehideChecks()
                            }
                        }
                    }
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// Stops running checks to determine when to rehide the section.
    private func stopRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}
