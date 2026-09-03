const std = @import("std");

const Ast = @import("Ast.zig");
const HashContext = @import("hash_context.zig").HashContext;

pub const Typ = union(enum) {
    pub const Array = struct {
        len: []const u8,
        typ: *const Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
    };

    pub const Slice = struct {
        typ: *const Typ,
        mutable: bool,
    };

    pub const Prime = enum {
        u8,
        i32,
        u32,
        u64,
        bool,
        void,

        pub fn isNumber(prime: Prime) bool {
            switch (prime) {
                .i32, .u8, .u32, .u64 => return true,
                .bool, .void => return false,
            }
        }
    };

    pub const Ptr = struct {
        typ: *const Typ,
        mutable: bool,
    };

    prime: Prime,
    name: Name,
    slice: Slice,
    ptr: Ptr,
    array: Array,

    pub fn fromName(name: []const u8) Typ {
        if (std.meta.stringToEnum(Prime, name)) |prime| {
            return .{ .prime = prime };
        }
        return .{ .name = .{ .name = name } };
    }

    pub fn isVoid(typ: Typ) bool {
        return typ == .prime and typ.prime == .void;
    }

    pub fn eql(a: Typ, b: Typ) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) {
            return false;
        }
        switch (a) {
            .name => |aname| {
                if (!std.mem.eql(u8, aname.name, b.name.name)) {
                    return false;
                }
                for (aname.generics, b.name.generics) |ag, bg| {
                    if (!ag.eql(bg)) {
                        return false;
                    }
                }
                return true;
            },
            .prime => |aprime| return aprime == b.prime,
            .slice => |aslice| return aslice.typ == b.slice.typ and
                aslice.mutable == b.slice.mutable,
            .ptr => |aptr| return aptr.typ == b.ptr.typ and
                aptr.mutable == b.ptr.mutable,
            .array => |arr| return arr.typ == b.array.typ and
                std.mem.eql(u8, arr.len, b.array.len),
        }
    }

    pub fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        switch (typ) {
            .name => |name| {
                hasher.update(&.{0});
                hasher.update(name.name);
                for (name.generics) |generic| {
                    generic.hashIn(hasher);
                }
            },
            .ptr => |ptr| {
                hasher.update(&.{1});
                hasher.update(std.mem.asBytes(&ptr));
            },
            .array => |array| {
                hasher.update(&.{2});
                hasher.update(array.len);
                hasher.update(std.mem.asBytes(&array.typ));
            },
            .slice => |slice| {
                hasher.update(&.{3});
                hasher.update(std.mem.asBytes(&slice));
            },
            .prime => |prime| {
                hasher.update(&.{ 4, @intFromEnum(prime) });
            },
        }
    }
};

const Memo = std.HashMap(
    Typ,
    *const Typ,
    HashContext(Typ),
    std.hash_map.default_max_load_percentage,
);

const AstTyps = @This();

arena: std.heap.ArenaAllocator,
memo: Memo,

pub fn init(gpa: std.mem.Allocator) AstTyps {
    const arena = std.heap.ArenaAllocator.init(gpa);
    const memo = Memo.init(arena.child_allocator);
    return .{
        .arena = arena,
        .memo = memo,
    };
}

pub fn makeTyp(typs: *AstTyps, typ: Ast.Typ) !Typ {
    switch (typ) {
        .slice => |inner| {
            const new = try typs.makeTyp(inner.typ);
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

pub fn box(typs: *AstTyps, typ: Typ) !*const Typ {
    if (typs.memo.get(typ)) |res| {
        return res;
    }
    const res = try typs.arena.allocator().create(Typ);
    res.* = typ;
    try typs.memo.put(typ, res);
    return res;
}

pub fn deinit(typs: *AstTyps) void {
    typs.arena.deinit();
    typs.memo.deinit();
}
