const std = @import("std");

const Ast = @import("Ast/mod.zig");
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
        switch (typ) {
            .prime => |prime| try prime.format(writer),
            .name => |name| try name.format(writer),
            .fun => |fun| try fun.format(writer),
            .ptr => |ptr| try ptr.format(writer),
            .array => |array| try array.format(writer),
            .slice => |slice| try slice.format(writer),
            .lazy => |inner| if (debug_lazies) {
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
        if (res == .lazy) {
            res.lazy = res.lazy.shorten();
        }
        // may be 2 or 1 lazies on the way
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

    pub const debug_unify = false;

    pub fn unify(a: Typ, b: Typ, active: bool) ?Typ {
        if (debug_unify) {
            std.debug.print("unify {f} vs {f}\n", .{ a, b });
        }
        if (a == .err or b == .err) {
            return .err;
        }
        if (a == .any) {
            return b;
        }
        if (b == .any) {
            return a;
        }
        if (a == .lazy and b == .lazy) {
            const sa = a.lazy.shorten();
            const sb = b.lazy.shorten();
            if (sa != sb) {
                const typ = sa.unify(sb.*, active) orelse return null;
                sa.setLazy(typ);
                sb.setLazy(.{ .lazy = sa });
            }
            return .{ .lazy = sa };
        }
        if (a == .lazy) {
            const res = a.lazy.unify(b, active) orelse return null;
            if (active) {
                a.lazy.setLazy(res);
            }
            return a;
        }
        if (b == .lazy) {
            const res = a.unify(b.lazy.*, active) orelse return null;
            if (active) {
                b.lazy.setLazy(res);
            }
            return b;
        }
        if (a == .slice and b == .ptr and b.ptr.typ.* == .array and
            a.slice.mutable == b.ptr.mutable)
        {
            if (a.slice.typ != b.ptr.typ.array.typ) {
                _ = a.slice.typ.unify(b.ptr.typ.array.typ.*, active) orelse return null;
            }
            return a;
        }
        if (a == .int and b.isNumber()) {
            return b;
        }
        if (b == .int and a.isNumber()) {
            return a;
        }
        if (@intFromEnum(a) != @intFromEnum(b)) {
            return null;
        }
        switch (a) {
            .prime => |aprime| if (aprime == b.prime) {
                return b;
            } else {
                return null;
            },
            .name => |aname| {
                if (!std.mem.eql(u8, aname.name, b.name.name)) {
                    return null;
                }
                for (aname.generics, b.name.generics) |ag, bg| {
                    _ = ag.unify(bg, active) orelse return null;
                }
                return b;
            },
            .fun => |fun| {
                if (fun.ret_typ != b.fun.ret_typ) {
                    _ = fun.ret_typ.unify(b.fun.ret_typ.*, active) orelse return null;
                }
                for (fun.params, b.fun.params) |ap, bp| {
                    _ = ap.unify(bp, active) orelse return null;
                }
                return a;
            },
            .slice => |aslice| {
                if (aslice.mutable != b.slice.mutable) {
                    return null;
                }
                if (aslice.typ != b.slice.typ) {
                    _ = aslice.typ.unify(b.slice.typ.*, active) orelse return null;
                }
                return a;
            },
            .ptr => |aptr| {
                if (aptr.mutable and !b.ptr.mutable) {
                    return null;
                }
                if (aptr.typ != b.ptr.typ and aptr.typ.unify(b.ptr.typ.*, active) == null) {
                    return null;
                }
                return a;
            },
            .array => |arr| {
                if (arr.len != b.array.len or
                    (arr.typ != b.array.typ and arr.typ.unify(b.array.typ.*, active) == null))
                {
                    return null;
                }
                return a;
            },
            .lazy, .any, .err, .int => unreachable,
        }
    }
};
