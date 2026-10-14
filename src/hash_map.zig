const std = @import("std");

fn HashContext(K: type) type {
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

pub fn HashMap(K: type, V: type) type {
    return std.HashMap(K, V, HashContext(K), std.hash_map.default_max_load_percentage);
}

fn PtrHashContext(K: type) type {
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

pub fn PtrHashMap(K: type, V: type) type {
    return std.HashMap(*const K, V, PtrHashContext(K), std.hash_map.default_max_load_percentage);
}

fn SliceHashContext(K: type) type {
    return struct {
        pub fn hash(_: @This(), keys: []const K) u64 {
            var hasher = std.hash.Wyhash.init(0);
            for (keys) |key| {
                key.hashIn(&hasher);
            }
            return hasher.final();
        }

        pub fn eql(_: @This(), as: []const K, bs: []const K) bool {
            if (as.len != bs.len) {
                return false;
            }
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
