//! Reads an introspection schema straight into `introspection` structs.
//!
//! A replacement for `std.json` specialised to the handful of shapes the
//! generator reads: it matches keys against the fields it knows, skips
//! everything else without looking inside, and slices strings with no escapes
//! straight out of the input. Escaped strings are decoded into the allocator.
//! Malformed JSON, and a missing required field, are still errors.

const std = @import("std");
const Allocator = std.mem.Allocator;
const introspection = @import("introspection.zig");

pub const Error = error{ SyntaxError, MissingField, OutOfMemory };

/// Parse a whole introspection result, `{"__schema": {"types": [...]}}`.
pub fn schema(a: Allocator, src: []const u8) Error!introspection.Schema {
    return .{ .types = try types(a, src, introspection.FullType, fullType) };
}

/// A type in the schema, read only as far as the rest of the schema needs to
/// know it: its kind, name and enum values, and the JSON to parse it from.
pub const Span = struct {
    kind: []const u8,
    name: []const u8,
    enum_values: []const introspection.EnumValue = &.{},
    json: []const u8,
};

/// Locate every type in an introspection result without parsing its fields.
pub fn spans(a: Allocator, src: []const u8) Error![]Span {
    return types(a, src, Span, span);
}

fn types(a: Allocator, src: []const u8, comptime T: type, comptime element: fn (*Parser) Error!T) Error![]T {
    var p: Parser = .{ .src = src, .a = a };
    var found: ?[]T = null;
    var root = try p.object();
    while (try root.next(&p)) |key| {
        if (!eql(key, "__schema")) {
            try p.skip();
            continue;
        }
        var s = try p.object();
        while (try s.next(&p)) |k| {
            if (eql(k, "types")) found = try p.list(T, element) else try p.skip();
        }
    }
    try p.end();
    return found orelse error.MissingField;
}

fn span(p: *Parser) Error!Span {
    p.whitespace();
    const start = p.pos;
    var t: Span = .{ .kind = undefined, .name = undefined, .json = undefined };
    var seen: packed struct { kind: bool = false, name: bool = false } = .{};
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "kind")) {
            t.kind = try p.string();
            seen.kind = true;
        } else if (eql(key, "name")) {
            t.name = try p.string();
            seen.name = true;
        } else if (eql(key, "enumValues")) {
            t.enum_values = try p.nullableList(introspection.EnumValue, enumValue) orelse &.{};
        } else try p.skip();
    }
    if (!seen.kind or !seen.name) return error.MissingField;
    t.json = p.src[start..p.pos];
    return t;
}

/// Parse a single introspection type.
pub fn fullType(p: *Parser) Error!introspection.FullType {
    var t: introspection.FullType = .{ .kind = undefined, .name = undefined };
    var seen: packed struct { kind: bool = false, name: bool = false } = .{};
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "kind")) {
            t.kind = try p.string();
            seen.kind = true;
        } else if (eql(key, "name")) {
            t.name = try p.string();
            seen.name = true;
        } else if (eql(key, "description")) {
            t.description = try p.nullableString();
        } else if (eql(key, "fields")) {
            t.fields = try p.nullableList(introspection.Field, field);
        } else if (eql(key, "inputFields")) {
            t.inputFields = try p.nullableList(introspection.InputValue, inputValue);
        } else if (eql(key, "enumValues")) {
            t.enumValues = try p.nullableList(introspection.EnumValue, enumValue);
        } else try p.skip();
    }
    if (!seen.kind or !seen.name) return error.MissingField;
    return t;
}

/// Parse a single introspection type from its own JSON document.
pub fn fullTypeDocument(a: Allocator, src: []const u8) Error!introspection.FullType {
    var p: Parser = .{ .src = src, .a = a };
    const t = try fullType(&p);
    try p.end();
    return t;
}

fn field(p: *Parser) Error!introspection.Field {
    var f: introspection.Field = .{ .name = undefined, .type = undefined };
    var seen: packed struct { name: bool = false, type: bool = false } = .{};
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "name")) {
            f.name = try p.string();
            seen.name = true;
        } else if (eql(key, "description")) {
            f.description = try p.nullableString();
        } else if (eql(key, "deprecationReason")) {
            f.deprecationReason = try p.nullableString();
        } else if (eql(key, "args")) {
            f.args = try p.list(introspection.InputValue, inputValue);
        } else if (eql(key, "type")) {
            f.type = try typeRef(p);
            seen.type = true;
        } else if (eql(key, "directives")) {
            f.directives = try p.nullableList(introspection.Directive, directive);
        } else try p.skip();
    }
    if (!seen.name or !seen.type) return error.MissingField;
    return f;
}

fn inputValue(p: *Parser) Error!introspection.InputValue {
    var v: introspection.InputValue = .{ .name = undefined, .type = undefined };
    var seen: packed struct { name: bool = false, type: bool = false } = .{};
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "name")) {
            v.name = try p.string();
            seen.name = true;
        } else if (eql(key, "description")) {
            v.description = try p.nullableString();
        } else if (eql(key, "type")) {
            v.type = try typeRef(p);
            seen.type = true;
        } else if (eql(key, "directives")) {
            v.directives = try p.nullableList(introspection.Directive, directive);
        } else try p.skip();
    }
    if (!seen.name or !seen.type) return error.MissingField;
    return v;
}

fn enumValue(p: *Parser) Error!introspection.EnumValue {
    var v: introspection.EnumValue = .{ .name = undefined };
    var seen_name = false;
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "name")) {
            v.name = try p.string();
            seen_name = true;
        } else if (eql(key, "description")) {
            v.description = try p.nullableString();
        } else if (eql(key, "directives")) {
            v.directives = try p.nullableList(introspection.Directive, directive);
        } else try p.skip();
    }
    if (!seen_name) return error.MissingField;
    return v;
}

fn directive(p: *Parser) Error!introspection.Directive {
    var d: introspection.Directive = .{ .name = undefined };
    var seen_name = false;
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "name")) {
            d.name = try p.string();
            seen_name = true;
        } else if (eql(key, "args")) {
            d.args = try p.list(introspection.DirectiveArg, directiveArg);
        } else try p.skip();
    }
    if (!seen_name) return error.MissingField;
    return d;
}

fn directiveArg(p: *Parser) Error!introspection.DirectiveArg {
    var arg: introspection.DirectiveArg = .{ .name = undefined };
    var seen_name = false;
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "name")) {
            arg.name = try p.string();
            seen_name = true;
        } else if (eql(key, "value")) {
            arg.value = try p.nullableString();
        } else try p.skip();
    }
    if (!seen_name) return error.MissingField;
    return arg;
}

fn typeRef(p: *Parser) Error!introspection.TypeRef {
    var r: introspection.TypeRef = .{ .kind = undefined };
    var seen_kind = false;
    var o = try p.object();
    while (try o.next(p)) |key| {
        if (eql(key, "kind")) {
            r.kind = try p.string();
            seen_kind = true;
        } else if (eql(key, "name")) {
            r.name = try p.nullableString();
        } else if (eql(key, "ofType")) {
            if (p.null_()) continue;
            const child = try p.a.create(introspection.TypeRef);
            child.* = try typeRef(p);
            r.ofType = child;
        } else try p.skip();
    }
    if (!seen_kind) return error.MissingField;
    return r;
}

pub const Parser = struct {
    src: []const u8,
    pos: usize = 0,
    a: Allocator,

    /// Iterates the keys of an object; the caller consumes each value.
    const Object = struct {
        first: bool = true,

        fn next(o: *Object, p: *Parser) Error!?[]const u8 {
            if (try p.closes('}')) return null;
            if (!o.first) try p.expect(',');
            o.first = false;
            const key = try p.string();
            try p.expect(':');
            return key;
        }
    };

    fn object(p: *Parser) Error!Object {
        try p.expect('{');
        return .{};
    }

    fn list(p: *Parser, comptime T: type, comptime element: fn (*Parser) Error!T) Error![]T {
        try p.expect('[');
        if (try p.closes(']')) return &.{};
        var items: std.ArrayList(T) = try .initCapacity(p.a, 8);
        while (true) {
            try items.append(p.a, try element(p));
            if (try p.closes(']')) return items.items;
            try p.expect(',');
        }
    }

    fn nullableList(p: *Parser, comptime T: type, comptime element: fn (*Parser) Error!T) Error!?[]T {
        return if (p.null_()) null else try p.list(T, element);
    }

    fn string(p: *Parser) Error![]const u8 {
        try p.expect('"');
        const start = p.pos;
        const at = quoteOrEscape(p.src, start) orelse return error.SyntaxError;
        if (p.src[at] == '"') {
            p.pos = at + 1;
            return p.src[start..at];
        }
        return p.escaped(start);
    }

    fn nullableString(p: *Parser) Error!?[]const u8 {
        return if (p.null_()) null else try p.string();
    }

    /// Decode a string with escapes, from just after its opening quote.
    fn escaped(p: *Parser, start: usize) Error![]const u8 {
        var out: std.ArrayList(u8) = try .initCapacity(p.a, 64);
        var i = start;
        while (true) {
            const at = quoteOrEscape(p.src, i) orelse return error.SyntaxError;
            try out.appendSlice(p.a, p.src[i..at]);
            if (p.src[at] == '"') {
                p.pos = at + 1;
                return out.items;
            }
            if (at + 1 >= p.src.len) return error.SyntaxError;
            i = at + 2;
            const byte: u8 = switch (p.src[at + 1]) {
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                'b' => 0x08,
                'f' => 0x0c,
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'u' => {
                    var cp: u21 = try hex4(p.src, at + 2);
                    i = at + 6;
                    if (cp >= 0xd800 and cp <= 0xdbff) {
                        if (i + 6 > p.src.len or p.src[i] != '\\' or p.src[i + 1] != 'u') return error.SyntaxError;
                        const low = try hex4(p.src, i + 2);
                        if (low < 0xdc00 or low > 0xdfff) return error.SyntaxError;
                        cp = 0x10000 + ((cp - 0xd800) << 10) + (low - 0xdc00);
                        i += 6;
                    } else if (cp >= 0xdc00 and cp <= 0xdfff) {
                        return error.SyntaxError;
                    }
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &buf) catch return error.SyntaxError;
                    try out.appendSlice(p.a, buf[0..n]);
                    continue;
                },
                else => return error.SyntaxError,
            };
            try out.append(p.a, byte);
        }
    }

    /// Skip one value of any kind without decoding it.
    fn skip(p: *Parser) Error!void {
        p.whitespace();
        if (p.pos >= p.src.len) return error.SyntaxError;
        switch (p.src[p.pos]) {
            '"' => p.pos = try skipString(p.src, p.pos + 1),
            '{', '[' => p.pos = try skipContainer(p.src, p.pos),
            't' => try p.literal("true"),
            'f' => try p.literal("false"),
            'n' => try p.literal("null"),
            '-', '0'...'9' => {
                p.pos += 1;
                while (p.pos < p.src.len) : (p.pos += 1) switch (p.src[p.pos]) {
                    '0'...'9', '.', 'e', 'E', '+', '-' => {},
                    else => break,
                };
            },
            else => return error.SyntaxError,
        }
    }

    /// Index just past the closing quote of a string whose body starts at `i`.
    fn skipString(src: []const u8, start: usize) Error!usize {
        var i = start;
        while (true) {
            i = quoteOrEscape(src, i) orelse return error.SyntaxError;
            if (src[i] == '"') return i + 1;
            i += 2;
        }
    }

    fn literal(p: *Parser, comptime word: []const u8) Error!void {
        if (!std.mem.startsWith(u8, p.src[p.pos..], word)) return error.SyntaxError;
        p.pos += word.len;
    }

    /// Consume a `null` if one comes next.
    fn null_(p: *Parser) bool {
        p.whitespace();
        if (!std.mem.startsWith(u8, p.src[p.pos..], "null")) return false;
        p.pos += 4;
        return true;
    }

    /// Consume `close` if it comes next.
    fn closes(p: *Parser, close: u8) Error!bool {
        p.whitespace();
        if (p.pos >= p.src.len) return error.SyntaxError;
        if (p.src[p.pos] != close) return false;
        p.pos += 1;
        return true;
    }

    fn expect(p: *Parser, byte: u8) Error!void {
        p.whitespace();
        if (p.pos >= p.src.len or p.src[p.pos] != byte) return error.SyntaxError;
        p.pos += 1;
    }

    fn end(p: *Parser) Error!void {
        p.whitespace();
        if (p.pos != p.src.len) return error.SyntaxError;
    }

    fn whitespace(p: *Parser) void {
        while (p.pos < p.src.len) : (p.pos += 1) switch (p.src[p.pos]) {
            ' ', '\t', '\n', '\r' => {},
            else => return,
        };
    }
};

/// Index just past the `}` or `]` that closes the object or array opening at
/// `start`, 64 bytes at a time.
///
/// Uses simdjson's bit tricks: a backslash escapes the byte after it only at
/// the end of an odd-length run, a prefix XOR over the unescaped quotes marks
/// the bytes inside strings, and brackets outside strings move the depth. A
/// block with fewer closing brackets than the depth cannot end the container
/// and is skipped without looking at its bits one by one. The brackets are not
/// checked to match: that is left to the parser, which reads this JSON in full
/// if it needs it.
fn skipContainer(src: []const u8, start: usize) Error!usize {
    const odd_bits: u64 = 0xaaaa_aaaa_aaaa_aaaa;
    const V = @Vector(64, u8);
    var depth: u64 = 0;
    var in_string: u64 = 0;
    var next_escaped: u64 = 0;
    var i = start;
    var tail: [64]u8 = undefined;
    while (i < src.len) : (i += 64) {
        const bytes: *const [64]u8 = if (i + 64 <= src.len) src[i..][0..64] else blk: {
            @memset(&tail, ' ');
            @memcpy(tail[0 .. src.len - i], src[i..]);
            break :blk &tail;
        };
        const chunk: V = bytes.*;
        const backslash: u64 = @bitCast(chunk == @as(V, @splat('\\')));
        var escaped = next_escaped;
        if (backslash != 0) {
            const potential = backslash & ~next_escaped;
            const code = (((potential << 1) | odd_bits) -% potential) ^ odd_bits;
            escaped = code ^ (backslash | next_escaped);
            next_escaped = (code & backslash) >> 63;
        } else {
            next_escaped = 0;
        }
        const quotes = @as(u64, @bitCast(chunk == @as(V, @splat('"')))) & ~escaped;
        const inside = prefixXor(quotes) ^ in_string;
        in_string = 0 -% (inside >> 63);
        const opens = (@as(u64, @bitCast(chunk == @as(V, @splat('{')))) | @as(u64, @bitCast(chunk == @as(V, @splat('['))))) & ~inside;
        const closes = (@as(u64, @bitCast(chunk == @as(V, @splat('}')))) | @as(u64, @bitCast(chunk == @as(V, @splat(']'))))) & ~inside;
        if (depth > @popCount(closes)) {
            depth = depth + @popCount(opens) - @popCount(closes);
            continue;
        }
        var events = opens | closes;
        while (events != 0) : (events &= events - 1) {
            const bit: u6 = @intCast(@ctz(events));
            if (opens & (@as(u64, 1) << bit) != 0) {
                depth += 1;
            } else {
                depth -= 1;
                if (depth == 0) return i + bit + 1;
            }
        }
    }
    return error.SyntaxError;
}

/// Each bit set to the XOR of itself and every bit below it.
fn prefixXor(bits: u64) u64 {
    var x = bits;
    x ^= x << 1;
    x ^= x << 2;
    x ^= x << 4;
    x ^= x << 8;
    x ^= x << 16;
    x ^= x << 32;
    return x;
}

/// Index of the first `"` or `\\` at or after `start`, 16 bytes at a time.
fn quoteOrEscape(src: []const u8, start: usize) ?usize {
    const V = @Vector(16, u8);
    var i = start;
    while (i + 16 <= src.len) : (i += 16) {
        const chunk: V = src[i..][0..16].*;
        const quotes: u16 = @bitCast(chunk == @as(V, @splat('"')));
        const escapes: u16 = @bitCast(chunk == @as(V, @splat('\\')));
        const hits = quotes | escapes;
        if (hits != 0) return i + @ctz(hits);
    }
    while (i < src.len) : (i += 1) {
        if (src[i] == '"' or src[i] == '\\') return i;
    }
    return null;
}

fn hex4(src: []const u8, at: usize) Error!u21 {
    if (at + 4 > src.len) return error.SyntaxError;
    return std.fmt.parseInt(u16, src[at .. at + 4], 16) catch error.SyntaxError;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn expectSame(src: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const want = try std.json.parseFromSliceLeaky(introspection.FullType, a, src, .{ .ignore_unknown_fields = true });
    try std.testing.expectEqualDeep(want, try fullTypeDocument(a, src));
}

test "strings decode every JSON escape" {
    try expectSame(
        \\{"kind": "OBJECT", "name": "Q", "description": "a\"b\\c\/d\be\ff\ng\rh\ti é 😀 A"}
    );
}

test "unknown keys of every kind are skipped" {
    try expectSame(
        \\{"interfaces": [{"a": [1, -2.5e+3, true, false, null, "x\"]}"]}], "kind": "ENUM",
        \\ "possibleTypes": null, "name": "E", "specifiedByURL": "{", "enumValues": [
        \\   {"name": "A", "isDeprecated": false, "directives": [{"name": "d", "args": [{"name": "n", "value": "\"v\""}]}]}
        \\ ]}
    );
}

test "nested type references and nullable fields" {
    try expectSame(
        \\{"kind": "OBJECT", "name": "T", "description": null, "inputFields": null, "fields": [
        \\  {"name": "f", "description": "", "deprecationReason": null, "directives": null,
        \\   "args": [{"name": "x", "defaultValue": "1", "type": {"kind": "LIST", "name": null,
        \\     "ofType": {"kind": "NON_NULL", "ofType": {"kind": "SCALAR", "name": "Int", "ofType": null}}}}],
        \\   "type": {"kind": "NON_NULL", "ofType": {"kind": "OBJECT", "name": "T"}}}
        \\]}
    );
}

test "malformed input and missing fields are errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{
        \\{"kind": "OBJECT"}
        ,
        \\{"kind": "OBJECT", "name": "T",}
        ,
        \\{"kind": "OBJECT", "name": "T"} trailing
        ,
        \\{"kind": "OBJECT", "name": "T\u12"}
        ,
        \\{"kind": "OBJECT", "name": "T\ud800"}
        ,
        \\{"kind": "OBJECT", "name": "T", "fields": [{"name": "f"}]}
        ,
        \\{"kind": "OBJECT", "name": "T", "x": [1, 2}
    }) |src| {
        try std.testing.expect(std.meta.isError(fullTypeDocument(a, src)));
    }
}

test "skipContainer agrees with a byte-at-a-time scan" {
    const reference = struct {
        fn skip(src: []const u8, start: usize) ?usize {
            var depth: usize = 0;
            var i = start;
            var in_string = false;
            while (i < src.len) : (i += 1) {
                const c = src[i];
                if (in_string) {
                    if (c == '\\') i += 1 else if (c == '"') in_string = false;
                    continue;
                }
                switch (c) {
                    '"' => in_string = true,
                    '{', '[' => depth += 1,
                    '}', ']' => {
                        depth -= 1;
                        if (depth == 0) return i + 1;
                    },
                    else => {},
                }
            }
            return null;
        }
    };

    var prng: std.Random.DefaultPrng = .init(0x5eed);
    const random = prng.random();
    var buf: [700]u8 = undefined;
    for (0..20_000) |_| {
        // A nested structure whose strings are full of brackets, quotes and
        // backslash runs, so escapes and strings straddle 64-byte blocks.
        var len: usize = 0;
        var depth: usize = 0;
        buf[len] = '[';
        len += 1;
        depth += 1;
        const target = random.intRangeAtMost(usize, 1, buf.len - 80);
        while (len < target) {
            switch (random.uintLessThan(u8, 6)) {
                0 => {
                    buf[len] = if (random.boolean()) '[' else '{';
                    len += 1;
                    depth += 1;
                },
                1 => if (depth > 1) {
                    buf[len] = if (random.boolean()) ']' else '}';
                    len += 1;
                    depth -= 1;
                },
                2, 3 => {
                    buf[len] = '"';
                    len += 1;
                    const n = random.uintLessThan(usize, 40);
                    for (0..n) |_| {
                        const pick = "ab{}[]\\\\\\\\ ,:";
                        const c = pick[random.uintLessThan(usize, pick.len)];
                        if (c == '\\') {
                            buf[len] = '\\';
                            buf[len + 1] = if (random.boolean()) '"' else '\\';
                            len += 2;
                        } else {
                            buf[len] = c;
                            len += 1;
                        }
                    }
                    buf[len] = '"';
                    len += 1;
                },
                else => {
                    buf[len] = if (random.boolean()) ',' else ' ';
                    len += 1;
                },
            }
        }
        while (depth > 0) : (depth -= 1) {
            buf[len] = ']';
            len += 1;
        }
        const trailing = random.uintLessThan(usize, 3);
        for (0..trailing) |_| {
            buf[len] = ']';
            len += 1;
        }
        const src = buf[0..len];
        const want = reference.skip(src, 0);
        const got = skipContainer(src, 0) catch null;
        try std.testing.expectEqual(want, got);
    }
}
