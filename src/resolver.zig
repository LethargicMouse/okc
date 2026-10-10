const std = @import("std");

const memo = @import("memo.zig");

pub fn Resolver(T: type) type {
    return struct {
        const Self = @This();
        mem: *memo.Memo(T),
        map: std.StringHashMap(T),
    };
}
