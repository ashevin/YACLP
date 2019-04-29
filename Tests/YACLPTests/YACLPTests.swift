import XCTest
@testable import YACLP

struct Custom { let value: String }

class Parameters {
    var string: String?
    var int: Int?
    var double: Double?
    var bool: Bool?
    var date: Date?
    var array: [Int]?
    var toggle: Bool?
    var custom: Custom?
}

enum Commands: String {
    case greet
}

final class YACLPTests: XCTestCase {
    func test_types() {
        let args = [
            "-string=hello",
            "-int=1",
            "-double=1.3",
            "-bool=true",
            "-date=2017",
            "-array=3,4,5",
            "-toggle",
            "-custom=bye",
            ]

        do {
            let parameters = Parameters()

            let root = Command(bindTarget: parameters)
                .tagged("string", type: .string,                        binding: \Parameters.string)
                .tagged("int",    type: .int(1...10),                   binding: \Parameters.int)
                .tagged("double", type: .double,                        binding: \Parameters.double)
                .tagged("bool",   type: .bool,                          binding: \Parameters.bool)
                .tagged("date",   type: .date(format: "yyyy"),          binding: \Parameters.date)
                .tagged("array",  type: .array(.int(nil)),              binding: \Parameters.array)
                .tagged("toggle", type: .toggle,                        binding: \Parameters.toggle)
                .tagged("custom", type: .custom({ Custom(value: $0) }), binding: \Parameters.custom)

            _ = try parse(args, root: root)

            XCTAssertEqual(parameters.string, "hello")
            XCTAssertEqual(parameters.int, 1)
            XCTAssertEqual(parameters.double, 1.3)
            XCTAssertEqual(parameters.bool, true)
            XCTAssertEqual(parameters.date?.timeIntervalSince1970, 1483221600.0)
            XCTAssertEqual(parameters.array, [3, 4, 5])
            XCTAssertEqual(parameters.toggle, true)
            XCTAssertEqual(parameters.custom?.value, Custom(value: "bye").value)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }

    func test_value_separated_by_space() {
        let args = [
            "-string", "hello",
            ]

        do {
            let parameters = Parameters()

            let root = Command(bindTarget: parameters)
                .tagged("string", type: .string, binding: \Parameters.string)

            _ = try parse(args, root: root)

            XCTAssertEqual(parameters.string, "hello")
        }
        catch {
            XCTFail(String(describing: error))
        }
    }

    func test_int_range() {
        let args = [
            "-int", "11",
            ]

        do {
            let parameters = Parameters()

            let root = Command("yaclp", bindTarget: parameters)
                .tagged("int", type: .int(1...10), binding: \Parameters.int)

            _ = try parse(args, root: root)

            XCTFail("Expected exception not thrown")
        }
        catch {
            if case let YACLPError.invalidValue(p, v, c) = error {
                XCTAssertEqual(p.token, "int")
                XCTAssertEqual(v, "11")
                XCTAssertEqual(c[0].token, "yaclp")
            }
            else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_inverted_toggle() {
        let args = [
            "-notoggle",
            ]

        do {
            let parameters = Parameters()

            let root = Command("yaclp", bindTarget: parameters)
                .tagged("toggle", type: .toggle, binding: \Parameters.toggle)

            _ = try parse(args, root: root)

            XCTAssertEqual(parameters.toggle, false)
        }
        catch {
            XCTFail(String(describing: error))
        }
    }

    func test_command() {
        let args = [
            "greet",
            ]

        do {
            let parameters = Parameters()

            let root = Command("yaclp", bindTarget: parameters)
                .command(Commands.greet)

            let result = try parse(args, root: root)

            XCTAssertEqual(result.commands.count, 1)

            if let c = result.commands[0] as? Commands {
                XCTAssertEqual(c, .greet)
            }
            else {
                XCTFail("Unknown command type: \(type(of: result.commands[0]))")
            }
        }
        catch {
            XCTFail(String(describing: error))
        }
    }

    func test_required_parameter() {
        let args = [
            "greet",
            "you"
        ]

        do {
            class Parameters { var name: String? }

            let parameters = Parameters()

            let root = Command("yaclp", bindTarget: parameters)
                .command(Commands.greet) {
                    $0.required("name", binding: \Parameters.name)
            }

            _ = try parse(args, root: root)

            XCTAssertEqual(parameters.name, "you")
        }
        catch {
            XCTFail(String(describing: error))
        }
    }

    func test_optional_parameter() {
        let args = [
            "greet",
            "mister",
            "you"
        ]

        do {
            class Parameters {
                var name: String?
                var surname: String?
            }

            let parameters = Parameters()

            let root = Command("yaclp", bindTarget: parameters)
                .command(Commands.greet) {
                    $0.required("name", binding: \Parameters.name)
                    $0.optional("surname", binding: \Parameters.surname)
            }

            _ = try parse(args, root: root)

            XCTAssertEqual(parameters.surname, "you")
        }
        catch {
            XCTFail(String(describing: error))
        }
    }

    func test_missing_optional_parameter() {
        let args = [
            "greet",
            "mister",
        ]

        do {
            class Parameters {
                var name: String?
                var surname: String?
            }

            let parameters = Parameters()

            let root = Command("yaclp", bindTarget: parameters)
                .command(Commands.greet) {
                    $0.required("name", binding: \Parameters.name)
                    $0.optional("surname", binding: \Parameters.surname)
            }

            _ = try parse(args, root: root)

            XCTAssertEqual(parameters.surname, nil)
        }
        catch {
            XCTFail(String(describing: error))
        }
    }

    static var allTests = [
        ("test_types",                      test_types),
        ("test_value_separated_by_space",   test_value_separated_by_space),
        ("test_int_range",                  test_int_range),
        ("test_inverted_toggle",            test_inverted_toggle),
        ("test_command",                    test_command),
        ("test_required_parameter",         test_required_parameter),
        ("test_optional_parameter",         test_optional_parameter),
        ("test_missing_optional_parameter", test_missing_optional_parameter),
    ]
}
