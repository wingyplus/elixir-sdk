//! Canonical view of a GraphQL type reference, a port of `Dagger.Codegen.Type`.
//!
//! The `NON_NULL`/`LIST` wire chain is peeled once by `normalize`, so every
//! consumer downstream is a flat switch instead of another walk.

const std = @import("std");
const Allocator = std.mem.Allocator;
const introspection = @import("introspection.zig");
const naming = @import("naming.zig");

pub const Type = union(enum) {
    string,
    int,
    float,
    boolean,
    datetime,
    id,
    void,
    scalar: []const u8,
    object: []const u8,
    interface: []const u8,
    @"enum": []const u8,
    input: []const u8,
    /// A kind the generator has no mapping for, e.g. a union. The Elixir
    /// generator crashes when it has to print one; so does `spec` here.
    unknown: []const u8,
    list: *const Type,
    nullable: *const Type,

    fn namedName(t: Type) ?[]const u8 {
        return switch (t) {
            .scalar, .object, .interface, .@"enum", .input => |name| name,
            else => null,
        };
    }
};

pub fn normalize(a: Allocator, ref: *const introspection.TypeRef, expected: ?Type) error{ OutOfMemory, UnsupportedType }!Type {
    if (std.mem.eql(u8, ref.kind, "NON_NULL")) return unwrapped(a, ref.ofType.?, expected);
    return .{ .nullable = try box(a, try unwrapped(a, ref, expected)) };
}

fn unwrapped(a: Allocator, ref: *const introspection.TypeRef, expected: ?Type) !Type {
    const kind = ref.kind;
    if (std.mem.eql(u8, kind, "LIST")) return .{ .list = try box(a, try normalize(a, ref.ofType.?, expected)) };
    const name = ref.name orelse return error.UnsupportedType;
    if (std.mem.eql(u8, kind, "SCALAR")) return scalar(name, expected);
    if (std.mem.eql(u8, kind, "OBJECT")) return .{ .object = name };
    if (std.mem.eql(u8, kind, "INTERFACE")) return .{ .interface = name };
    if (std.mem.eql(u8, kind, "ENUM")) return .{ .@"enum" = name };
    if (std.mem.eql(u8, kind, "INPUT_OBJECT")) return .{ .input = name };
    return error.UnsupportedType;
}

fn scalar(name: []const u8, expected: ?Type) Type {
    const eql = std.mem.eql;
    if (eql(u8, name, "String")) return .string;
    if (eql(u8, name, "Int")) return .int;
    if (eql(u8, name, "Float")) return .float;
    if (eql(u8, name, "Boolean")) return .boolean;
    if (eql(u8, name, "DateTime")) return .datetime;
    if (eql(u8, name, "Void")) return .void;
    if (eql(u8, name, "ID")) return expected orelse .id;
    return .{ .scalar = name };
}

fn box(a: Allocator, t: Type) !*const Type {
    const p = try a.create(Type);
    p.* = t;
    return p;
}

/// Render the type as a typespec.
pub fn spec(a: Allocator, w: *std.Io.Writer, t: Type) !void {
    switch (t) {
        .nullable => |inner| switch (inner.*) {
            .list => try spec(a, w, inner.*),
            else => {
                try spec(a, w, inner.*);
                try w.writeAll(" | nil");
            },
        },
        .list => |inner| {
            try w.writeByte('[');
            try spec(a, w, inner.*);
            try w.writeByte(']');
        },
        .string, .id => try w.writeAll("String.t()"),
        .int => try w.writeAll("integer()"),
        .float => try w.writeAll("float()"),
        .boolean => try w.writeAll("boolean()"),
        .datetime => try w.writeAll("DateTime.t()"),
        .void => try w.writeAll("Dagger.Void.t()"),
        .scalar, .object, .interface, .@"enum", .input => |name| {
            try w.writeAll(try naming.module(a, name));
            try w.writeAll(".t()");
        },
        .unknown => return error.UnsupportedType,
    }
}

/// Module backing the type, for struct construction.
pub fn module(a: Allocator, t: Type) !?[]const u8 {
    return switch (t) {
        .nullable, .list => |inner| module(a, inner.*),
        else => if (t.namedName()) |name| try naming.module(a, name) else null,
    };
}

pub const Encoder = union(enum) {
    identity,
    call: []const u8,
    map: []const u8,
};

/// How a value of this type travels in a query: objects and interfaces as ids.
pub fn encoder(t: Type) Encoder {
    return switch (t) {
        .nullable => |inner| encoder(inner.*),
        .list => |inner| switch (encoder(inner.*)) {
            .call => |f| .{ .map = f },
            else => .identity,
        },
        .object, .interface => .{ .call = "Dagger.ID.id!" },
        else => .identity,
    };
}

pub const Guard = union(enum) {
    none,
    call: []const u8,
    is_struct: []const u8,
    @"struct": []const u8,
    in: []const []const u8,
    /// Resolved to `in` or `call` by the analyzer, which knows enum members.
    @"enum",
};

pub fn guard(a: Allocator, t: Type) !Guard {
    return switch (t) {
        .string, .id, .scalar => .{ .call = "is_binary" },
        .int => .{ .call = "is_integer" },
        // GraphQL's Float accepts an integer literal, so `is_float/1` would be wrong.
        .float => .{ .call = "is_number" },
        .boolean => .{ .call = "is_boolean" },
        .datetime => .{ .is_struct = "DateTime" },
        .list => .{ .call = "is_list" },
        .@"enum" => .@"enum",
        .object, .input => |name| .{ .@"struct" = try naming.module(a, name) },
        .interface => .{ .call = "is_struct" },
        else => .none,
    };
}

pub fn nonNull(t: Type) Type {
    return switch (t) {
        .nullable => |inner| inner.*,
        else => t,
    };
}

pub fn isNullable(t: Type) bool {
    return t == .nullable;
}

pub fn isVoid(t: Type) bool {
    return switch (t) {
        .void => true,
        .nullable => |inner| isVoid(inner.*),
        else => false,
    };
}

pub fn isEnum(t: ?Type) bool {
    return switch (t orelse return false) {
        .@"enum" => true,
        .nullable => |inner| isEnum(inner.*),
        else => false,
    };
}

pub fn isNode(t: ?Type) bool {
    return switch (t orelse return false) {
        .object, .interface => true,
        .nullable => |inner| isNode(inner.*),
        else => false,
    };
}

/// Element type of a list, or null if the type is not a list.
pub fn element(t: Type) ?Type {
    return switch (t) {
        .nullable => |inner| element(inner.*),
        .list => |inner| nonNull(inner.*),
        else => null,
    };
}
