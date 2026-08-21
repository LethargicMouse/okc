const std = @import("std");

const Ast = @import("Ast.zig");

pub const Typ = union(enum) {
    const HashContext = struct {
        pub fn hash(_: HashContext, typ: Typ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            typ.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(_: HashContext, a: Typ, b: Typ) bool {
            if (@intFromEnum(a) != @intFromEnum(b)) {
                return false;
            }
            switch (a) {
                .name => |aname| return std.mem.eql(u8, aname, b.name),
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

    name: []const u8,
    ptr: *const Typ,
    array: Array,
    i1,
    i8,
    i32,
    i64,
    void,

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (typ) {
            .name => |name| try writer.print("%{s}", .{name}),
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
            .name => |name| hasher.update(name),
            .ptr => |inner| {
                hasher.update(&.{0});
                inner.hashIn(hasher);
            },
            .array => |array| {
                hasher.update(&.{1});
                hasher.update(array.len);
                array.typ.hashIn(hasher);
            },
            .i1 => hasher.update(&.{2}),
            .i8 => hasher.update(&.{3}),
            .i32 => hasher.update(&.{4}),
            .i64 => hasher.update(&.{5}),
            .void => hasher.update(&.{6}),
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
        .name => |name| return .{ .name = name },
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
