const std = @import("std");

pub fn SliceHashMap(K: type, V: type) type {
    return std.HashMap([]const K, V, Context(K), std.hash_map.default_max_load_percentage);
}

fn Context(K: type) type {
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
