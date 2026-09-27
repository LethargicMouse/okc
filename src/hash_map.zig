const std = @import("std");

fn HashContext(K: type) type {
    return struct {
        const Self = @This();

        pub fn hash(_: Self, key: K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            key.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(_: Self, a: K, b: K) bool {
            return a.eql(b);
        }
    };
}

pub fn HashMap(K: type, V: type) type {
    return std.HashMap(K, V, HashContext(K), std.hash_map.default_max_load_percentage);
}
