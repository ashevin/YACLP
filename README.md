# YACLP (Yet Another Command-line Parser)

YACLP (pronounced yackle-P) is a framework for writing command-line specifications, and for parsing command-line arguments accordingly.

## Specification

Before diving into the API, we need to explain two concepts.

### Bindings

Bindings allow the results of parsing to be bound to properties of a class.  YACLP requires that all parameters be bound.  Each spec will have at least one bind target, and each parameter will have a binding to a property of its command's target. Sub-commands may inherit its parent's target.  (A bind target is unnecessary if no parameters are defined.)

#### Bind Target

The bind target must be a reference type (`class`), and each bindable property must be writeable (`var`).

##### Example

```swift
class Config {
    var input: String?
    var count: Int?
}
```

If the command-line arguments do not contain a value for a bound parameter, the bound property is not modified.  This allows the bind target to specify default values as part of its initialization.

```swift
class Config {
    var input: String = "input.txt"
    var count: Int = 1
}
```

#### Binding

A binding is a writeable `keyPath` to one of the properties in the bind target.  It is perfectly acceptable for mutually-exclusive parameters to share a binding.

### Command Tokens

While a command is specified as a string in the command-line arguments, that's not a type-safe way to identify the intended command.  To that end, YACLP requires command tokens (the strings matched in the arguments) to be specified as `RawRepresentable` enum cases, with a `RawValue` type of `String`.

##### Example

```swift
enum Commands: String {
    case file
    case misfile
}
```

### Anatomy of a Command-line

When a program is invoked, it may be passed a number of arguments.  YACLP organizes arguments into two general categories:

- commands
- parameters

Commands are strings that specify what action the user wants the program to take.  Not all programs will support multiple actions, and thus may not define any commands.

Parameters are themselves divided into 3 types:

- tagged
- required
- optional

Tagged parameters are written as `-option` or `--option`, and are typically followed by a value.

```bash
./silly-app -name fred   # -name is the tag, and fred is the value
./silly-app -name=fred   # the value may be separated by "=" instead of spaces
```

Required and optional parameters are individual arguments.

```bash
./silly-app hello fred   # "hello" and "fred" are parameters.
                         # from the invocation, one cannot tell if they are required or optional
```

#### Organization

The general form of a command-line is:

```
<command> [tagged parameters] <required parameters> [optional parameters]
```

- The program itself is considered a command, so the arguments may begin with parameters.
- If any tagged parameters are provided, they must precede required parameters.
- If there are required parameters, they must precede any optional parameters.
- If multiple optional parameters are provided, they must be provided in the order declared in the specification.

The sequence defined above may be repeated to represent sub-commands.

```bash
./silly-app file print --filename insults.txt
# "file" and "print" are commands
# --filename is a tagged parameter of the print sub-command
# "insults.txt" is the value for the --filename parameter
```

```bash
./silly-app file --filename insults.txt print --pretty
# "file" and "print" are commands
# --filename is a tagged parameter of the file command
# "insults.txt" is the value for the --filename parameter
# --pretty is a tagged parameter of the print command.  It has no value.
```

### Specifying the Spec

Before the specification can be made, we need to define our bind target(s) and our commands enum(s).


**Bind Target:**
```swift
class Parameters {
    var filename = "insults.txt"
    var name = "fred"
}
```

**Commands enum:**
```swift
enum Commands: String {
    case file
    case insult
}

enum FileCommands: String {
    case print
    case mangle
}
```

**Note:** it is recommended that each command's sub-commands be defined in a separate `enum`.  This allows exhaustive switching at each level of command handling.

A specification always begins with a root command that represents the program.

**API:**
```swift
public init(_ appName: String = CommandLine.arguments[0],  // the default value is the full path used to invoke the program
            description: String = "",                      // The description is printed in usage messages
            bindTarget: AnyObject? = nil)
```

**Example:**
```swift
// Parameter bindings will set properties of this instance.
let parameters = Parameters()

let root =
    AppCommand("silly-app",
               description: "A silly little program",
               bindTarget: parameters)
```

**Note:** the root should be an instance of `AppCommand`.

**AppCommand vs Command**
> The two types have an almost-identical API.  The difference between them lie in their constructors.  `AppCommand` takes a `String` for its first argument, which allows any arbitrary value to be passed.  `Command` requires an `enum` case, which allows for better type-safety when parsing the command-line.  The former is more lenient, as the token representing the root command is not used to determine user intent.

By convention, parameters will be defined next.

**API:**

```swift
@discardableResult
func required<R, V>
    (
     _ parameter: String,                      // This string is printed in usage messages
     type: ValueType = .string,                // The (data)type of the value
     binding: ReferenceWritableKeyPath<R, V>,  // The keyPath of the bind target's property
     description: String = ""                  // The description is printed in usage messages
    ) -> Self

@discardableResult
func optional<R, V>
    (
     _ parameter: String,
     type: ValueType = .string,
     binding: ReferenceWritableKeyPath<R, V>,
     description: String = ""
    ) -> Self

@discardableResult
func tagged<R, V>
    (
     _ parameter: String,                      // The tag to match in command-line arguments.  Also printed in usage messages
     type: ValueType = .string,
     binding: ReferenceWritableKeyPath<R, V>,
     description: String = ""
    ) -> Self
```

**Example:**
```swift
root
    .tagged("filename",
            binding: \Parameters.filename,
            description: "source file for insults")
```

As we can see above, the methods for defining parameters return the `Command` instance to which the parameters have been added.  This allows chaining, as we will see in the following examples.  This, however, poses a problem for commands, as we need a reference to the newly-defined command to add parameters and sub-commands.

Accordingly, commands are added as follows.

**API:**
```swift
func command<Token>
    (
     _ command: Token,                      // The enum case whose rawValue to match in command-line arguments.  Also printed in usage messages
     bindTarget: AnyObject? = nil,          // When nil, the target of the enclosing command is used
     description: String = "",              // The description is printed in usage messages
     configure: (Command) -> () = { _ in }  // This closure allows parameters and sub-commands to be added to the newly-defined command
    ) -> Self
```

**Example:**
```swift
root
    .command(Commands.file) {               // inherits bindTarget from root
        $0
            .command(FileCommands.print)    // inherits bindTarget from .file, which inherits from root
            .command(FileCommands.mangle)   // inherits bindTarget from .file, which inherits from root
    }
    .command(Commands.insult) {             // inherits bindTarget from root
        $0.required("name")
    }
```

### Let's Talk Types

One of the primary goals of YACLP is to provide type-safety for argument parsing.  To that end, the expected type of each parameter must be specified as part of its definition.

**Example:**
```swift
root.required("amount", type: .int(nil), binding: \Parameters.amount)
```

An exception is thrown if the string from the command-line arguments cannot be converted to the specified type.

The complete list of available types is defined as follows:

```swift
enum ValueType {
    case string
    case int(ClosedRange<Int>?)    // If non-nil, values outside the range are rejected
    case double
    case bool                      // accepted strings: true/false
    case date(format: String)      // Strings which can't be parsed with the provided format string are rejected
    case array(ValueType)          // All cases except .array are supported
    case toggle                    // Only applies to tagged parameters.
    case custom((String) -> Any?)  // The closure should return nil if the value is rejected
}
```

**Examples:**

```swift
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

let parameters = Parameters()

let root = AppCommand(bindTarget: parameters)
    .tagged("string", type: .string,                        binding: \Parameters.string)
    .tagged("int",    type: .int(1...10),                   binding: \Parameters.int)
    .tagged("double", type: .double,                        binding: \Parameters.double)
    .tagged("bool",   type: .bool,                          binding: \Parameters.bool)
    .tagged("date",   type: .date(format: "yyyy"),          binding: \Parameters.date)
    .tagged("array",  type: .array(.int(nil)),              binding: \Parameters.array)
    .tagged("toggle", type: .toggle,                        binding: \Parameters.toggle)
    .tagged("custom", type: .custom({ Custom(value: $0) }), binding: \Parameters.custom)
```

```bash
./silly-app -string moo -int 5 -double 3.14 -bool true -date 1945
# parameters.string = "moo"
# parameters.int = 5
# parameters.double = 3.14
# parameters.bool = true
# parameters.date = // date representing January 1, 1945

./silly-app -array 1,4,7 -custom cow
# parameters.array = [1, 4, 7]
# parameters.custom = // instance of Custom with a value of cow

./silly-app -toggle           # note: there's no value provided.  The presence of the tag sets the value
# parameters.toggle = true

./silly-app -notoggle         # prepending "no" to the tag negates toggle types
# parameters.toggle = false
```

**Note for the pedants:** I am aware that all the values of `parameter` are actually `Optional(...)`.

## Parsing

Parsing is as simple as calling `parse()`.

**API:**
```swift
struct ParseResults {
    public let commands: [Any]
    public let remainder: [String]
}

public func parse<C: Collection>(_ arguments: C,
                                 root: Command,
                                 optionNegation: String = "no")
    throws -> ParseResults where C.Element == String
```

`arguments` contains the program arguments.  This will usually be the command-line entered in the shell or invoked from a shell script, but the list can come from anywhere.  Tagged parameters of type `.toggle` can be negated by prepending the value of `optionNegation` to the parameter name  (e.g. `--nofriends`).

The return value is an instance of `ParseResults`.  The `commands` array contains the enums which represent the commands found on the command-line.

The `remainder` array contains the arguments which were not consumed while parsing.  Parsing can be terminated by including an argument of `--` (two dashes).  All arguments following the dashes are included in `remainder`.

**Example:**
```swift
let results = try! parse(CommandLine.arguments.dropFirst(), root: root)

switch results.commands[0] as! Commands {
case file:
    switch results.commands[1] as! FileCommands {
    case print: print()
    case mangle: mangle()
    }
case insult: insult()
}
```
The first element of `CommandLine.arguments` contains the path used to invoke the program.  It's not an argument to be parsed.

The contents of `results.commands` need to be cast.  It's safe to use `as!` because it's a programmer error if the value is not of the expected type.

```bash
./silly-app file mangle
# results.commands = [ .file, .mangle ]

./silly-app file mangle -- moo cow
# results.commands = [ .file, .mangle ]
# results.remainder = [ "moo", "cow" ]

./silly-app file mangle moo -- cow
# results.commands = [ .file, .mangle ]
# results.remainder = [ "moo", "cow" ] (mangle has no sub-commands or parameters, so "moo" was not parsed)
```

### Parsing Errors

The following exceptions may be thrown while parsing.

```swift
enum YACLPError: Error {
    /**
     Unrecognized tagged parameter found.

     **associated values:**
     - argument string
     - list of commands parsed
     */
    case unknownOption(String, [Command])

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
    case ambiguousOption(String, [Parameter], [Command])

    /**
     A value for a parameter was expected, but not found.

     **associated values:**
     - the parameter whose value is missing
     - list of commands parsed
     */
    case missingValue(Parameter, [Command])

    /**
     A value was successfully parsed, but is not valid.

     **associated values:**
     - the parameter whose value is invalid
     - argument string which failed validation
     - list of commands parsed

     This exception applies to invalid int ranges and unparsable dates.
     */
    case invalidValue(Parameter, String, [Command])

    /**
     A value could not be converted to the expected type.

     **associated values:**
     - the parameter whose value is invalid
     - argument string which failed conversion
     - list of commands parsed

     **Example:** "two" for an `.int` parameter
     */
    case invalidValueType(Parameter, String, [Command])

    /*
     A sub-command was expected, but none was found.

     **associated values:**
     - list of commands parsed
     */
    case missingSubcommand([Command])
}
```

## Function Builder Syntax

Thanks to the new function builder feature of Swift 5.1, there is an alternative syntax available for creating specifications.

**Examples:**

```swift
struct Custom { let value: String }

class Parameters {
    var string: String?
    var int: Int?
}

enum Commands {
    case file
}

let parameters = Parameters()

let root = AppCommand(bindTarget: parameters) {
    Tagged("int",    type: .int(1...10), binding: \Parameters.int)

    Command(Commands.file) {
        Tagged("string", type: .string, binding: \Parameters.string)
    }
}
```

Instead of chaining calls to the builder methods, we can simply create instances of the different parameter types and/or (sub)commands within the trailing closure of the constructor.
