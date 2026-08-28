const std = @import("std");

const Ast = @import("Ast.zig");

const Resolver = struct {
    typs: *Typs,
    map: std.StringHashMap(Typ),

    pub fn resolve(resolver: *Resolver, typ: Typ) !Typ {
        switch (typ) {
            .name => |name| {
                if (resolver.map.get(name.name)) |resolved| {
                    return resolved;
                }
                const generics = try resolver.typs.arena.allocator().alloc(Typ, name.generics.len);
                for (generics, name.generics) |*target, generic| {
                    target.* = try resolver.resolve(generic);
                }
                return .{ .name = .{
                    .name = name.name,
                    .generics = generics,
                } };
            },
            .ptr => |ptr| {
                const new = try resolver.resolve(ptr.*);
                const new_ptr = try resolver.typs.box(new);
                return .{ .ptr = new_ptr };
            },
            .mut_ptr => |ptr| {
                const new = try resolver.resolve(ptr.*);
                const new_ptr = try resolver.typs.box(new);
                return .{ .mut_ptr = new_ptr };
            },
            .array => |array| {
                const new = try resolver.resolve(array.typ.*);
                const new_ptr = try resolver.typs.box(new);
                return .{ .array = .{
                    .len = array.len,
                    .typ = new_ptr,
                } };
            },
            // lazy not resolved cuz I feel so
            .lazy, .any, .err, .prime => return typ,
        }
    }
};

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
                .name => |aname| {
                    if (!std.mem.eql(u8, aname.name, b.name.name)) {
                        return false;
                    }
                    for (aname.generics, b.name.generics) |atyp, btyp| {
                        if (!ctx.eql(atyp, btyp)) {
                            return false;
                        }
                    }
                    return true;
                },
                // a == b <=> &a == &b due to memo
                .ptr => |aptr| return aptr == b.ptr,
                // a == b <=> &a == &b due to memo
                .mut_ptr => |aptr| return aptr == b.mut_ptr,
                .array => |arr| {
                    if (std.mem.eql(u8, arr.len, b.array.len)) {
                        // a == b <=> &a == &b due to memo
                        return arr.typ == b.array.typ;
                    }
                    return false;
                },
                // pointers in lazy types are not memoized
                // but we need to discriminate lazy types by pointers
                // as they are unique type variables
                .lazy => |aptr| return aptr == b.lazy,
                .any, .err => return true,
            }
        }
    };

    pub const Array = struct {
        len: []const u8,
        typ: *const Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
    };

    prime: Ast.Prime,
    name: Name,
    ptr: *const Typ,
    mut_ptr: *const Typ,
    array: Array,
    lazy: *Typ,
    any,
    err,

    pub fn named(name: []const u8) Typ {
        return .{ .name = .{ .name = name } };
    }

    fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        switch (typ) {
            .prime => |prime| {
                hasher.update(&.{0});
                hasher.update(&.{@intFromEnum(prime)});
            },
            .name => |name| {
                hasher.update(&.{1});
                hasher.update(name.name);
                // `name.name` determines number of `name.generics`
                for (name.generics) |gen| {
                    gen.hashIn(hasher);
                }
            },
            .ptr => |inner| {
                hasher.update(&.{2});
                // a == b <=> &a == &b due to memo
                hasher.update(std.mem.asBytes(&inner));
            },
            .mut_ptr => |inner| {
                hasher.update(&.{3});
                // a == b <=> &a == &b due to memo
                hasher.update(std.mem.asBytes(&inner));
            },
            .array => |array| {
                hasher.update(&.{4});
                hasher.update(array.len);
                // a == b <=> &a == &b due to memo
                hasher.update(std.mem.asBytes(&array.typ));
            },
            // pointers in lazy types are not memoized
            // but we need to discriminate lazy types by pointers
            // as they are unique type variables
            .lazy => |inner| {
                hasher.update(&.{5});
                hasher.update(std.mem.asBytes(&inner));
            },
            .any => hasher.update(&.{6}),
            .err => hasher.update(&.{7}),
        }
    }

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const show_lazy = false;
        switch (typ) {
            .prime => |prime| try writer.writeAll(@tagName(prime)),
            .name => |name| {
                try writer.writeAll(name.name);
                if (name.generics.len != 0) {
                    try writer.print("<{f}", .{name.generics[0]});
                    for (name.generics[1..]) |generic| {
                        try writer.print(", {f}", .{generic});
                    }
                    try writer.writeByte('>');
                }
            },
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
            .err => try writer.writeAll("<err>"),
            .any => try writer.writeAll("_"),
        }
    }

    pub fn isNumber(typ: Typ) bool {
        switch (typ) {
            .prime => |prime| return prime.isNumber(),
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
        .name => |name| {
            const generics = try typs.arena.allocator().alloc(Typ, name.generics.len);
            for (generics, name.generics) |*target, generic| {
                target.* = try typs.makeTyp(generic);
            }
            return .{ .name = .{
                .name = name.name,
                .generics = generics,
            } };
        },
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

pub fn makeResolver(typs: *Typs, gpa: std.mem.Allocator) Resolver {
    return .{
        .typs = typs,
        .map = .init(gpa),
    };
}
