import Foundation

/// Domain-separated signatures use sorted-key JSON and integer epoch seconds.
public struct SignedValue<Value: Codable & Sendable>: Codable, Sendable {
    public var value: Value
    public var signature: String
    public init(value: Value, signature: String) { self.value = value; self.signature = signature }
}

extension SignedValue: Equatable where Value: Equatable {}
