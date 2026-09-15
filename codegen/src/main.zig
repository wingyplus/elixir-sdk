//! dagger_codegen in Zig.
//!
//!   dagger_codegen generate --outdir DIR --introspection FILE [--jobs N]
//!   dagger_codegen bench --introspection FILE [--outdir DIR] [--iterations N]
//!
//! `generate` writes laid-out Elixir source, byte-identical to what
//! `mix dagger.codegen generate` writes for the same schema. No formatter pass.

const std = @import("std");
const Io = std.Io;
const codegen = @import("codegen.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    // Start-up is a measurable share of a run, so skip what `std.process.Init`
    // sets up and this program never uses: file operations block anyway, and
    // the worker threads in `codegen.writeAll` are plain threads.
    var threaded: Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const gpa = std.heap.smp_allocator;
    var args_bump: codegen.Bump = .init(gpa);
    const args = try init.args.toSlice(args_bump.allocator());

    if (args.len < 2) return usage();
    const outdir = flag(args, "--outdir");
    const introspection = flag(args, "--introspection") orelse return usage();

    if (std.mem.eql(u8, args[1], "generate")) {
        // A thread takes about as long to start as a small type takes to
        // generate, so beyond a few the extra threads cost more than they save.
        const jobs = if (flag(args, "--jobs")) |s| try std.fmt.parseInt(usize, s, 10) else @min(4, std.Thread.getCpuCount() catch 1);
        try generate(gpa, io, introspection, outdir orelse return usage(), @max(jobs, 1));
        std.process.exit(0);
    } else if (std.mem.eql(u8, args[1], "bench")) {
        const n = if (flag(args, "--iterations")) |s| try std.fmt.parseInt(usize, s, 10) else 50;
        try bench(gpa, io, introspection, outdir, n);
    } else return usage();
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        \\usage: dagger_codegen generate --outdir DIR --introspection FILE [--jobs N]
        \\       dagger_codegen bench --introspection FILE [--outdir DIR] [--iterations N]
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

/// Nothing here is freed: the process exits as soon as the last file is
/// written, and tearing the heap down first would only add work.
fn generate(gpa: std.mem.Allocator, io: Io, path: []const u8, outdir: []const u8, jobs: usize) !void {
    const cwd = Io.Dir.cwd();
    const json = try mapFile(io, cwd, path);
    try cwd.createDirPath(io, outdir);
    const dir = try cwd.openDir(io, outdir, .{});
    try codegen.writeAll(gpa, io, dir, json, jobs);
}

/// Map a file read-only rather than copying it into the heap.
fn mapFile(io: Io, dir: Io.Dir, path: []const u8) ![]const u8 {
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    const len = try file.length(io);
    if (len == 0) return "";
    return std.posix.mmap(null, @intCast(len), .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
}

/// Time each phase in-process, repeated, so process start-up is excluded.
/// Files are written under `--outdir` when given.
fn bench(gpa: std.mem.Allocator, io: Io, path: []const u8, outdir: ?[]const u8, iterations: usize) !void {
    const json = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(json);

    const Phase = enum { parse, index, analyze, render, write, total };
    var samples: [@typeInfo(Phase).@"enum".fields.len][256]i96 = undefined;
    const n = @min(iterations, 256);
    var bytes: usize = 0;

    var buf: Io.Writer.Allocating = try .initCapacity(gpa, 64 * 1024);
    defer buf.deinit();

    var dir: ?Io.Dir = null;
    if (outdir) |o| {
        try Io.Dir.cwd().createDirPath(io, o);
        dir = try Io.Dir.cwd().openDir(io, o, .{});
    }
    defer if (dir) |*d| d.close(io);

    for (0..n) |i| {
        var bump: codegen.Bump = .init(gpa);
        defer bump.deinit();
        const a = bump.allocator();
        var acc: [@typeInfo(Phase).@"enum".fields.len]i96 = @splat(0);

        const t0 = Io.Clock.awake.now(io);
        const schema = try codegen.parse(a, json);
        const t1 = Io.Clock.awake.now(io);
        const idx = try codegen.index(a, schema);
        const emit = try codegen.emittable(a, schema);
        const t2 = Io.Clock.awake.now(io);
        acc[@intFromEnum(Phase.parse)] = t0.durationTo(t1).nanoseconds;
        acc[@intFromEnum(Phase.index)] = t1.durationTo(t2).nanoseconds;
        bytes = 0;
        for (emit) |t| {
            buf.clearRetainingCapacity();
            const s0 = Io.Clock.awake.now(io);
            const def = try codegen.analyzer.analyze(a, t, &idx);
            const s1 = Io.Clock.awake.now(io);
            try codegen.render(a, &buf.writer, &def);
            const s2 = Io.Clock.awake.now(io);
            if (dir) |d| try d.writeFile(io, .{ .sub_path = try codegen.filename(a, t), .data = buf.written() });
            const s3 = Io.Clock.awake.now(io);
            acc[@intFromEnum(Phase.analyze)] += s0.durationTo(s1).nanoseconds;
            acc[@intFromEnum(Phase.render)] += s1.durationTo(s2).nanoseconds;
            acc[@intFromEnum(Phase.write)] += s2.durationTo(s3).nanoseconds;
            bytes += buf.written().len;
        }
        acc[@intFromEnum(Phase.total)] = t0.durationTo(Io.Clock.awake.now(io)).nanoseconds;
        for (&samples, acc) |*sample, v| sample[i] = v;
    }

    std.debug.print("iterations: {d}\nraw bytes: {d}\n", .{ n, bytes });
    for (&samples, 0..) |*sample, p| {
        std.mem.sort(i96, sample[0..n], {}, std.sort.asc(i96));
        std.debug.print("{s} median: {d:.3} ms\n", .{ @tagName(@as(Phase, @enumFromInt(p))), ms(sample[n / 2]) });
    }
}

fn ms(ns: i96) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e6;
}

test {
    _ = codegen;
}
