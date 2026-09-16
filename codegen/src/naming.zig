//! Maps GraphQL names onto Elixir names.
//!
//! `underscore` and `camelize` are byte-for-byte ports of Elixir's
//! `Macro.underscore/1` and `Macro.camelize/1`, because generated file, module
//! and function names must match the Elixir generator exactly.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Module name for a GraphQL type, e.g. `CacheVolume` -> `Dagger.CacheVolume`.
pub fn module(a: Allocator, name: []const u8) ![]const u8 {
    const n = if (std.mem.eql(u8, name, "Query")) "Client" else name;
    var out: std.ArrayList(u8) = try .initCapacity(a, n.len + 7);
    out.appendSliceAssumeCapacity("Dagger.");
    try camelizeInto(a, &out, n);
    return out.items;
}

/// Variable (and file) name for a GraphQL type, e.g. `CacheVolume` -> `cache_volume`.
pub fn variable(a: Allocator, name: []const u8) ![]const u8 {
    return underscore(a, if (std.mem.eql(u8, name, "Query")) "Client" else name);
}

/// Function name for a GraphQL field, e.g. `withEnvVariable` -> `with_env_variable`.
pub fn function(a: Allocator, name: []const u8) ![]const u8 {
    const folded = try normalizeAcronym(a, name);
    const escaped = if (isReserved(folded)) try std.mem.concat(a, u8, &.{ folded, "_" }) else folded;
    const underscored = try underscore(a, escaped);
    // Elixir spells predicates `foo?`, not `is_foo`.
    if (std.mem.startsWith(u8, underscored, "is_")) {
        return std.mem.concat(a, u8, &.{ underscored[3..], "?" });
    }
    return underscored;
}

const reserved_words = [_][]const u8{
    "true", "false", "nil",   "when", "and",    "or",    "not", "in",
    "fn",   "do",    "end",   "catch", "rescue", "after", "else",
};

fn isReserved(name: []const u8) bool {
    for (reserved_words) |word| if (std.mem.eql(u8, name, word)) return true;
    return false;
}

fn isUpper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

fn isLower(c: u8) bool {
    return c >= 'a' and c <= 'z';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn toLower(c: u8) u8 {
    return if (isUpper(c)) c + 32 else c;
}

fn toUpper(c: u8) u8 {
    return if (isLower(c)) c - 32 else c;
}

/// Fold a pluralised acronym (`GPUs`) down to one capital (`Gpus`), i.e.
/// `Regex.replace(~r/[A-Z]{2,}s(?![a-z])/, ...)`.
fn normalizeAcronym(a: Allocator, name: []const u8) ![]const u8 {
    var out: ?std.ArrayList(u8) = null;
    var copied: usize = 0;
    var i: usize = 0;
    while (i < name.len) {
        var run: usize = 0;
        while (i + run < name.len and isUpper(name[i + run])) run += 1;
        const s = i + run;
        const matched = run >= 2 and s < name.len and name[s] == 's' and
            !(s + 1 < name.len and isLower(name[s + 1]));
        if (!matched) {
            i += 1;
            continue;
        }
        if (out == null) out = try .initCapacity(a, name.len);
        try out.?.appendSlice(a, name[copied..i]);
        try out.?.append(a, name[i]);
        for (name[i + 1 .. s + 1]) |c| try out.?.append(a, toLower(c));
        i = s + 1;
        copied = i;
    }
    var result = out orelse return name;
    try result.appendSlice(a, name[copied..]);
    return result.items;
}

/// Port of `Macro.underscore/1` for binaries.
pub fn underscore(a: Allocator, name: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = try .initCapacity(a, name.len + 8);
    try underscoreInto(a, &out, name);
    return out.items;
}

fn underscoreInto(a: Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    if (s.len == 0) return;
    try out.append(a, toLower(s[0]));
    var prev = s[0];
    var i: usize = 1;
    while (i < s.len) {
        const h = s[i];
        if (i + 1 < s.len and isUpper(h)) {
            const t = s[i + 1];
            if (!isUpper(t) and !isDigit(t) and t != '.' and t != '_') {
                try out.appendSlice(a, &.{ '_', toLower(h), t });
                prev = t;
                i += 2;
                continue;
            }
        }
        if (isUpper(h) and !isUpper(prev) and prev != '_') {
            try out.appendSlice(a, &.{ '_', toLower(h) });
        } else if (h == '.') {
            try out.append(a, '/');
            return underscoreInto(a, out, s[i + 1 ..]);
        } else {
            try out.append(a, toLower(h));
        }
        prev = h;
        i += 1;
    }
}

/// Port of `Macro.camelize/1`.
fn camelizeInto(a: Allocator, out: *std.ArrayList(u8), input: []const u8) !void {
    var s = input;
    while (s.len > 0 and s[0] == '_') s = s[1..];
    if (s.len == 0) return;
    try out.append(a, toUpper(s[0]));
    var i: usize = 1;
    while (i < s.len) {
        const c = s[i];
        if (c == '_') {
            if (i + 1 == s.len) return;
            const h = s[i + 1];
            if (h == '_') {
                i += 1;
                continue;
            } else if (isLower(h)) {
                try out.append(a, toUpper(h));
                i += 2;
                continue;
            } else if (isDigit(h)) {
                try out.append(a, h);
                i += 2;
                continue;
            }
            try out.append(a, c);
            i += 1;
        } else if (c == '/') {
            try out.append(a, '.');
            return camelizeInto(a, out, s[i + 1 ..]);
        } else {
            try out.append(a, c);
            i += 1;
        }
    }
}

/// Rewrite backticked API references in documentation to their Elixir
/// spelling. Matches are found in the original text and each one is then
/// replaced everywhere in the accumulated text, as `Naming.doc/1` does.
pub fn doc(a: Allocator, text: []const u8) ![]const u8 {
    var acc = text;
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, i, '`')) |tick| {
        i = tick;
        var j = i + 1;
        while (j < text.len and std.ascii.isAlphanumeric(text[j])) j += 1;
        if (j == i + 1 or j >= text.len or text[j] != '`') {
            i += 1;
            continue;
        }
        const api = text[i + 1 .. j];
        const renamed = try function(a, api);
        if (!std.mem.eql(u8, renamed, api)) {
            const needle = text[i .. j + 1];
            const replacement = try std.mem.concat(a, u8, &.{ "`", renamed, "`" });
            acc = try std.mem.replaceOwned(u8, a, acc, needle, replacement);
        }
        i = j + 1;
    }
    return acc;
}

fn expectName(comptime f: anytype, input: []const u8, want: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings(want, try f(arena.allocator(), input));
}

test "module names keep the schema's own casing" {
    try expectName(module, "Container", "Dagger.Container");
    try expectName(module, "BuildArg", "Dagger.BuildArg");
    try expectName(module, "SDKConfig", "Dagger.SDKConfig");
    try expectName(module, "LLMTokenUsage", "Dagger.LLMTokenUsage");
    try expectName(module, "HTTPState", "Dagger.HTTPState");
}

test "the GraphQL root is exposed as the client" {
    try expectName(module, "Query", "Dagger.Client");
    try expectName(variable, "Query", "client");
}

test "variable names" {
    try expectName(variable, "Container", "container");
    try expectName(variable, "CacheVolume", "cache_volume");
}

test "function names" {
    try expectName(function, "withEnvVariable", "with_env_variable");
    try expectName(function, "loadSecretFromID", "load_secret_from_id");
}

test "a pluralised acronym stays in one piece" {
    // Without this, `Macro.underscore/1` yields "experimental_with_all_gp_us".
    // See dagger/dagger#6310.
    try expectName(function, "experimentalWithAllGPUs", "experimental_with_all_gpus");
    try expectName(function, "listIDs", "list_ids");
}

test "an acronym followed by a word is left alone" {
    try expectName(function, "withVCSGeneratedPaths", "with_vcs_generated_paths");
    try expectName(function, "asHTTPState", "as_http_state");
    try expectName(function, "withMCPServer", "with_mcp_server");
    try expectName(function, "insecureSkipTLSVerify", "insecure_skip_tls_verify");
    try expectName(function, "experimentalWithGPU", "experimental_with_gpu");
    try expectName(function, "EStarGZ", "e_star_gz");
}

test "reserved words are escaped" {
    try expectName(function, "true", "true_");
    try expectName(function, "do", "do_");
}

test "predicates are spelled the Elixir way" {
    try expectName(function, "isTerminal", "terminal?");
}

test "docs rewrite API references" {
    try expectName(doc, "A simple document", "A simple document");
    try expectName(doc, "A simple document that reference to `someFunction`", "A simple document that reference to `some_function`");
    try expectName(doc, "see `withExec` twice `withExec`", "see `with_exec` twice `with_exec`");
}
