const std = @import("std");

const Ast = @import("Ast.zig");
const Memo = @import("memo.zig").Memo;

pub const Typ = union(enum) {
    prime: Ast.Typ.Prime,
    name: Name,
    fun: Fun,
    ptr: Ptr,
    slice: Slice,
    array: Array,
    lazy: *Typ,
    any,
    err,

    pub const Array = struct {
        len: u64,
        typ: *const Typ,
    };

    pub const Name = struct {
        name: []const u8,
        generics: []const Typ = &.{},
    };

    pub const Ptr = struct {
        typ: *const Typ,
        mutable: bool,
    };

    pub const Slice = struct {
        typ: *const Typ,
        mutable: bool,
    };

    pub const Fun = struct {
        params: []const Typ,
        ret_typ: *const Typ,
    };

    pub const Resolver = struct {
        memo: *Memo(Typ),
        map: std.StringHashMap(Typ),

        pub fn init(gpa: std.mem.Allocator, memo: *Memo(Typ)) Resolver {
            return .{
                .memo = memo,
                .map = .init(gpa),
            };
        }

        pub fn resolve(resolver: *Resolver, typ: Typ) !Typ {
            switch (typ) {
                .name => |name| {
                    if (resolver.map.get(name.name)) |resolved| {
                        return resolved;
                    }
                    const generics = try resolver.memo.arena.allocator().alloc(Typ, name.generics.len);
                    for (generics, name.generics) |*target, generic| {
                        target.* = try resolver.resolve(generic);
                    }
                    return .{ .name = .{
                        .name = name.name,
                        .generics = generics,
                    } };
                },
                .fun => |fun| {
                    const params = try resolver.memo.arena.allocator().alloc(Typ, fun.params.len);
                    for (params, fun.params) |*target, param| {
                        target.* = try resolver.resolve(param);
                    }
                    const ret_typ = try resolver.resolve(fun.ret_typ.*);
                    const ptr = try resolver.memo.box(ret_typ);
                    return .{ .fun = .{
                        .params = params,
                        .ret_typ = ptr,
                    } };
                },
                .slice => |slice| {
                    const new = try resolver.resolve(slice.typ.*);
                    const ptr = try resolver.memo.box(new);
                    return .{ .slice = .{
                        .typ = ptr,
                        .mutable = slice.mutable,
                    } };
                },
                .ptr => |ptr| {
                    const new = try resolver.resolve(ptr.typ.*);
                    const new_ptr = try resolver.memo.box(new);
                    return .{ .ptr = .{
                        .typ = new_ptr,
                        .mutable = ptr.mutable,
                    } };
                },
                .array => |array| {
                    const new = try resolver.resolve(array.typ.*);
                    const new_ptr = try resolver.memo.box(new);
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

    pub fn eql(a: Typ, b: Typ) bool {
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
                    if (!atyp.eql(btyp)) {
                        return false;
                    }
                }
                return true;
            },
            .fun => |fun| {
                if (fun.ret_typ != b.fun.ret_typ) {
                    return false;
                }
                for (fun.params, b.fun.params) |ap, bp| {
                    if (!ap.eql(bp)) {
                        return false;
                    }
                }
                return true;
            },
            .slice => |aslice| return aslice.typ == b.slice.typ and
                aslice.mutable == b.slice.mutable,
            .ptr => |aptr| return aptr.typ == b.ptr.typ and
                aptr.mutable == b.ptr.mutable,
            .array => |arr| {
                if (arr.len == b.array.len) {
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

    pub fn named(name: []const u8) Typ {
        return .{ .name = .{ .name = name } };
    }

    pub fn hashIn(typ: Typ, hasher: *std.hash.Wyhash) void {
        hasher.update(&.{@intFromEnum(typ)});
        switch (typ) {
            .prime => |prime| hasher.update(&.{@intFromEnum(prime)}),
            .name => |name| {
                hasher.update(name.name);
                // `name.name` determines number of `name.generics`
                for (name.generics) |gen| {
                    gen.hashIn(hasher);
                }
            },
            .fun => |fun| {
                for (fun.params) |param| {
                    param.hashIn(hasher);
                }
                fun.ret_typ.hashIn(hasher);
            },
            .ptr => |inner| hasher.update(std.mem.asBytes(&inner)),
            .array => |array| hasher.update(std.mem.asBytes(&array)),
            // pointers in lazy types are not memoized
            // but we need to discriminate lazy types by pointers
            // as they are unique type variables
            .lazy => |inner| hasher.update(std.mem.asBytes(&inner)),
            .slice => |slice| hasher.update(std.mem.asBytes(&slice)),
            .any, .err => {},
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
            .fun => |fun| {
                try writer.writeAll("fn(");
                if (fun.params.len != 0) {
                    try fun.params[0].format(writer);
                    for (fun.params[1..]) |param| {
                        try writer.print(", {f}", .{param});
                    }
                }
                try writer.print(") {f}", .{fun.ret_typ});
            },
            .ptr => |ptr| if (ptr.mutable) {
                try writer.print("&mut {f}", .{ptr.typ});
            } else {
                try writer.print("&{f}", .{ptr.typ});
            },
            .array => |array| try writer.print(
                "[{}]{f}",
                .{ array.len, array.typ },
            ),
            .slice => |inner| {
                try writer.writeAll("[]");
                if (inner.mutable) {
                    try writer.writeAll("mut ");
                }
                try inner.typ.format(writer);
            },
            .lazy => |inner| if (show_lazy) {
                try writer.print("{*}<{f}>", .{ inner, inner });
            } else {
                try inner.format(writer);
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
