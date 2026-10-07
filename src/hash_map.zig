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

fn PtrHashContext(K: type) type {
    return struct {
        const Self = @This();

        pub fn hash(_: Self, key: *const K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            key.hashIn(&hasher);
            return hasher.final();
        }

        pub fn eql(_: Self, a: *const K, b: *const K) bool {
            return a.eql(b.*);
        }
    };
}

pub fn PtrHashMap(K: type, V: type) type {
    return std.HashMap(*const K, V, PtrHashContext(K), std.hash_map.default_max_load_percentage);
}

fn SliceHashContext(K: type) type {
    return struct {
        const Self = @This();

        pub fn hash(_: Self, keys: []const K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            for (keys) |key| {
                key.hashIn(&hasher);
            }
            return hasher.final();
        }

        pub fn eql(_: Self, as: []const K, bs: []const K) bool {
            for (as, bs) |a, b| {
                if (!a.eql(b)) {
                    return false;
                }
            }
            return true;
        }
    };
}

pub fn SliceHashMap(K: type, V: type) type {
    return std.HashMap([]const K, V, SliceHashContext(K), std.hash_map.default_max_load_percentage);
}
