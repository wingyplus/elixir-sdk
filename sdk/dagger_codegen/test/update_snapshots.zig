//! Rewrite `snapshots/` from the current generator. Run through
//! `zig build update-snapshots`, which sets the working directory to `test/`.

const std = @import("std");
const cases = @import("cases.zig");
const golden = @import("golden.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const dir = std.Io.Dir.cwd();
    for (cases.all) |c| {
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try dir.readFileAlloc(io, try std.fmt.allocPrint(a, "fixtures/{s}.json", .{c.fixture}), a, .unlimited);
        const path = try std.fmt.allocPrint(a, "snapshots/{s}.ex", .{c.name});
        if (std.fs.path.dirname(path)) |parent| try dir.createDirPath(io, parent);
        try dir.writeFile(io, .{ .sub_path = path, .data = try golden.render(a, c, fixture) });
    }
}
