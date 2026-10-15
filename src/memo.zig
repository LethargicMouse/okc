const std = @import("std");

const hash_map = @import("hash_map.zig");
const Module = @import("Module.zig");

pub fn Memo(T: type) type {
    return struct {
        map: hash_map.PtrHashMap(T, void),
        slice_map: hash_map.SliceHashMap(T, void),

        pub fn init(gpa: std.mem.Allocator) @This() {
            return .{
                .map = .init(gpa),
                .slice_map = .init(gpa),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.map.deinit();
            self.slice_map.deinit();
            self.* = undefined;
        }

        pub fn box(self: *@This(), val: T) error{OutOfMemory}!*const T {
            if (self.map.getKey(&val)) |ptr| {
                return ptr;
            }
            const ptr = try Module.arena.create(T);
            ptr.* = val;
            try self.map.put(ptr, {});
            return ptr;
        }

        pub fn save(self: *@This(), slice: []const T) error{OutOfMemory}![]const T {
            if (self.slice_map.getKey(slice)) |res| {
                return res;
            }
            const res = try Module.arena.alloc(T, slice.len);
            @memcpy(res, slice);
            try self.slice_map.put(res, {});
            return res;
        }
    };
}
