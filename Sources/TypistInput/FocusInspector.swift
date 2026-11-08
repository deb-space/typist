// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// What has keyboard focus right now, as seen through the Accessibility API.
public struct FocusInfo: Sendable, Codable {
    public var appName: String?
    public var bundleID: String?
    public var pid: Int32?
    public var windowTitle: String?
    public var role: String?
    public var subrole: String?
    /// The element's text, cut to a few thousand characters.
    public var value: String?
    public var valueLength: Int?
    public var selectedTextSettable: Bool?
    public var valueSettable: Bool?
    /// Another app has turned on secure keyboard entry, usually a password field.
    public var secureInput: Bool
    public var keyboardLayout: String?
    public var error: String?
}

public enum FocusInspector {
    /// Whether this app has the Accessibility permission (shown as Device Control on macOS 27).
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the permission, and adds the app to its list.
    @discardableResult
    public static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        return copy(systemWide, kAXFocusedUIElementAttribute)
    }

    /// Asks Electron and Chromium apps to build their accessibility tree, which they skip unless
    /// an assistive app asks. Returns the result for the log.
    @discardableResult
    public static func enableAccessibilityTree(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        let manual = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return "AXManualAccessibility: \(manual.rawValue)"
    }

    /// Chrome builds its accessibility tree when an assistive app sets this. It also changes
    /// some window behavior (animations), so use it only when needed.
    @discardableResult
    public static func enableEnhancedUserInterface(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success
    }

    public static func inspect(maxValueLength: Int = 4000) -> FocusInfo {
        let front = NSWorkspace.shared.frontmostApplication
        var info = FocusInfo(
            appName: front?.localizedName, bundleID: front?.bundleIdentifier, pid: front?.processIdentifier,
            secureInput: IsSecureEventInputEnabled(), keyboardLayout: currentKeyboardLayout())

        if let pid = front?.processIdentifier {
            let app = AXUIElementCreateApplication(pid)
            if let window: AXUIElement = copy(app, kAXFocusedWindowAttribute) {
                info.windowTitle = copy(window, kAXTitleAttribute)
            }
        }
        guard let element = focusedElement() else {
            info.error = isTrusted ? "no focused element" : "not trusted for Accessibility"
            return info
        }
        info.role = copy(element, kAXRoleAttribute)
        info.subrole = copy(element, kAXSubroleAttribute)
        if let value: String = copy(element, kAXValueAttribute) {
            info.valueLength = value.count
            info.value = String(value.suffix(maxValueLength))
        }
        info.selectedTextSettable = isSettable(element, kAXSelectedTextAttribute)
        info.valueSettable = isSettable(element, kAXValueAttribute)
        return info
    }

    static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    static func currentKeyboardLayout() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
