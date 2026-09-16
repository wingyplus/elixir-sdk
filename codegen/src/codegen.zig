//! Schema-level driver, a port of `Dagger.Codegen`: which types get a module,
//! the index they are analyzed against, and where each file goes.

const std = @import("std");
const Allocator = std.mem.Allocator;
pub const introspection = @import("introspection.zig");
pub const analyzer = @import("analyzer.zig");
pub const parser = @import("parser.zig");
pub const Bump = @import("Bump.zig");
pub const render = @import("render.zig").render;
const renderer = @import("render.zig");
const naming = @import("naming.zig");

pub fn parse(a: Allocator, json: []const u8) !introspection.Schema {
    return parser.schema(a, json);
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

/// The index from located types, before any of them is parsed in full.
pub fn indexSpans(a: Allocator, spans: []const parser.Span) !analyzer.Index {
    var idx: analyzer.Index = .empty;
    try idx.ensureTotalCapacity(a, @intCast(spans.len));
    for (spans) |t| idx.putAssumeCapacity(t.name, .{
        .kind = analyzer.kindOf(t.kind),
        .enum_values = t.enum_values,
    });
    return idx;
}

const builtin_scalars = [_][]const u8{ "String", "Float", "Int", "Boolean", "DateTime", "ID" };

/// Whether a type gets a module: everything but introspection's own types and
/// the scalars that map onto Elixir builtins.
pub fn isEmittable(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "_")) return false;
    for (builtin_scalars) |s| if (std.mem.eql(u8, name, s)) return false;
    return true;
}

/// Types that get a module, with their fields sorted by name, in byte order, in
/// place.
pub fn emittable(a: Allocator, schema: introspection.Schema) ![]*introspection.FullType {
    var out: std.ArrayList(*introspection.FullType) = .empty;
    for (schema.types) |*t| {
        if (!isEmittable(t.name)) continue;
        sortFields(t);
        try out.append(a, t);
    }
    return out.items;
}

fn sortFields(t: *introspection.FullType) void {
    if (t.fields) |fields| std.mem.sort(introspection.Field, fields, {}, fieldLess);
    if (t.inputFields) |fields| std.mem.sort(introspection.InputValue, fields, {}, inputLess);
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
    try renderer.render(a, w, &def);
}

/// Generate every emittable type in an introspection result into `dir`, on up
/// to `workers` threads.
///
/// Only a scan runs up front: it finds each type's JSON and reads the kind,
/// name and enum values the index needs. Everything else about a type is
/// independent of the others, so each worker takes the next unclaimed type and
/// parses, analyzes, renders and writes it with its own allocator and buffer.
/// The largest types go first, so none of them is left to finish on its own.
///
/// Starting a thread costs about as much as generating a small type, so the
/// threads start one another while the scan runs, and wait for it to finish.
pub fn writeAll(gpa: Allocator, io: std.Io, dir: std.Io.Dir, json: []const u8, workers: usize) !void {
    var bump: Bump = .init(gpa);
    defer bump.deinit();
    const a = bump.allocator();

    var shared: Writer = .{ .gpa = gpa, .io = io, .dir = dir };
    shared.spare.store(workers -| 1, .monotonic);
    shared.spawn();
    defer shared.finish();

    const spans = try parser.spans(a, json);
    const idx = try indexSpans(a, spans);
    var jobs: std.ArrayList(parser.Span) = try .initCapacity(a, spans.len);
    for (spans) |t| if (isEmittable(t.name)) jobs.appendAssumeCapacity(t);
    std.mem.sort(parser.Span, jobs.items, {}, largerFirst);

    shared.jobs = jobs.items;
    shared.idx = &idx;
    shared.ready.store(1, .release);
    io.futexWake(u32, &shared.ready.raw, std.math.maxInt(u32));
    shared.run();
    if (shared.failed.load(.acquire)) return shared.err;
}

const Writer = struct {
    gpa: Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    jobs: []const parser.Span = &.{},
    idx: *const analyzer.Index = undefined,
    next: std.atomic.Value(usize) = .init(0),
    /// Threads still allowed to start.
    spare: std.atomic.Value(usize) = .init(0),
    /// Threads started and not yet exited; `finish` waits for zero.
    alive: std.atomic.Value(u32) = .init(0),
    /// Set to 1 once `jobs` and `idx` are in place, or the run is abandoned.
    ready: std.atomic.Value(u32) = .init(0),
    failed: std.atomic.Value(bool) = .init(false),
    err: anyerror = undefined,

    /// Start one more thread, if any is left to start.
    fn spawn(w: *Writer) void {
        var left = w.spare.load(.monotonic);
        while (left > 0) : (left = w.spare.load(.monotonic)) {
            if (w.spare.cmpxchgWeak(left, left - 1, .monotonic, .monotonic) == null) break;
        } else return;
        _ = w.alive.fetchAdd(1, .monotonic);
        const thread = std.Thread.spawn(.{ .stack_size = 256 * 1024, .allocator = w.gpa }, threadMain, .{w}) catch {
            w.exit();
            return;
        };
        thread.detach();
    }

    fn threadMain(w: *Writer) void {
        defer w.exit();
        w.spawn();
        while (w.ready.load(.acquire) == 0) w.io.futexWaitUncancelable(u32, &w.ready.raw, 0);
        w.run();
    }

    fn exit(w: *Writer) void {
        if (w.alive.fetchSub(1, .release) == 1) w.io.futexWake(u32, &w.alive.raw, std.math.maxInt(u32));
    }

    /// Release waiting threads, even on an early return, and wait for all of
    /// them to exit so none outlives `writeAll`.
    fn finish(w: *Writer) void {
        w.spare.store(0, .monotonic);
        if (w.ready.load(.acquire) == 0) {
            w.failed.store(true, .release);
            w.ready.store(1, .release);
            w.io.futexWake(u32, &w.ready.raw, std.math.maxInt(u32));
        }
        while (true) {
            const alive = w.alive.load(.acquire);
            if (alive == 0) return;
            w.io.futexWaitUncancelable(u32, &w.alive.raw, alive);
        }
    }

    fn run(w: *Writer) void {
        w.generateEach() catch |err| {
            if (!w.failed.swap(true, .acquire)) w.err = err;
        };
    }

    fn generateEach(w: *Writer) !void {
        if (w.failed.load(.monotonic)) return;
        var bump: Bump = .init(w.gpa);
        defer bump.deinit();
        var buf: std.Io.Writer.Allocating = try .initCapacity(w.gpa, 256 * 1024);
        defer buf.deinit();
        while (!w.failed.load(.monotonic)) {
            const i = w.next.fetchAdd(1, .monotonic);
            if (i >= w.jobs.len) return;
            bump.reset();
            buf.clearRetainingCapacity();
            const a = bump.allocator();
            var t = try parser.fullTypeDocument(a, w.jobs[i].json);
            sortFields(&t);
            try generate(a, &buf.writer, &t, w.idx);
            try w.dir.writeFile(w.io, .{ .sub_path = try filename(a, &t), .data = buf.written() });
        }
    }
};

fn largerFirst(_: void, l: parser.Span, r: parser.Span) bool {
    return l.json.len > r.json.len;
}

pub fn filename(a: Allocator, t: *const introspection.FullType) ![]const u8 {
    return std.mem.concat(a, u8, &.{ try naming.variable(a, t.name), ".ex" });
}

test {
    _ = naming;
    _ = parser;
    _ = Bump;
}
