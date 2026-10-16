const std = @import("std");

pub fn PtrHashMap(K: type, V: type) type {
    return std.HashMap(*const K, V, Context(K), std.hash_map.default_max_load_percentage);
}

pub fn Context(K: type) type {
    return struct {
        pub fn hash(_: @This(), key: *const K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            key.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(_: @This(), a: *const K, b: *const K) bool {
            return a.eql(b.*);
        }
    };
}
