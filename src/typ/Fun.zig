const std = @import("std");

const Typ = @import("mod.zig").Typ;

params: []const Typ,
ret_typ: *const Typ,

pub fn resolve(self: @This(), resolve_map: std.StringHashMap(Typ)) error{OutOfMemory}!@This() {
    const params = try Typ.memo.alloc(self.params.len);
    for (params, self.params) |*target, param| {
        target.* = try param.resolve(resolve_map);
    }
    const ret_typ = try self.ret_typ.resolve(resolve_map);
    const ptr = try Typ.memo.box(ret_typ);
    return .{
        .params = try Typ.memo.save(params),
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

pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
    for (self.params) |param| {
        param.hashIn(hasher);
    }
    self.ret_typ.hashIn(hasher);
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    try writer.writeAll("fn(");
    if (self.params.len != 0) {
        try self.params[0].format(writer);
        for (self.params[1..]) |param| {
            try writer.print(", {f}", .{param});
        }
    }
    try writer.print(") {f}", .{self.ret_typ});
}
