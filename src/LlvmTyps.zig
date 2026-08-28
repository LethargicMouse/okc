const std = @import("std");

const Ast = @import("Ast.zig");

const Resolver = struct {
    typs: *LlvmTyps,
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
            .array => |array| {
                const new = try resolver.resolve(array.typ.*);
                const new_ptr = try resolver.typs.box(new);
                return .{ .array = .{
                    .len = array.len,
                    .typ = new_ptr,
                } };
            },
            .i1, .i8, .i32, .i64, .void => return typ,
        }
    }
};

pub const Typ = union(enum) {
    pub const HashContext = struct {
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
                .name => |aname| {
                    if (!std.mem.eql(u8, aname.name, b.name.name)) {
                        return false;
                    }
                    for (aname.generics, b.name.generics) |ag, bg| {
                        if (!ctx.eql(ag, bg)) {
                            return false;
                        }
                    }
                    return true;
                },
                // a == b <=> &a == &b due to memo
                .ptr => |aptr| return aptr == b.ptr,
                .array => |arr| {
                    if (std.mem.eql(u8, arr.len, b.array.len)) {
                        // a == b <=> &a == &b due to memo
                        return arr.typ == b.array.typ;
                    }
                    return false;
                },
                .i1, .i8, .i32, .i64, .void => return true,
            }
        }
    };

    const Array = struct {
        len: []const u8,
        typ: *const Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
    };

    name: Name,
    ptr: *const Typ,
    array: Array,
    i1,
    i8,
    i32,
    i64,
    void,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .name => |name| {
                try writer.print("%\"{s}", .{name.name});
                if (name.generics.len != 0) {
                    try writer.print("<{f}", .{name.generics[0]});
                    for (name.generics[1..]) |generic| {
                        try writer.print(", {f}", .{generic});
                    }
                    try writer.writeByte('>');
                }
                try writer.writeByte('"');
            },
            .array => |array| try writer.print("[{s} x {f}]", .{ array.len, array.typ }),
            else => try writer.writeAll(@tagName(typ)),
        }
    }

    pub fn fromPrime(prime: Ast.Prime) Typ {
        switch (prime) {
            .i32 => return .i32,
            .u8 => return .i8,
            .u32 => return .i32,
            .u64 => return .i64,
            .bool => return .i1,
            .void => return .void,
        }
    }

    fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        switch (typ) {
            .name => |name| {
                hasher.update(&.{0});
                hasher.update(name.name);
                for (name.generics) |generic| {
                    generic.hashIn(hasher);
                }
            },
            .ptr => |inner| {
                hasher.update(&.{1});
                // a == b <=> &a == &b due to memo
                hasher.update(std.mem.asBytes(&inner));
            },
            .array => |array| {
                hasher.update(&.{2});
                hasher.update(array.len);
                // a == b <=> &a == &b due to memo
                hasher.update(std.mem.asBytes(&array.typ));
            },
            .i1 => hasher.update(&.{3}),
            .i8 => hasher.update(&.{4}),
            .i32 => hasher.update(&.{5}),
            .i64 => hasher.update(&.{6}),
            .void => hasher.update(&.{7}),
        }
    }
};

const Memo = std.HashMap(Typ, *const Typ, Typ.HashContext, std.hash_map.default_max_load_percentage);

const LlvmTyps = @This();

arena: std.heap.ArenaAllocator,
memo: Memo,

pub fn init(gpa: std.mem.Allocator) LlvmTyps {
    const arena = std.heap.ArenaAllocator.init(gpa);
    const memo = Memo.init(gpa);
    return .{
        .arena = arena,
        .memo = memo,
    };
}

pub fn makeTyp(typs: *LlvmTyps, typ: Ast.Typ) !Typ {
    switch (typ) {
        .slice => |inner| {
            const new = try typs.makeTyp(inner.*);
            const generics = try typs.arena.allocator().alloc(Typ, 1);
            generics[0] = new;
            return .{ .name = .{
                .name = "[]",
                .generics = generics,
            } };
        },
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
        .prime => |prime| return Typ.fromPrime(prime),
        .ptr => |ptr| {
            const inner = try typs.makeTyp(ptr.*);
            const new = try typs.box(inner);
            return .{ .ptr = new };
        },
        .mut_ptr => |ptr| {
            const inner = try typs.makeTyp(ptr.*);
            const new = try typs.box(inner);
            return .{ .ptr = new };
        },
        .array => |array| {
            const inner = try typs.makeTyp(array.typ);
            const new = try typs.box(inner);
            return .{ .array = .{
                .len = array.len,
                .typ = new,
            } };
        },
    }
}

pub fn box(typs: *LlvmTyps, typ: Typ) !*const Typ {
    if (typs.memo.get(typ)) |res| {
        return res;
    }
    const res = try typs.arena.allocator().create(Typ);
    res.* = typ;
    try typs.memo.put(typ, res);
    return res;
}

pub fn deinit(typs: *LlvmTyps) void {
    typs.memo.deinit();
    typs.arena.deinit();
}

pub fn makeResolver(typs: *LlvmTyps, gpa: std.mem.Allocator) Resolver {
    return .{
        .typs = typs,
        .map = .init(gpa),
    };
}
