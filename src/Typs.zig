const std = @import("std");

const Ast = @import("Ast.zig");

pub const Typ = union(enum) {
    const HashContext = struct {
        pub fn hash(_: HashContext, typ: Typ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            typ.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(ctx: HashContext, a: Typ, b: Typ) bool {
            if (@intFromEnum(a) != @intFromEnum(b)) {
                return false;
            }
            switch (a) {
                .prime => |aprime| return aprime == b.prime,
                .name => |aname| return std.mem.eql(u8, aname, b.name),
                .ptr => |aptr| return ctx.eql(aptr.*, b.ptr.*),
                .mut_ptr => |aptr| return ctx.eql(aptr.*, b.mut_ptr.*),
                .array => |arr| {
                    if (std.mem.eql(u8, arr.len, b.array.len)) {
                        return ctx.eql(arr.typ.*, b.array.typ.*);
                    }
                    return false;
                },
                .lazy => |aptr| return aptr == b.lazy,
                .int, .any, .err => return true,
            }
        }
    };

    pub const Array = struct {
        len: []const u8,
        typ: *const Typ,
    };

    prime: Ast.Prime,
    name: []const u8,
    ptr: *const Typ,
    mut_ptr: *const Typ,
    array: Array,
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
            // lazy type is determined by its pointer.
            // e.g we need to discriminate between one @lazy<<any>> and other @lazy<<any>>
            .lazy => |inner| {
                hasher.update(&.{4});
                // updating on bytes of a pointer
                hasher.update(std.mem.asBytes(&inner));
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

const Memo = std.HashMap(Typ, *const Typ, Typ.HashContext, std.hash_map.default_max_load_percentage);

const Typs = @This();

arena: std.heap.ArenaAllocator,
memo: Memo,

pub fn init(gpa: std.mem.Allocator) Typs {
    const arena = std.heap.ArenaAllocator.init(gpa);
    const memo = Memo.init(gpa);
    return .{
        .arena = arena,
        .memo = memo,
    };
}

pub fn makeLazy(typs: *Typs) !*Typ {
    // not calling `box` because we need a new pointer
    // while `box` will memoize
    // and will always give the same pointer to `any`
    const lazy = try typs.arena.allocator().create(Typ);
    lazy.* = .any;
    return lazy;
}

pub fn deinit(typs: *Typs) void {
    typs.arena.deinit();
    typs.memo.deinit();
    typs.* = undefined;
}

pub fn makeTyp(typs: *Typs, typ: Ast.Typ) !Typ {
    switch (typ) {
        .mut_ptr => |inner| {
            const inner_typ = try typs.makeTyp(inner.*);
            const ptr = try typs.box(inner_typ);
            return .{ .mut_ptr = ptr };
        },
        .prime => |prime| return .{ .prime = prime },
        .name => |name| return .{ .name = name },
        .ptr => |inner| {
            const inner_typ = try typs.makeTyp(inner.*);
            const ptr = try typs.box(inner_typ);
            return .{ .ptr = ptr };
        },
        .array => |array| {
            const inner_typ = try typs.makeTyp(array.typ);
            const ptr = try typs.box(inner_typ);
            return .{ .array = .{
                .len = array.len,
                .typ = ptr,
            } };
        },
    }
}

pub fn box(typs: *Typs, typ: Typ) !*const Typ {
    if (typs.memo.get(typ)) |res| {
        return res;
    }
    const res = try typs.arena.allocator().create(Typ);
    res.* = typ;
    try typs.memo.put(typ, res);
    return res;
}
