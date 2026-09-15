//! Turns an introspection type into the `ModuleDef` the renderer prints.
//! A port of `Dagger.Codegen.IR` and `Dagger.Codegen.Analyzer`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const introspection = @import("introspection.zig");
const naming = @import("naming.zig");
const types = @import("types.zig");
const Type = types.Type;

pub const Kind = enum { object, interface, @"enum", input, scalar, unknown };

pub const IndexEntry = struct {
    kind: Kind,
    enum_values: []const introspection.EnumValue,
};

/// What the analyzer needs to know about the rest of the schema.
pub const Index = std.StringHashMapUnmanaged(IndexEntry);

pub const Arg = struct {
    name: []const u8,
    gql_name: []const u8,
    type: Type,
    doc: ?[]const u8,
    guard: types.Guard,
};

pub const EnumValue = struct {
    name: []const u8,
    value: []const u8,
    doc: ?[]const u8,
};

pub const Return = union(enum) {
    lazy: Type,
    leaf: Type,
    void,
    @"enum": Type,
    list_of_enum: Type,
    nodes: Type,
    node: []const u8,
};

pub const Function = struct {
    name: []const u8,
    gql_name: []const u8,
    doc: ?[]const u8,
    deprecated: ?[]const u8,
    self: []const u8,
    required_args: []const Arg,
    optional_args: []const Arg,
    @"return": Return,
};

pub const ModuleDef = struct {
    module: []const u8,
    variable: []const u8,
    gql_name: []const u8,
    kind: Kind,
    moduledoc: []const u8,
    derives: []const []const u8 = &.{},
    functions: []const Function = &.{},
    enum_values: []const EnumValue = &.{},
    fields: []const Arg = &.{},

    pub fn isNode(self: ModuleDef) bool {
        for (self.derives) |d| if (std.mem.eql(u8, d, "Dagger.ID")) return true;
        return false;
    }
};

pub fn kindOf(kind: []const u8) Kind {
    const eql = std.mem.eql;
    if (eql(u8, kind, "OBJECT")) return .object;
    if (eql(u8, kind, "INTERFACE")) return .interface;
    if (eql(u8, kind, "ENUM")) return .@"enum";
    if (eql(u8, kind, "INPUT_OBJECT")) return .input;
    if (eql(u8, kind, "SCALAR")) return .scalar;
    return .unknown;
}

pub fn analyze(a: Allocator, t: *const introspection.FullType, index: *const Index) !ModuleDef {
    const module = try naming.module(a, t.name);
    var def: ModuleDef = .{
        .module = module,
        .variable = try naming.variable(a, t.name),
        .gql_name = t.name,
        .kind = kindOf(t.kind),
        // ExDoc drops a module with no @moduledoc, so fall back to its own name.
        .moduledoc = if (t.description) |d| (if (d.len == 0) module else d) else module,
    };
    const fields = t.fields orelse &.{};
    switch (def.kind) {
        .object, .interface => {
            def.derives = try derives(a, fields);
            const functions = try a.alloc(Function, fields.len);
            for (fields, functions) |*field, *f| f.* = try function(a, field, t, index);
            def.functions = functions;
        },
        .@"enum" => {
            const values = t.enumValues orelse &.{};
            const out = try a.alloc(EnumValue, values.len);
            for (values, out) |v, *o| o.* = .{
                .name = try naming.function(a, v.name),
                .value = v.name,
                .doc = try doc(a, v.description, v.directives),
            };
            def.enum_values = out;
        },
        .input => {
            const inputs = t.inputFields orelse &.{};
            const out = try a.alloc(Arg, inputs.len);
            for (inputs, out) |*iv, *o| o.* = try arg(a, iv, index);
            def.fields = out;
        },
        .scalar => {},
        .unknown => return error.UnsupportedType,
    }
    return def;
}

fn derives(a: Allocator, fields: []const introspection.Field) ![]const []const u8 {
    const protocols = [_][2][]const u8{ .{ "id", "Dagger.ID" }, .{ "sync", "Dagger.Sync" } };
    var out: std.ArrayList([]const u8) = .empty;
    for (protocols) |p| {
        for (fields) |f| if (std.mem.eql(u8, f.name, p[0])) {
            try out.append(a, p[1]);
            break;
        };
    }
    return out.items;
}

fn function(a: Allocator, field: *const introspection.Field, t: *const introspection.FullType, index: *const Index) !Function {
    var required: std.ArrayList(Arg) = .empty;
    var optional: std.ArrayList(Arg) = .empty;
    for (field.args) |*iv| {
        const list = if (iv.isOptional()) &optional else &required;
        try list.append(a, try arg(a, iv, index));
    }
    return .{
        .name = try naming.function(a, field.name),
        .gql_name = field.name,
        .doc = try doc(a, field.description, field.directives),
        .deprecated = if (field.deprecationReason) |r| try naming.doc(a, r) else null,
        .self = try selfVar(a, t.name, required.items),
        .required_args = required.items,
        .optional_args = optional.items,
        .@"return" = try classify(a, field, t, index),
    };
}

// An argument may be named the same as the receiver; the receiver yields.
fn selfVar(a: Allocator, type_name: []const u8, required: []const Arg) ![]const u8 {
    const v = try naming.variable(a, type_name);
    for (required) |r| if (std.mem.eql(u8, r.name, v)) return std.mem.concat(a, u8, &.{ v, "_" });
    return v;
}

fn arg(a: Allocator, iv: *const introspection.InputValue, index: *const Index) !Arg {
    const expected = if (std.mem.eql(u8, iv.name, "id")) null else resolve(iv.directives, index);
    const t = try types.normalize(a, &iv.type, expected);
    return .{
        .name = try naming.variable(a, iv.name),
        .gql_name = iv.name,
        .type = t,
        .doc = try doc(a, iv.description, iv.directives),
        .guard = try guard(a, t, index),
    };
}

fn guard(a: Allocator, t: Type, index: *const Index) !types.Guard {
    const g = try types.guard(a, t);
    if (g != .@"enum") return g;
    const entry = index.get(t.@"enum") orelse return .{ .call = "is_atom" };
    if (entry.enum_values.len == 0) return .{ .call = "is_atom" };
    const values = try a.alloc([]const u8, entry.enum_values.len);
    for (entry.enum_values, values) |v, *o| o.* = try std.mem.concat(a, u8, &.{ ":", v.name });
    return .{ .in = values };
}

/// Resolve an `@expectedType` directive to the type it names. An unknown name
/// falls back to an interface, the safer of the two ways to be wrong.
fn resolve(directives: ?[]introspection.Directive, index: *const Index) ?Type {
    const name = introspection.expectedType(directives) orelse return null;
    const kind: Kind = if (index.get(name)) |e| e.kind else .interface;
    return switch (kind) {
        .object => .{ .object = name },
        .interface => .{ .interface = name },
        .@"enum" => .{ .@"enum" = name },
        .input => .{ .input = name },
        .scalar => .{ .scalar = name },
        .unknown => .{ .unknown = name },
    };
}

fn classify(a: Allocator, field: *const introspection.Field, t: *const introspection.FullType, index: *const Index) !Return {
    const returned = try types.normalize(a, &field.type, null);
    const elem = types.element(returned);
    if (types.isNode(elem)) return .{ .nodes = returned };
    if (types.isVoid(returned)) return .void;
    if (selfId(field, t, index)) return .{ .node = t.name };
    if (types.isEnum(elem)) return .{ .list_of_enum = returned };
    if (types.isEnum(returned)) return .{ .@"enum" = returned };
    if (types.isNode(returned)) return .{ .lazy = returned };
    return .{ .leaf = returned };
}

// `sync` and friends: a scalar whose `@expectedType` is the type it lives on.
fn selfId(field: *const introspection.Field, t: *const introspection.FullType, index: *const Index) bool {
    const expected = resolve(field.directives, index) orelse return false;
    const name = switch (expected) {
        inline .object, .interface, .@"enum", .input, .scalar, .unknown => |n| n,
        else => unreachable,
    };
    return !std.mem.eql(u8, field.name, "id") and std.mem.eql(u8, name, t.name);
}

fn doc(a: Allocator, description: ?[]const u8, directives: ?[]introspection.Directive) !?[]const u8 {
    const d = description orelse return null;
    if (d.len == 0) return null;
    var text = try naming.doc(a, d);
    for (directives orelse &.{}) |directive| {
        if (!std.mem.eql(u8, directive.name, "experimental")) continue;
        if (directive.args.len != 1 or !std.mem.eql(u8, directive.args[0].name, "reason")) continue;
        const reason = introspection.trimQuotes(directive.args[0].value orelse return error.UnsupportedType);
        text = try admonition(a, text, "Experimental", reason);
    }
    return text;
}

fn admonition(a: Allocator, text: []const u8, title: []const u8, body: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n\n> #### ");
    try out.appendSlice(a, title);
    try out.appendSlice(a, " {: .warning}\n>\n");
    var lines = std.mem.splitScalar(u8, body, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(a, '\n');
        first = false;
        try out.appendSlice(a, "> ");
        try out.appendSlice(a, line);
    }
    return out.items;
}
