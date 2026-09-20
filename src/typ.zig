const std = @import("std");

const Ast = @import("Ast.zig");
const Memo = @import("memo.zig").Memo;
const Resolver = @import("resolver.zig").Resolver(Typ);
const typ_kinds = @import("typ_kinds.zig");

pub const Typ = union(enum) {
    prime: Ast.Typ.Prime,
    name: Name,
    fun: Fun,
    ptr: Ptr,
    slice: Slice,
    array: Array,
    lazy: *Typ,
    any,
    int,
    err,

    pub const Array = typ_kinds.Array(Typ);
    pub const Name = typ_kinds.Name(Typ);
    pub const Ptr = typ_kinds.Ptr(Typ);
    pub const Slice = typ_kinds.Slice(Typ);
    pub const Fun = typ_kinds.Fun(Typ);

    pub fn resolve(typ: Typ, resolver: *Resolver) error{OutOfMemory}!Typ {
        switch (typ) {
            .name => |name| if (resolver.map.get(name.name)) |resolved| {
                return resolved;
            } else {
                return .{ .name = try name.resolve(resolver) };
            },
            .fun => |fun| return .{ .fun = try fun.resolve(resolver) },
            .slice => |slice| return .{ .slice = try slice.resolve(resolver) },
            .ptr => |ptr| return .{ .ptr = try ptr.resolve(resolver) },
            .array => |array| return .{ .array = try array.resolve(resolver) },
            // lazy not resolved cuz I feel so
            .lazy, .any, .err, .prime, .int => return typ,
        }
    }

    const debug_lazies = false;

    pub fn setLazy(lazy: *Typ, typ: Typ) void {
        lazy.* = typ;
        if (debug_lazies) {
            std.debug.print("=> {f}\n", .{Typ{ .lazy = lazy }});
        }
    }

    pub fn eql(a: Typ, b: Typ) bool {
        if (@intFromEnum(a) != @intFromEnum(b)) {
            return false;
        }
        return switch (a) {
            .prime => |aprime| aprime == b.prime,
            .name => |aname| aname.eql(b.name),
            .fun => |afun| afun.eql(b.fun),
            .slice => |aslice| aslice.eql(b.slice),
            .ptr => |aptr| aptr.eql(b.ptr),
            .array => |arr| arr.eql(b.array),
            // pointers in lazy types are not memoized
            // but we need to discriminate lazy types by pointers
            // as they are unique type variables
            .lazy => |aptr| aptr == b.lazy,
            .any, .err, .int => true,
        };
    }

    pub fn named(name: []const u8) Typ {
        return .{ .name = .{ .name = name } };
    }

    pub fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        hasher.update(&.{@intFromEnum(typ)});
        switch (typ) {
            .prime => |prime| prime.hashIn(hasher),
            .name => |name| name.hashIn(hasher),
            .fun => |fun| fun.hashIn(hasher),
            .ptr => |ptr| ptr.hashIn(hasher),
            .array => |array| array.hashIn(hasher),
            // pointers in lazy types are not memoized
            // but we need to discriminate lazy types by pointers
            // as they are unique type variables
            .lazy => |inner| hasher.update(std.mem.asBytes(&inner)),
            .slice => |slice| slice.hashIn(hasher),
            .any, .err, .int => {},
        }
    }

    pub fn format(typ: Typ, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const show_lazy = true;
        switch (typ) {
            .prime => |prime| try prime.format(writer),
            .name => |name| try name.format(writer),
            .fun => |fun| try fun.format(writer),
            .ptr => |ptr| try ptr.format(writer),
            .array => |array| try array.format(writer),
            .slice => |slice| try slice.format(writer),
            .lazy => |inner| if (show_lazy) {
                try writer.print("@{x}<{f}>", .{ @intFromPtr(inner) & 0xffff, inner });
            } else {
                try inner.format(writer);
            },
            .err => try writer.writeAll("<err>"),
            .any => try writer.writeAll("_"),
            .int => try writer.writeAll("<int>"),
        }
    }

    pub fn isNumber(typ: Typ) bool {
        switch (typ) {
            .prime => |prime| return prime.isNumber(),
            .err, .int => return true,
            .lazy => |inner| return inner.isNumber(),
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

    pub fn shorten(typ: *Typ) *Typ {
        if (typ.* == .lazy) {
            typ.lazy = typ.lazy.shorten();
            if (debug_lazies) {
                std.debug.print("=> {f}\n", .{typ});
            }
            return typ.lazy;
        } else {
            return typ;
        }
    }
};
