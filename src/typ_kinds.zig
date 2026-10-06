const std = @import("std");
const Location = @import("Location.zig");

const Resolver = @import("resolver.zig").Resolver;

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
