//
//  YACLP.swift
//  YACLP
//
//  Created by Avi Shevin on 25/11/2018.
//

import Foundation

public enum YACLPError: Error {
    /**
     Unrecognized tagged parameter found.

     **associated values:**
     - argument string
     - list of commands parsed
     */
    case unknownOption(String, [_Command])

    /**
     Ambiguous tagged parameter found.

     **associated values:**
     - argument string
     - list of matching parameters
     - list of commands parsed

     Tagged parameters allow prefix matching (e.g. `--file` will match a tag
     of `filename`), but the prefix must be unambiguous across all tagged
     parameters of the current command.
     */
    case ambiguousOption(String, [Parameter], [_Command])

    /**
     A value for a parameter was expected, but not found.

     **associated values:**
     - the parameter whose value is missing
     - list of commands parsed
     */
    case missingValue(Parameter, [_Command])

    /**
     A value was successfully parsed, but is not valid.

     **associated values:**
     - the parameter whose value is invalid
     - argument string which failed validation
     - list of commands parsed

     This exception applies to invalid int ranges and unparsable dates.
     */
    case invalidValue(Parameter, String, [_Command])

    /**
     A value could not be converted to the expected type.

     **associated values:**
     - the parameter whose value is invalid
     - argument string which failed conversion
     - list of commands parsed

     **Example:** "two" for an `.int` parameter
     */
    case invalidValueType(Parameter, String, [_Command])

    /*
     A sub-command was expected, but none was found.

     **associated values:**
     - list of commands parsed
     */
    case missingSubcommand([_Command])
}
private typealias E = YACLPError

public indirect enum ValueType {
    case string
    case int(ClosedRange<Int>?)    // If non-nil, values outside the range are rejected
    case double
    case bool                      // accepted strings: true/false
    case date(format: String)      // Strings which can't be parsed with the provided format string are rejected
    case array(ValueType)          // All cases except .array are supported
    case toggle                    // Only applies to tagged parameters.
    case custom((String) -> Any?)  // The closure should return nil if the value is rejected
}

private extension ValueType {
    var isToggle: Bool {
        switch self {
        case .toggle: return true
        default: return false
        }
    }
}

public protocol Component {}
extension Command: Component {}
extension Parameter: Component {}

@_functionBuilder
public class _Command {
    fileprivate typealias AddClosure = (inout [Any], String) -> ()

    public let token: String

    fileprivate let description: String
    fileprivate var bindTarget: AnyObject?
    fileprivate var subcommands = [Command]()
    fileprivate var arguments = [Parameter]()
    fileprivate var optionals = [Parameter]()
    fileprivate var options = [Parameter]()

    fileprivate let addToPath: AddClosure?

    fileprivate init(token: String,
                     addToPath: @escaping AddClosure,
                     description: String = "",
                     bindTarget: AnyObject? = nil,
                     components: [Component]) {
        self.token = token
        self.description = description
        self.bindTarget = bindTarget
        self.addToPath = addToPath

        assignComponents(components)
    }

    fileprivate func assignComponents(_ components: [Component]) {
        subcommands = components.compactMap({ $0 as? Command })
        arguments = components.compactMap({ $0 as? Required })
        optionals = components.compactMap({ $0 as? Optional })
        options = components.compactMap({ $0 as? Tagged })

        subcommands.forEach({ $0.bindTarget = $0.bindTarget ?? bindTarget })

        precondition((arguments.isEmpty && optionals.isEmpty) || subcommands.isEmpty,
                     "A node must define either untagged parameters or commands, but not both")
    }

    static func buildBlock(_ parameters: Component...) -> [Component] {
        parameters
    }
}

public extension _Command {
    @discardableResult
    func command<Token>(_ command: Token,
                        bindTarget: AnyObject? = nil,
                        description: String = "",
                        configure: (Command) -> () = { _ in }) -> Self
        where Token: RawRepresentable, Token.RawValue == String
    {
        precondition(arguments.isEmpty && optionals.isEmpty,
                     "A node must define either untagged parameters or commands, but not both")

        let node = Command(token: command.rawValue,
                           addToPath: { $0.append(Token.init(rawValue: $1)!) },
                           description: description,
                           bindTarget: bindTarget ?? self.bindTarget,
                           components: [])

        configure(node)
        subcommands.append(node)

        return self
    }

    @discardableResult
    func required<R, V>(_ parameter: String,
                        type: ValueType = .string,
                        binding: ReferenceWritableKeyPath<R, V>,
                        description: String = "") -> Self
    {
        precondition(subcommands.isEmpty,
                     "A node must define either untagged parameters or commands, but not both")
        precondition(!type.isToggle, "untagged parameters cannot be toggled")

        arguments.append(Required(parameter,
                                  type: type,
                                  binding: binding,
                                  description: description))

        return self
    }

    @discardableResult
    func optional<R, V>(_ parameter: String,
                        type: ValueType = .string,
                        binding: ReferenceWritableKeyPath<R, V>,
                        description: String = "") -> Self
    {
        precondition(subcommands.isEmpty,
                     "A node must define either untagged parameters or commands, but not both")
        precondition(!type.isToggle, "untagged parameters cannot be toggled")

        optionals.append(Optional(parameter,
                                  type: type,
                                  binding: binding,
                                  description: description))

        return self
    }

    @discardableResult
    func tagged<R, V>(_ parameter: String,
                      type: ValueType = .string,
                      binding: ReferenceWritableKeyPath<R, V>,
                      description: String = "") -> Self
    {
        options.append(Tagged(parameter,
                              type: type,
                              binding: binding,
                              description: description))

        return self
    }
}

public final class AppCommand: _Command {}

public extension AppCommand {
    convenience init(_ appName: String = CommandLine.arguments[0],
                     description: String = "",
                     bindTarget: AnyObject? = nil,
                     @_Command components: () -> [Component] = { [] }) {
        self.init(token: appName,
                  addToPath: { _, _ in },
                  description: description,
                  bindTarget: bindTarget,
                  components: components())
    }

    convenience init(_ appName: String = CommandLine.arguments[0],
                     description: String = "",
                     bindTarget: AnyObject? = nil,
                     @_Command _ component: () -> Component)
    {
        self.init(token: appName,
                  addToPath: { _, _ in },
                  description: description,
                  bindTarget: bindTarget,
                  components: [component()])
    }
}

public final class Command: _Command {}

public extension Command {
    convenience init<Token>(_ command: Token,
                            bindTarget: AnyObject? = nil,
                            description: String = "",
                            @_Command components: () -> [Component] = { [] })
        where Token: RawRepresentable, Token.RawValue == String
    {
        self.init(token: command.rawValue,
                  addToPath: { $0.append(Token.init(rawValue: $1)!) },
                  description: description,
                  bindTarget: bindTarget,
                  components: components())

        assignComponents(components())
    }

    convenience init<Token>(_ command: Token,
                            bindTarget: AnyObject? = nil,
                            description: String = "",
                            @_Command component: () -> Component)
        where Token: RawRepresentable, Token.RawValue == String
    {
        self.init(token: command.rawValue,
                  addToPath: { $0.append(Token.init(rawValue: $1)!) },
                  description: description,
                  bindTarget: bindTarget,
                  components: [component()])
    }
}

public class Parameter {
    public let token: String

    fileprivate let description: String
    fileprivate let type: ValueType
    fileprivate let binding: ((AnyObject, Any) -> ())?

    fileprivate var usageToken: String { fatalError("override me") }

    public init<R, V>(_ token: String,
                      type: ValueType = .string,
                      binding: ReferenceWritableKeyPath<R, V>,
                      description: String = "")
    {
        self.token = token
        self.description = description
        self.type = type
        self.binding = { ($0 as! R)[keyPath: binding] = $1 as! V }
    }
}

public final class Required: Parameter {
    override fileprivate var usageToken: String { return "<\(token)>" }

    public override init<R, V>(_ parameter: String,
                               type: ValueType = .string,
                               binding: ReferenceWritableKeyPath<R, V>,
                               description: String = "")
    {
        precondition(!type.isToggle, "untagged parameters cannot be toggled")

        super.init(parameter,
                   type: type,
                   binding: binding,
                   description: description)
    }
}

public final class Tagged: Parameter {
    override fileprivate var usageToken: String { return "-\(token)" }
}

public final class Optional: Parameter {
    override fileprivate var usageToken: String { return "[\(token)]" }

    public override init<R, V>(_ parameter: String,
                               type: ValueType = .string,
                               binding: ReferenceWritableKeyPath<R, V>,
                               description: String = "")
    {
        precondition(!type.isToggle, "untagged parameters cannot be toggled")

        super.init(parameter,
                   type: type,
                   binding: binding,
                   description: description)
    }
}

public struct ParseResults {
    public let commands: [Any]
    public let remainder: [String]
}

private let dateFormatter = DateFormatter()

private func prepare<C: Collection>(_ args: C) -> ([String], C.SubSequence)
    where C.Element == String
{
    let remainderIndex = args.firstIndex(of: "--") ?? args.endIndex
    let remainder = args[remainderIndex ..< args.endIndex].dropFirst()

    return (args[args.startIndex ..< remainderIndex]
        .map { $0.starts(with: "--") ? String($0.dropFirst()) : $0 }
        .map { a -> [String] in
            if
                a.starts(with: "-"),
                let eqIndex = a.firstIndex(of: "="),
                eqIndex < a.index(before: a.endIndex)
            {
                return a.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .map(String.init)
            }

            return [a]
        }.flatMap { $0 }.reversed(), remainder)
}

public func parse<C: Collection>(_ arguments: C,
                                 root: _Command,
                                 optionNegation: String = "no")
    throws -> ParseResults where C.Element == String
{
    var commandPath = [root]
    var commands = [Any]()

    var (arguments, remainder) = prepare(arguments)

    func value(arg: String, for opt: Parameter) throws -> Any? {
        func checkedValue(_ arg: String, for opt: Parameter, as type: ValueType) throws -> Any {
            let invalidValue = E.invalidValue(opt, arg, commandPath)
            let invalidValueType = E.invalidValueType(opt, arg, commandPath)

            switch type {
            case .string:
                return arg

            case .int(let range):
                guard let i = Int(arg) else { throw invalidValueType }

                guard range == nil || range!.contains(i) else { throw invalidValue }

                return i

            case .double:
                guard let d = Double(arg) else { throw invalidValueType }

                return d

            case .bool:
                guard let b = Bool(arg) else { throw invalidValueType }

                return b

            case .date(let format):
                dateFormatter.dateFormat = format
                guard let d = dateFormatter.date(from: arg) else { throw invalidValue }

                return d

            case .custom(let transform):
                guard let v = transform(arg) else { throw invalidValueType }

                return v

            default:
                fatalError("unhandled type")
            }
        }

        switch opt.type {
        case .array(let type):
            let args = arg.split(separator: ",")

            return try args.map {
                try checkedValue(String($0), for: opt, as: type)
            }
        case .toggle:
            return nil
        default:
            return try checkedValue(arg, for: opt, as: opt.type)
        }
    }

    func optionMatch(_ arg: String, options: [Parameter]) throws -> Parameter? {
        guard arg.starts(with: "-") else { return nil }

        var matches = [Parameter]()

        let arg = arg.dropFirst()

        // Exact match
        matches = options.filter { $0.token == arg }

        // Prefix match
        if matches.isEmpty {
            matches = options.filter { $0.token.starts(with: arg) }
        }

        // notoggle match
        if matches.isEmpty {
            matches = options.filter {
                if $0.type.isToggle {
                    return (optionNegation + $0.token).starts(with: arg)
                }

                return false
            }
        }

        if matches.count == 0 { throw E.unknownOption("-" + arg, commandPath) }
        else if matches.count > 1 { throw E.ambiguousOption("-" + arg, matches, commandPath) }

        return matches.first
    }

    func _parse(node: _Command) throws {
        var done = false

        while !arguments.isEmpty && !done {
            let arg = arguments.peek()

            if let match = try optionMatch(arg, options: node.options) {
                arguments.pop()

                if match.type.isToggle {
                    let v = !arg.starts(with: "-" + optionNegation)

                    match.binding?(node.bindTarget!, v)
                }
                else {
                    guard !arguments.isEmpty else { throw E.missingValue(match, commandPath) }

                    if let v = try value(arg: arguments.pop(), for: match) {
                        match.binding?(node.bindTarget!, v)
                    }
                }
            }
            else {
                for node in node.subcommands where node.token == arg {
                    arguments.pop()

                    commandPath.append(node)
                    node.addToPath!(&commands, node.token)

                    try _parse(node: node)
                }

                done = true
            }
        }

        for arg in node.arguments + node.optionals {
            if arguments.isEmpty {
                guard arg is Optional else {
                    throw E.missingValue(arg, commandPath)
                }

                break
            }

            if let v = try value(arg: arguments.pop(), for: arg) {
                arg.binding?(node.bindTarget!, v)
            }
        }

        if !node.subcommands.isEmpty && !done {
            throw E.missingSubcommand(commandPath)
        }
    }

    try _parse(node: root)

    return ParseResults(commands: commands,
                        remainder: arguments + remainder)
}

private extension Array where Element == String {
    func peek() -> Element { return self[endIndex - 1] }

    @discardableResult
    mutating func pop() -> Element { return popLast()! }
}

public func usage(_ node: Command) -> String {
    return usage([node])
}

public func usage(_ path: [Command]) -> String {
    let node = path[path.index(before: path.endIndex)]

    let pathUsage = path.map { $0.token }.joined(separator: " ")

    var usage = "USAGE: \(pathUsage)"

    var optionlist = ""
    var commandlist = ""
    var paramsList = ""

    let options = node.options
    let commands = node.subcommands
    let parameters = node.arguments + node.optionals

    if !options.isEmpty {
        usage += " [options]"

        optionlist = "\n\nOPTIONS:"

        let width = options.map { $0.token.count }.reduce(0, max)

        options.forEach {
            optionlist += "\n  \($0.usageToken)" +
                String(repeating: " ", count: width - $0.token.count) + " : \($0.description)"
        }
    }

    if !commands.isEmpty {
        usage += " <command>"

        commandlist = "\n\nSUBCOMMANDS:"

        let width = commands.map { $0.token.count }.reduce(0, max)

        commands.forEach {
            commandlist += "\n  \($0.token)" +
                String(repeating: " ", count: width - $0.token.count) + " : \($0.description)"
        }
    }

    if !parameters.isEmpty {
        usage += " " + parameters.map({ $0.usageToken }).joined(separator: " ")

        paramsList = "\n\nPARAMETERS: <required> [optional]"

        let width = parameters.map { $0.token.count }.reduce(0, max)

        parameters.forEach {
            paramsList += "\n  \($0.usageToken)" +
                String(repeating: " ", count: width - $0.token.count) + " : \($0.description)"
        }
    }

    return usage + optionlist + paramsList + commandlist
}
