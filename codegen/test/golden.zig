//! Every snapshot case renders byte-for-byte to its `snapshots/` file.
//!
//! After an intended change to the output, rewrite them with
//! `zig build update-snapshots` and review the diff.

const std = @import("std");
const codegen = @import("codegen");
const cases = @import("cases.zig");

pub fn render(a: std.mem.Allocator, c: cases.Case, fixture: []const u8) ![]const u8 {
    const t = try codegen.parser.fullTypeDocument(a, fixture);
    var index: codegen.analyzer.Index = .empty;
    for (c.index) |stub| {
        const values = try a.alloc(codegen.introspection.EnumValue, stub.enum_values.len);
        for (stub.enum_values, values) |name, *v| v.* = .{ .name = name };
        try index.put(a, stub.name, .{ .kind = stub.kind, .enum_values = values });
    }
    var out: std.Io.Writer.Allocating = .init(a);
    try codegen.generate(a, &out.writer, &t, &index);
    return out.written();
}

test "generated modules match their snapshots" {
    var failures: usize = 0;
    inline for (cases.all) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const got = try render(arena.allocator(), c, @embedFile("fixtures/" ++ c.fixture ++ ".json"));
        const want = @embedFile("snapshots/" ++ c.name ++ ".ex");
        if (!std.mem.eql(u8, got, want)) {
            failures += 1;
            std.debug.print("\nsnapshot mismatch: {s}\n", .{c.name});
            std.testing.expectEqualStrings(want, got) catch {};
        }
    }
    try std.testing.expectEqual(0, failures);
}

test "the schema reader agrees with std.json on every fixture" {
    inline for (cases.all) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = @embedFile("fixtures/" ++ c.fixture ++ ".json");
        const want = try std.json.parseFromSliceLeaky(codegen.introspection.FullType, a, fixture, .{
            .ignore_unknown_fields = true,
        });
        try std.testing.expectEqualDeep(want, try codegen.parser.fullTypeDocument(a, fixture));
    }
}
