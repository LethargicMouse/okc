const std = @import("std");

pub fn HashContext(Val: type) type {
    return struct {
        const Self = @This();

        pub fn hash(_: Self, val: Val) u64 {
            var hasher = std.hash.Wyhash.init(0);
            val.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(_: Self, a: Val, b: Val) bool {
            return a.eql(b);
        }
    };
}
