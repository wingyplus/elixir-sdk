//! dagger_codegen in Zig.
//!
//!   dagger_codegen generate --outdir DIR --introspection FILE
//!   dagger_codegen bench --introspection FILE [--iterations N]
//!
//! `generate` writes laid-out Elixir source, byte-identical to what
//! `mix dagger.codegen generate` writes for the same schema. No formatter pass.

const std = @import("std");
const Io = std.Io;
const codegen = @import("codegen.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) return usage();
    const outdir = flag(args, "--outdir");
    const introspection = flag(args, "--introspection") orelse return usage();

    if (std.mem.eql(u8, args[1], "generate")) {
        try generate(init.gpa, io, introspection, outdir orelse return usage());
    } else if (std.mem.eql(u8, args[1], "bench")) {
        const n = if (flag(args, "--iterations")) |s| try std.fmt.parseInt(usize, s, 10) else 50;
        try bench(init.gpa, io, introspection, n);
    } else return usage();
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        \\usage: dagger_codegen generate --outdir DIR --introspection FILE
        \\       dagger_codegen bench --introspection FILE [--iterations N]
        \\
    , .{});
    return error.InvalidArguments;
}

fn flag(args: []const [:0]const u8, name: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, name) and i + 1 < args.len) return args[i + 1];
    }
    return null;
}

fn generate(gpa: std.mem.Allocator, io: Io, path: []const u8, outdir: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const cwd = Io.Dir.cwd();
    const json = try cwd.readFileAlloc(io, path, a, .unlimited);
    const schema = try codegen.parse(a, json);
    const idx = try codegen.index(a, schema);

    try cwd.createDirPath(io, outdir);
    var dir = try cwd.openDir(io, outdir, .{});
    defer dir.close(io);

    var buf: Io.Writer.Allocating = try .initCapacity(gpa, 64 * 1024);
    defer buf.deinit();
    for (try codegen.emittable(a, schema)) |t| {
        buf.clearRetainingCapacity();
        try codegen.generate(a, &buf.writer, t, &idx);
        try dir.writeFile(io, .{ .sub_path = try codegen.filename(a, t), .data = buf.written() });
    }
}

/// Time each phase in-process, repeated, so process start-up is excluded.
fn bench(gpa: std.mem.Allocator, io: Io, path: []const u8, iterations: usize) !void {
    const json = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(json);

    var parse_ns: [256]i96 = undefined;
    var gen_ns: [256]i96 = undefined;
    const n = @min(iterations, parse_ns.len);
    var bytes: usize = 0;

    var buf: Io.Writer.Allocating = try .initCapacity(gpa, 64 * 1024);
    defer buf.deinit();

    for (0..n) |i| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const a = arena_state.allocator();

        const t0 = Io.Clock.awake.now(io);
        const schema = try codegen.parse(a, json);
        const t1 = Io.Clock.awake.now(io);
        const idx = try codegen.index(a, schema);
        bytes = 0;
        for (try codegen.emittable(a, schema)) |t| {
            buf.clearRetainingCapacity();
            try codegen.generate(a, &buf.writer, t, &idx);
            bytes += buf.written().len;
        }
        const t2 = Io.Clock.awake.now(io);
        parse_ns[i] = t0.durationTo(t1).nanoseconds;
        gen_ns[i] = t1.durationTo(t2).nanoseconds;
    }

    std.mem.sort(i96, parse_ns[0..n], {}, std.sort.asc(i96));
    std.mem.sort(i96, gen_ns[0..n], {}, std.sort.asc(i96));
    std.debug.print(
        "iterations: {d}\nraw bytes: {d}\njson parse median: {d:.2} ms\nindex+analyze+render median: {d:.2} ms\n",
        .{ n, bytes, ms(parse_ns[n / 2]), ms(gen_ns[n / 2]) },
    );
}

fn ms(ns: i96) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e6;
}

test {
    _ = codegen;
}
