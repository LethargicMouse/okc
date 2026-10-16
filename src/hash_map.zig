const std = @import("std");

pub fn HashMap(K: type, V: type) type {
    return std.HashMap(K, V, Context(K), std.hash_map.default_max_load_percentage);
}

fn Context(K: type) type {
    return struct {
        pub fn hash(_: @This(), key: K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            key.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), a: K, b: K) bool {
            return a.eql(b);
        }
    };
}
