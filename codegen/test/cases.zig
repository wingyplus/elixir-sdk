//! The snapshot cases: a single introspection type from `fixtures/`, the rest
//! of the schema as the analyzer sees it, and the module expected in
//! `snapshots/<name>.ex`.
//!
//! Each fixture is analyzed on its own, without the field sort the schema-level
//! driver applies, against an index that holds only the types listed here.

const analyzer = @import("codegen").analyzer;

pub const Stub = struct {
    name: []const u8,
    kind: analyzer.Kind,
    enum_values: []const []const u8 = &.{},
};

pub const Case = struct {
    name: []const u8,
    fixture: []const u8,
    index: []const Stub = &.{},
};

const objects = [_]Stub{
    .{ .name = "Directory", .kind = .object },
    .{ .name = "Module", .kind = .object },
    .{ .name = "TypeDef", .kind = .object },
};

pub const all = [_]Case{
    .{ .name = "enums/render-enum", .fixture = "enums/render-enum" },
    .{ .name = "scalars/platform", .fixture = "scalars/platform" },
    .{ .name = "inputs/build-arg", .fixture = "inputs/build-arg" },
    .{ .name = "objects/guarded-args", .fixture = "objects/guarded-args", .index = &.{
        .{ .name = "Directory", .kind = .object },
        .{ .name = "Node", .kind = .interface },
        .{ .name = "CacheSharingMode", .kind = .@"enum", .enum_values = &.{ "SHARED", "PRIVATE", "LOCKED" } },
    } },
    .{ .name = "objects/chain-selection", .fixture = "objects/chain-selection" },
    .{ .name = "objects/list-leaf-nodes", .fixture = "objects/list-leaf-nodes" },
    .{ .name = "objects/execute-leaf-node", .fixture = "objects/execute-leaf-node" },
    .{ .name = "objects/id-arg", .fixture = "objects/id-arg", .index = &objects },
    // `@expectedType` resolves against the index, so an interface stays one...
    .{ .name = "objects/id-arg-interface", .fixture = "objects/id-arg", .index = &.{
        .{ .name = "Directory", .kind = .interface },
    } },
    // ...and a type the index does not know degrades to the permissive guard,
    // never to a match on a struct that may not exist.
    .{ .name = "objects/id-arg-unknown-type", .fixture = "objects/id-arg" },
    .{ .name = "objects/iss-7788", .fixture = "objects/iss-7788" },
    .{ .name = "objects/return-void", .fixture = "objects/return-void" },
    .{ .name = "objects/return-scalar", .fixture = "objects/return-scalar" },
    .{ .name = "objects/return-list-of-enums", .fixture = "objects/return-list-of-enums" },
    .{ .name = "objects/iss-8610", .fixture = "objects/iss-8610", .index = &objects },
    .{ .name = "objects/gen-protocol", .fixture = "objects/gen-protocol", .index = &objects },
    .{ .name = "objects/escape-docs", .fixture = "objects/escape-docs" },
    .{ .name = "objects/experimental", .fixture = "objects/experimental" },
};
