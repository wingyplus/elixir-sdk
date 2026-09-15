//! A GraphQL introspection schema, reduced to what the generator reads.
//!
//! Field names mirror the JSON keys; `parser.zig` reads straight into these
//! structs. Strings borrow from the input buffer where possible.

pub const TypeRef = struct {
    kind: []const u8,
    name: ?[]const u8 = null,
    ofType: ?*TypeRef = null,
};

pub const DirectiveArg = struct {
    name: []const u8,
    value: ?[]const u8 = null,
};

pub const Directive = struct {
    name: []const u8,
    args: []DirectiveArg = &.{},
};

pub const InputValue = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    type: TypeRef,
    directives: ?[]Directive = null,

    /// GraphQL marks a value as omittable by not wrapping it in `NON_NULL`.
    pub fn isOptional(self: InputValue) bool {
        return !eql(self.type.kind, "NON_NULL");
    }
};

pub const Field = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    deprecationReason: ?[]const u8 = null,
    args: []InputValue = &.{},
    type: TypeRef,
    directives: ?[]Directive = null,
};

pub const EnumValue = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    directives: ?[]Directive = null,
};

pub const FullType = struct {
    kind: []const u8,
    name: []const u8,
    description: ?[]const u8 = null,
    fields: ?[]Field = null,
    inputFields: ?[]InputValue = null,
    enumValues: ?[]EnumValue = null,
};

pub const Schema = struct {
    types: []FullType,
};

/// The name an `@expectedType` directive points at, with its GraphQL quotes
/// stripped, or null when no such directive is present.
pub fn expectedType(directives: ?[]Directive) ?[]const u8 {
    for (directives orelse return null) |directive| {
        if (!eql(directive.name, "expectedType")) continue;
        for (directive.args) |arg| {
            if (eql(arg.name, "name")) {
                if (arg.value) |value| return trimQuotes(value);
            }
        }
    }
    return null;
}

/// Directive argument values arrive as GraphQL literals, quotes included.
/// Mirrors `String.trim_leading("\"") |> String.trim_trailing("\"")`.
pub fn trimQuotes(value: []const u8) []const u8 {
    var start: usize = 0;
    while (start < value.len and value[start] == '"') start += 1;
    var end: usize = value.len;
    while (end > start and value[end - 1] == '"') end -= 1;
    return value[start..end];
}

fn eql(a: []const u8, b: []const u8) bool {
    return @import("std").mem.eql(u8, a, b);
}
