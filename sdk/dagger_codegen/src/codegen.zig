//! Schema-level driver, a port of `Dagger.Codegen`: which types get a module,
//! the index they are analyzed against, and where each file goes.

const std = @import("std");
const Allocator = std.mem.Allocator;
pub const introspection = @import("introspection.zig");
pub const analyzer = @import("analyzer.zig");
const render = @import("render.zig");
const naming = @import("naming.zig");

pub fn parse(a: Allocator, json: []const u8) !introspection.Schema {
    const root = try std.json.parseFromSliceLeaky(introspection.Root, a, json, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_if_needed,
    });
    return root.__schema;
}

pub fn index(a: Allocator, schema: introspection.Schema) !analyzer.Index {
    var idx: analyzer.Index = .empty;
    try idx.ensureTotalCapacity(a, @intCast(schema.types.len));
    for (schema.types) |t| idx.putAssumeCapacity(t.name, .{
        .kind = analyzer.kindOf(t.kind),
        .enum_values = t.enumValues orelse &.{},
    });
    return idx;
}

const builtin_scalars = [_][]const u8{ "String", "Float", "Int", "Boolean", "DateTime", "ID" };

/// Types that get a module: everything but introspection's own types and the
/// scalars that map onto Elixir builtins. Fields are sorted by name, in byte
/// order, in place.
pub fn emittable(a: Allocator, schema: introspection.Schema) ![]*introspection.FullType {
    var out: std.ArrayList(*introspection.FullType) = .empty;
    outer: for (schema.types) |*t| {
        if (std.mem.startsWith(u8, t.name, "_")) continue;
        for (builtin_scalars) |s| if (std.mem.eql(u8, t.name, s)) continue :outer;
        if (t.fields) |fields| std.mem.sort(introspection.Field, fields, {}, fieldLess);
        if (t.inputFields) |fields| std.mem.sort(introspection.InputValue, fields, {}, inputLess);
        try out.append(a, t);
    }
    return out.items;
}

fn fieldLess(_: void, l: introspection.Field, r: introspection.Field) bool {
    return std.mem.lessThan(u8, l.name, r.name);
}

fn inputLess(_: void, l: introspection.InputValue, r: introspection.InputValue) bool {
    return std.mem.lessThan(u8, l.name, r.name);
}

/// Render one type's raw source into `w`.
pub fn generate(a: Allocator, w: *std.Io.Writer, t: *const introspection.FullType, idx: *const analyzer.Index) !void {
    const def = try analyzer.analyze(a, t, idx);
    try render.render(a, w, &def);
}

pub fn filename(a: Allocator, t: *const introspection.FullType) ![]const u8 {
    return std.mem.concat(a, u8, &.{ try naming.variable(a, t.name), ".ex" });
}

test {
    _ = naming;
}
