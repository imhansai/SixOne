//
//  KeyNameResolver.swift
//  SixOne
//
//  按当前键盘布局（而非输入法）把物理 keyCode 翻成显示字符，并缓存。
//

import AppKit
import Carbon.HIToolbox

final class KeyNameResolver {
    static let shared = KeyNameResolver()

    private struct CacheKey: Hashable {
        let inputSourceID: String
        let keyCode: UInt32
    }

    private var cache: [CacheKey: String] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache.removeAll()
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 特殊键（方向、功能键、编辑键、小键盘）用固定名字；其余按布局翻译。
    func name(for keyCode: UInt32) -> String {
        if Self.fixedKeyCodes.contains(keyCode), let fixed = Self.fallbackNames[keyCode] {
            return fixed
        }
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let sourceID = source.map(Self.inputSourceID) ?? ""
        let cacheKey = CacheKey(inputSourceID: sourceID, keyCode: keyCode)
        if let cached = cache[cacheKey] {
            return cached
        }
        let name = source
            .flatMap { Self.translatedCharacter(for: keyCode, source: $0) }
            .flatMap(Self.displayCharacter)
            ?? Self.fallbackNames[keyCode]
            ?? "Key"
        cache[cacheKey] = name
        return name
    }

    /// 菜单 key equivalent：字母转小写，特殊键映射到功能键字符；无法表达的返回 nil。
    func keyEquivalent(for keyCode: UInt32) -> String? {
        if let special = Self.specialKeyEquivalents[keyCode] {
            return special
        }
        if Self.keypadKeyCodes.contains(keyCode) {
            return nil
        }
        let name = name(for: keyCode)
        guard name.count == 1,
              let scalar = name.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            return nil
        }
        return name.lowercased()
    }

    // MARK: - 布局翻译

    private static func inputSourceID(_ source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func translatedCharacter(
        for keyCode: UInt32,
        source: TISInputSource
    ) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    private static func displayCharacter(_ raw: String) -> String? {
        guard raw.count == 1,
              let scalar = raw.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            return nil
        }
        return raw.uppercased()
    }

    // MARK: - 固定键名

    /// 这些键不按布局翻译：方向/功能/编辑键没有可读字符，小键盘保持固定写法。
    private static let fixedKeyCodes: Set<UInt32> = [
        UInt32(kVK_Space), UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter),
        UInt32(kVK_Tab), UInt32(kVK_Escape), UInt32(kVK_Delete),
        UInt32(kVK_ForwardDelete), UInt32(kVK_Help),
        UInt32(kVK_UpArrow), UInt32(kVK_DownArrow), UInt32(kVK_LeftArrow), UInt32(kVK_RightArrow),
        UInt32(kVK_Home), UInt32(kVK_End), UInt32(kVK_PageUp), UInt32(kVK_PageDown),
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
        UInt32(kVK_ANSI_Keypad0), UInt32(kVK_ANSI_Keypad1), UInt32(kVK_ANSI_Keypad2),
        UInt32(kVK_ANSI_Keypad3), UInt32(kVK_ANSI_Keypad4), UInt32(kVK_ANSI_Keypad5),
        UInt32(kVK_ANSI_Keypad6), UInt32(kVK_ANSI_Keypad7), UInt32(kVK_ANSI_Keypad8),
        UInt32(kVK_ANSI_Keypad9), UInt32(kVK_ANSI_KeypadDecimal), UInt32(kVK_ANSI_KeypadPlus),
        UInt32(kVK_ANSI_KeypadMinus), UInt32(kVK_ANSI_KeypadMultiply),
        UInt32(kVK_ANSI_KeypadDivide), UInt32(kVK_ANSI_KeypadEquals),
        UInt32(kVK_ANSI_KeypadClear),
    ]

    private static let specialKeyEquivalents: [UInt32: String] = {
        var map: [UInt32: String] = [
            UInt32(kVK_Space): " ",
            UInt32(kVK_Return): "\r",
            UInt32(kVK_ANSI_KeypadEnter): "\r",
            UInt32(kVK_Tab): "\t",
            UInt32(kVK_Escape): "\u{1b}",
            UInt32(kVK_Delete): "\u{8}",
            UInt32(kVK_ForwardDelete): "\u{7f}",
            UInt32(kVK_Help): String(UnicodeScalar(NSHelpFunctionKey)!),
        ]

        let navigation: [(Int, Int)] = [
            (kVK_UpArrow, NSUpArrowFunctionKey),
            (kVK_DownArrow, NSDownArrowFunctionKey),
            (kVK_LeftArrow, NSLeftArrowFunctionKey),
            (kVK_RightArrow, NSRightArrowFunctionKey),
            (kVK_Home, NSHomeFunctionKey),
            (kVK_End, NSEndFunctionKey),
            (kVK_PageUp, NSPageUpFunctionKey),
            (kVK_PageDown, NSPageDownFunctionKey),
        ]
        for (keyCode, functionKey) in navigation {
            map[UInt32(keyCode)] = String(UnicodeScalar(functionKey)!)
        }

        let functionKeys: [(Int, Int)] = [
            (kVK_F1, NSF1FunctionKey), (kVK_F2, NSF2FunctionKey),
            (kVK_F3, NSF3FunctionKey), (kVK_F4, NSF4FunctionKey),
            (kVK_F5, NSF5FunctionKey), (kVK_F6, NSF6FunctionKey),
            (kVK_F7, NSF7FunctionKey), (kVK_F8, NSF8FunctionKey),
            (kVK_F9, NSF9FunctionKey), (kVK_F10, NSF10FunctionKey),
            (kVK_F11, NSF11FunctionKey), (kVK_F12, NSF12FunctionKey),
            (kVK_F13, NSF13FunctionKey), (kVK_F14, NSF14FunctionKey),
            (kVK_F15, NSF15FunctionKey), (kVK_F16, NSF16FunctionKey),
            (kVK_F17, NSF17FunctionKey), (kVK_F18, NSF18FunctionKey),
            (kVK_F19, NSF19FunctionKey), (kVK_F20, NSF20FunctionKey),
        ]
        for (keyCode, functionKey) in functionKeys {
            map[UInt32(keyCode)] = String(UnicodeScalar(functionKey)!)
        }
        return map
    }()

    /// 小键盘键位：key equivalent 只有字符、分不出主键盘与小键盘，宁可不显示。
    private static let keypadKeyCodes: Set<UInt32> = [
        UInt32(kVK_ANSI_Keypad0), UInt32(kVK_ANSI_Keypad1), UInt32(kVK_ANSI_Keypad2),
        UInt32(kVK_ANSI_Keypad3), UInt32(kVK_ANSI_Keypad4), UInt32(kVK_ANSI_Keypad5),
        UInt32(kVK_ANSI_Keypad6), UInt32(kVK_ANSI_Keypad7), UInt32(kVK_ANSI_Keypad8),
        UInt32(kVK_ANSI_Keypad9), UInt32(kVK_ANSI_KeypadDecimal), UInt32(kVK_ANSI_KeypadPlus),
        UInt32(kVK_ANSI_KeypadMinus), UInt32(kVK_ANSI_KeypadMultiply),
        UInt32(kVK_ANSI_KeypadDivide), UInt32(kVK_ANSI_KeypadEquals),
        UInt32(kVK_ANSI_KeypadClear),
    ]

    private static let fallbackNames: [UInt32: String] = {
        let entries: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"), (kVK_ANSI_0, "0"), (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="),
            (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"),
            (kVK_F5, "F5"), (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"),
            (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"), (kVK_F16, "F16"),
            (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
            (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_ANSI_KeypadEnter, "⌤"),
            (kVK_Tab, "Tab"), (kVK_Escape, "Esc"), (kVK_Delete, "⌫"),
            (kVK_ForwardDelete, "⌦"), (kVK_Help, "?⃝"),
            (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"), (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"),
            (kVK_Home, "↖"), (kVK_End, "↘"), (kVK_PageUp, "⇞"), (kVK_PageDown, "⇟"),
            (kVK_ANSI_Keypad0, "0"), (kVK_ANSI_Keypad1, "1"), (kVK_ANSI_Keypad2, "2"),
            (kVK_ANSI_Keypad3, "3"), (kVK_ANSI_Keypad4, "4"), (kVK_ANSI_Keypad5, "5"),
            (kVK_ANSI_Keypad6, "6"), (kVK_ANSI_Keypad7, "7"), (kVK_ANSI_Keypad8, "8"),
            (kVK_ANSI_Keypad9, "9"), (kVK_ANSI_KeypadDecimal, "."), (kVK_ANSI_KeypadPlus, "+"),
            (kVK_ANSI_KeypadMinus, "-"), (kVK_ANSI_KeypadMultiply, "*"),
            (kVK_ANSI_KeypadDivide, "/"), (kVK_ANSI_KeypadEquals, "="),
            (kVK_ANSI_KeypadClear, "⌧"),
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { (UInt32($0.0), $0.1) })
    }()
}
