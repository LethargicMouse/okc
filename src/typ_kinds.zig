const std = @import("std");
const Location = @import("Location.zig");

const Resolver = @import("resolver.zig").Resolver;

pub fn Ptr(Typ: type) type {
    return struct {
        typ: *const Typ,
        mutable: bool,

        pub fn resolve(ptr: @This(), resolver: *Resolver(Typ)) error{OutOfMemory}!@This() {
            const new = try ptr.typ.resolve(resolver);
            const new_ptr = try resolver.memo.box(new);
            return .{
                .typ = new_ptr,
                .mutable = ptr.mutable,
            };
        }

        pub fn eql(a: @This(), b: @This()) bool {
            return a.typ == b.typ and a.mutable == b.mutable;
        }

        pub fn hashIn(ptr: @This(), hasher: *std.hash.Wyhash) void {
            hasher.update(std.mem.asBytes(&ptr.typ));
            hasher.update(&.{@intFromBool(ptr.mutable)});
        }

        pub fn format(ptr: @This(), writer: *std.Io.Writer) !void {
            if (ptr.mutable) {
                try writer.print("&mut {f}", .{ptr.typ});
            } else {
                try writer.print("&{f}", .{ptr.typ});
            }
        }
    };
}

pub fn Slice(Typ: type) type {
    return struct {
        typ: *const Typ,
        mutable: bool,

        pub fn resolve(slice: @This(), resolver: *Resolver(Typ)) error{OutOfMemory}!@This() {
            const new = try slice.typ.resolve(resolver);
            const ptr = try resolver.memo.box(new);
            return .{
                .typ = ptr,
                .mutable = slice.mutable,
            };
        }

        pub fn eql(a: @This(), b: @This()) bool {
            return a.typ == b.typ and a.mutable == b.mutable;
        }

        pub fn hashIn(slice: @This(), hasher: *std.hash.Wyhash) void {
            hasher.update(std.mem.asBytes(&slice.typ));
            hasher.update(&.{@intFromBool(slice.mutable)});
        }

        pub fn format(slice: @This(), writer: *std.Io.Writer) !void {
            try writer.writeAll("[]");
            if (slice.mutable) {
                try writer.writeAll("mut ");
            }
            try slice.typ.format(writer);
        }
    };
}

pub fn Fun(Typ: type) type {
    return struct {
        params: []const Typ,
        ret_typ: *const Typ,

        pub fn resolve(fun: @This(), resolver: *Resolver(Typ)) error{OutOfMemory}!@This() {
            const params = try resolver.memo.arena.allocator().alloc(Typ, fun.params.len);
            for (params, fun.params) |*target, param| {
                target.* = try param.resolve(resolver);
            }
            const ret_typ = try fun.ret_typ.resolve(resolver);
            const ptr = try resolver.memo.box(ret_typ);
            return .{
                .params = params,
                .ret_typ = ptr,
            };
        }

        pub fn eql(a: @This(), b: @This()) bool {
            if (a.ret_typ != b.ret_typ) {
                return false;
            }
            for (a.params, b.params) |ap, bp| {
                if (!ap.eql(bp)) {
                    return false;
                }
            }
            return true;
        }

        pub fn hashIn(fun: @This(), hasher: *std.hash.Wyhash) void {
            for (fun.params) |param| {
                param.hashIn(hasher);
            }
            fun.ret_typ.hashIn(hasher);
        }

        pub fn format(fun: @This(), writer: *std.Io.Writer) !void {
            try writer.writeAll("fn(");
            if (fun.params.len != 0) {
                try fun.params[0].format(writer);
                for (fun.params[1..]) |param| {
                    try writer.print(", {f}", .{param});
                }
            }
            try writer.print(") {f}", .{fun.ret_typ});
        }
    };
}
