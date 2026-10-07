const std = @import("std");

const Resolver = @import("../resolver.zig").Resolver;
const Typ = @import("mod.zig").Typ;

const Self = @This();
params: []const Typ,
ret_typ: *const Typ,

pub fn resolve(self: Self, resolver: *Resolver(Typ)) error{OutOfMemory}!Self {
    const params = try resolver.slice_mem.alloc(self.params.len);
    for (params, self.params) |*target, param| {
        target.* = try param.resolve(resolver);
    }
    const ret_typ = try self.ret_typ.resolve(resolver);
    const ptr = try resolver.mem.box(ret_typ);
    return .{
        .params = try resolver.slice_mem.save(params),
        .ret_typ = ptr,
    };
}

pub fn eql(a: Self, b: Self) bool {
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

pub fn hashIn(self: Self, hasher: *std.hash.Wyhash) void {
    for (self.params) |param| {
        param.hashIn(hasher);
    }
    self.ret_typ.hashIn(hasher);
}

pub fn format(self: Self, writer: *std.Io.Writer) !void {
    try writer.writeAll("fn(");
    if (self.params.len != 0) {
        try self.params[0].format(writer);
        for (self.params[1..]) |param| {
            try writer.print(", {f}", .{param});
        }
    }
    try writer.print(") {f}", .{self.ret_typ});
}
