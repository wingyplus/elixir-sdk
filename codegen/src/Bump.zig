//! A bump allocator for memory that lives until the end of a run.
//!
//! Allocation moves a cursor through a chunk taken from `backing`; a full chunk
//! is abandoned for a bigger one. The most recent allocation can grow or shrink
//! in place, so an `ArrayList` appended to without interleaved allocations
//! never copies. `free` only reclaims the most recent allocation. Nothing is
//! returned to `backing` before `deinit`.
//!
//! Not threadsafe: give each thread its own.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const Bump = @This();

backing: Allocator,
chunk: []u8 = &.{},
end: usize = 0,
chunks: ?*Chunk = null,

const min_chunk = 1 << 20;

/// Header at the start of every chunk, linking it to the chunk before.
const Chunk = struct {
    prev: ?*Chunk,
    len: usize,
};

pub fn init(backing: Allocator) Bump {
    return .{ .backing = backing };
}

pub fn deinit(b: *Bump) void {
    var next = b.chunks;
    while (next) |c| {
        next = c.prev;
        const bytes: [*]u8 = @ptrCast(c);
        b.backing.rawFree(bytes[0..c.len], .of(Chunk), @returnAddress());
    }
    b.* = .{ .backing = b.backing };
}

/// Forget every allocation, keeping the current chunk for reuse.
pub fn reset(b: *Bump) void {
    b.end = 0;
}

pub fn allocator(b: *Bump) Allocator {
    return .{ .ptr = b, .vtable = &.{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    } };
}

fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const b: *Bump = @ptrCast(@alignCast(ctx));
    const base = @intFromPtr(b.chunk.ptr);
    const start = alignment.forward(base + b.end) - base;
    if (start + len <= b.chunk.len) {
        b.end = start + len;
        return b.chunk.ptr + start;
    }
    return b.grow(len, alignment, ret_addr);
}

fn grow(b: *Bump, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const header = @sizeOf(Chunk);
    const want = header + alignment.toByteUnits() + len;
    const size = @max(want, min_chunk, 2 * (if (b.chunks) |c| c.len else 0));
    const bytes = b.backing.rawAlloc(size, .of(Chunk), ret_addr) orelse return null;
    const c: *Chunk = @ptrCast(@alignCast(bytes));
    c.* = .{ .prev = b.chunks, .len = size };
    b.chunks = c;
    b.chunk = bytes[header..size];
    b.end = 0;
    return alloc(b, len, alignment, ret_addr);
}

/// Whether `memory` is the most recent allocation in the current chunk.
fn isLast(b: *const Bump, memory: []u8) bool {
    return @intFromPtr(memory.ptr) + memory.len == @intFromPtr(b.chunk.ptr) + b.end;
}

fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    _ = alignment;
    _ = ret_addr;
    const b: *Bump = @ptrCast(@alignCast(ctx));
    if (!b.isLast(memory)) return new_len <= memory.len;
    const start = @intFromPtr(memory.ptr) - @intFromPtr(b.chunk.ptr);
    if (start + new_len > b.chunk.len) return false;
    b.end = start + new_len;
    return true;
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    return if (resize(ctx, memory, alignment, new_len, ret_addr)) memory.ptr else null;
}

fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    _ = alignment;
    _ = ret_addr;
    const b: *Bump = @ptrCast(@alignCast(ctx));
    if (b.isLast(memory)) b.end = @intFromPtr(memory.ptr) - @intFromPtr(b.chunk.ptr);
}

test "the most recent allocation grows in place, others are copied" {
    var b = Bump.init(std.testing.allocator);
    defer b.deinit();
    const a = b.allocator();

    var list: std.ArrayList(u32) = .empty;
    for (0..1000) |i| try list.append(a, @intCast(i));
    const first = list.items.ptr;
    try list.append(a, 1000);
    try std.testing.expectEqual(first, list.items.ptr);

    const other = try a.alloc(u8, 3);
    for (0..10_000) |i| try list.append(a, @intCast(i));
    try std.testing.expectEqual(@as(u32, 9999), list.items[list.items.len - 1]);
    try std.testing.expectEqual(@as(usize, 11_001), list.items.len);
    other[2] = 1;

    // Bigger than a chunk.
    const big = try a.alloc(u8, 3 << 20);
    big[big.len - 1] = 7;
    b.reset();
    try std.testing.expectEqual(@as(u8, 7), big[big.len - 1]);
}
