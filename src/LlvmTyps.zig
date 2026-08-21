const std = @import("std");

const Ast = @import("Ast.zig");

pub const Typ = union(enum) {
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
};

const LlvmTyps = @This();

arena: std.heap.ArenaAllocator,

pub fn init(gpa: std.mem.Allocator) LlvmTyps {
    const arena = std.heap.ArenaAllocator.init(gpa);
    return .{
        .arena = arena,
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
    const res = try typs.arena.allocator().create(Typ);
    res.* = typ;
    return res;
}

pub fn deinit(typs: *LlvmTyps) void {
    typs.arena.deinit();
}
