const std = @import("std");

const Ast = @import("Ast.zig");

pub const Typ = union(enum) {
    const HashContext = struct {
        fn hash(_: HashContext, typ: Typ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            typ.hashIn(&hasher);
            return hasher.final();
        }
    };

    pub const Array = struct {
        len: []const u8,
        typ: Typ,
    };

    prime: Ast.Prime,
    name: []const u8,
    ptr: *const Typ,
    mut_ptr: *const Typ,
    array: *const Array,
    lazy: *Typ,
    int,
    any,
    err,

    fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        switch (typ) {
            .prime => |prime| hasher.update(@tagName(prime)),
            .name => |name| hasher.update(name),
            .ptr => |inner| {
                hasher.update(&.{0});
                inner.hashIn(hasher);
            },
            .mut_ptr => |inner| {
                hasher.update(&.{2});
                inner.hashIn(hasher);
            },
            .array => |array| {
                hasher.update(&.{3});
                hasher.update(array.len);
                array.typ.hashIn(hasher);
            },
            .lazy => |inner| {
                hasher.update(&.{4});
                inner.hashIn(hasher);
            },
            .int => hasher.update(&.{5}),
            .any => hasher.update(&.{6}),
            .err => hasher.update(&.{7}),
        }
    }

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const show_lazy = false;
        switch (typ) {
            .prime => |prime| try writer.writeAll(@tagName(prime)),
            .name => |name| try writer.writeAll(name),
            .ptr => |inner| try writer.print("&{f}", .{inner}),
            .mut_ptr => |inner| try writer.print("&mut {f}", .{inner}),
            .array => |array| try writer.print(
                "[{s}]{f}",
                .{ array.len, array.typ },
            ),
            .lazy => |inner| if (show_lazy) {
                try writer.print("@lazy<{f}>", .{inner});
            } else {
                try writer.print("{f}", .{inner});
            },
            .int => try writer.writeAll("<int>"),
            .err => try writer.writeAll("<err>"),
            .any => try writer.writeAll("_"),
        }
    }

    pub fn isNumber(typ: Typ) bool {
        switch (typ) {
            .prime => |prime| return prime.isNumber(),
            .int => return true,
            .err => return true,
            else => return false,
        }
    }

    pub fn normalise(typ: Typ) Typ {
        var res = typ;
        while (res == .lazy) {
            res = res.lazy.*;
        }
        return res;
    }
};

const Typs = @This();

arena: std.heap.ArenaAllocator,

pub fn init(gpa: std.mem.Allocator) Typs {
    const arena = std.heap.ArenaAllocator.init(gpa);
    return .{
        .arena = arena,
    };
}

pub fn clone(typs: *Typs, typ: Typ) !Typ {
    switch (typ) {
        .mut_ptr => |inner| {
            const new = try typs.arena.allocator().create(Typ);
            new.* = try typs.clone(inner.*);
            return .{ .mut_ptr = new };
        },
        .ptr => |inner| {
            const new = try typs.arena.allocator().create(Typ);
            new.* = try typs.clone(inner.*);
            return .{ .ptr = new };
        },
        .array => |array| {
            const new = try typs.arena.allocator().create(Typ.Array);
            new.len = array.len;
            new.typ = try typs.clone(array.typ);
            return .{ .array = new };
        },
        // invariant: everything in lazy is already stored in typs
        .lazy => return typ,
        .name, .prime, .any, .int, .err => return typ,
    }
}

pub fn makeLazy(typs: *Typs) !*Typ {
    const lazy = try typs.arena.allocator().create(Typ);
    lazy.* = .any;
    return lazy;
}

pub fn deinit(typs: Typs) void {
    typs.arena.deinit();
}
