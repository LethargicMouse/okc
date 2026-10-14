const std = @import("std");

const ast = @import("ast/mod.zig");
const hash_map = @import("hash_map.zig");

pub fn Memo(T: type) type {
    return struct {
        const Self = @This();

        map: hash_map.PtrHashMap(T, void),
        slice_map: hash_map.SliceHashMap(T, void),

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{
                .map = .init(gpa),
                .slice_map = .init(gpa),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.slice_map.deinit();
            self.* = undefined;
        }

        pub fn box(self: *Self, val: T) error{OutOfMemory}!*const T {
            if (self.map.getKey(&val)) |ptr| {
                return ptr;
            }
            const ptr = try ast.arena.allocator().create(T);
            ptr.* = val;
            try self.map.put(ptr, {});
            return ptr;
        }

        pub fn save(self: *Self, slice: []const T) error{OutOfMemory}![]const T {
            if (self.slice_map.getKey(slice)) |res| {
                return res;
            }
            const res = try ast.arena.allocator().alloc(T, slice.len);
            @memcpy(res, slice);
            try self.slice_map.put(res, {});
            return res;
        }
    };
}
