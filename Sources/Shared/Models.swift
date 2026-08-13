import Foundation

enum KeyPhase: Sendable {
    case down
    case up
    case flagsChanged
}

enum KeyModifier: String, CaseIterable, Hashable, Sendable {
    case command
    case control
    case option
    case shift
    case function
}

struct KeyboardStroke: Equatable, Sendable {
    let keyCode: UInt16
    let phase: KeyPhase
    let modifiers: Set<KeyModifier>

    init(
        keyCode: UInt16,
        phase: KeyPhase = .down,
        modifiers: Set<KeyModifier> = []
    ) {
        self.keyCode = keyCode
        self.phase = phase
        self.modifiers = modifiers
    }
}

struct MappingContext: Equatable, Sendable {
    let bundleIdentifier: String?
    let isTextInput: Bool
    let isSecureInput: Bool

    init(
        bundleIdentifier: String? = nil,
        isTextInput: Bool = false,
        isSecureInput: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.isTextInput = isTextInput
        self.isSecureInput = isSecureInput
    }
}

enum WindowCommand: String, Equatable, Sendable {
    case leftHalf
    case rightHalf
    case fill
    case restore
    case restoreOrMinimize
    case minimizeAll
    case restoreMinimized
    case center
    case maximizeHeight
    case makeSmaller
    case makeLarger
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case nextDisplay
    case previousDisplay
}

enum WindowFillArea: String, CaseIterable, Equatable, Sendable {
    case keepDockVisible
    case coverDockArea
}

enum EngineAction: Equatable, Sendable {
    case passThrough
    case suppress
    case replace([KeyboardStroke])
    case openApplication(bundleIdentifier: String)
    case window(WindowCommand)
    case cycleInputSource
    case finderClipboard(FinderClipboardAction)
    case closeFrontWindow
    case captureWindow
}

enum FinderClipboardAction: Equatable, Sendable {
    case copy
    case cut
    case paste
}

struct RuleDecision: Equatable, Sendable {
    let ruleID: String
    let action: EngineAction
}

enum MacKeyCode {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let h: UInt16 = 4
    static let g: UInt16 = 5
    static let z: UInt16 = 6
    static let x: UInt16 = 7
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let b: UInt16 = 11
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let e: UInt16 = 14
    static let r: UInt16 = 15
    static let y: UInt16 = 16
    static let t: UInt16 = 17
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let six: UInt16 = 22
    static let five: UInt16 = 23
    static let equals: UInt16 = 24
    static let nine: UInt16 = 25
    static let seven: UInt16 = 26
    static let minus: UInt16 = 27
    static let eight: UInt16 = 28
    static let zero: UInt16 = 29
    static let rightBracket: UInt16 = 30
    static let o: UInt16 = 31
    static let u: UInt16 = 32
    static let leftBracket: UInt16 = 33
    static let i: UInt16 = 34
    static let p: UInt16 = 35
    static let l: UInt16 = 37
    static let j: UInt16 = 38
    static let quote: UInt16 = 39
    static let k: UInt16 = 40
    static let semicolon: UInt16 = 41
    static let backslash: UInt16 = 42
    static let comma: UInt16 = 43
    static let slash: UInt16 = 44
    static let n: UInt16 = 45
    static let m: UInt16 = 46
    static let period: UInt16 = 47
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let grave: UInt16 = 50
    static let delete: UInt16 = 51
    static let rightCommand: UInt16 = 54
    static let leftCommand: UInt16 = 55
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let insert: UInt16 = 114
    static let returnKey: UInt16 = 36
    static let escape: UInt16 = 53
    static let f1: UInt16 = 122
    static let f2: UInt16 = 120
    static let f3: UInt16 = 99
    static let f4: UInt16 = 118
    static let f5: UInt16 = 96
    static let f6: UInt16 = 97
    static let f7: UInt16 = 98
    static let f8: UInt16 = 100
    static let f9: UInt16 = 101
    static let f10: UInt16 = 109
    static let f11: UInt16 = 103
    static let f12: UInt16 = 111
    static let f13: UInt16 = 105
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let forwardDelete: UInt16 = 117
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
