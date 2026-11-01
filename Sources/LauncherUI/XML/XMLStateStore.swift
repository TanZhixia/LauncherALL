import SwiftUI
import Observation

/// XML 页面运行时状态：`<state>` 里声明的变量都存在这里，输入控件通过 Binding 双向读写。
@Observable
public final class XMLStateStore {
    private var values: [String: XMLValue]

    public init(values: [String: XMLValue] = [:]) {
        self.values = values
    }

    // MARK: 读写

    public func value(_ name: String) -> XMLValue? { values[name] }

    public func set(_ name: String, _ value: XMLValue) {
        values[name] = value
    }

    public func string(_ name: String, default fallback: String = "") -> String {
        values[name]?.stringValue ?? fallback
    }

    public func bool(_ name: String, default fallback: Bool = false) -> Bool {
        values[name]?.boolValue ?? fallback
    }

    public func double(_ name: String, default fallback: Double = 0) -> Double {
        values[name]?.doubleValue ?? fallback
    }

    public func int(_ name: String, default fallback: Int = 0) -> Int {
        values[name]?.intValue ?? fallback
    }

    public func contains(_ name: String) -> Bool { values[name] != nil }

    public var allValues: [String: XMLValue] { values }

    // MARK: 双向绑定（控件用）

    public func bindingString(_ name: String) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.string(name) ?? "" },
            set: { [weak self] newValue in self?.set(name, .string(newValue)) }
        )
    }

    public func bindingBool(_ name: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.bool(name) ?? false },
            set: { [weak self] newValue in self?.set(name, .bool(newValue)) }
        )
    }

    public func bindingDouble(_ name: String) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.double(name) ?? 0 },
            set: { [weak self] newValue in self?.set(name, .double(newValue)) }
        )
    }

    public func bindingInt(_ name: String) -> Binding<Int> {
        Binding(
            get: { [weak self] in self?.int(name) ?? 0 },
            set: { [weak self] newValue in self?.set(name, .int(newValue)) }
        )
    }
}
