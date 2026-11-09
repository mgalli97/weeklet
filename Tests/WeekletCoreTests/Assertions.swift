import Testing

// Small assertion helpers retain call-site locations and work with the Swift Testing
// framework bundled with Apple's command-line tools; XCTest is not required.
func checkEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () throws -> T,
                             sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        let left = try actual()
        let right = try expected()
        #expect(left == right, sourceLocation: sourceLocation)
    } catch { Issue.record("Unexpected thrown error", sourceLocation: sourceLocation) }
}

func checkThrowsError<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation,
                        _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); Issue.record("Expected a thrown error", sourceLocation: sourceLocation) }
    catch { handler(error) }
}

func checkNil<T>(_ expression: @autoclosure () throws -> T?, sourceLocation: SourceLocation = #_sourceLocation) {
    do { let value = try expression(); #expect(value == nil, sourceLocation: sourceLocation) }
    catch { Issue.record("Unexpected thrown error", sourceLocation: sourceLocation) }
}

func checkNotNil<T>(_ expression: @autoclosure () throws -> T?, sourceLocation: SourceLocation = #_sourceLocation) {
    do { let value = try expression(); #expect(value != nil, sourceLocation: sourceLocation) }
    catch { Issue.record("Unexpected thrown error", sourceLocation: sourceLocation) }
}

func checkFalse(_ expression: @autoclosure () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!expression(), sourceLocation: sourceLocation)
}

func checkGreaterThanOrEqual<T: Comparable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual >= expected, sourceLocation: sourceLocation)
}

func recordFailure(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
