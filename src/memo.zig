const std = @import("std");

const hash_map = @import("hash_map.zig");

pub fn Memo(T: type) type {
    return struct {
        const Self = @This();

        arena: *std.heap.ArenaAllocator,
        map: hash_map.PtrHashMap(T, void),
        slice_map: hash_map.SliceHashMap(T, void),

        pub fn init(arena: *std.heap.ArenaAllocator) Self {
            return .{
                .arena = arena,
                .map = .init(arena.child_allocator),
                .slice_map = .init(arena.child_allocator),
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
            const ptr = try self.arena.allocator().create(T);
            ptr.* = val;
            try self.map.put(ptr, {});
            return ptr;
        }

        pub fn save(self: *Self, slice: []const T) error{OutOfMemory}![]const T {
            if (self.slice_map.getKey(slice)) |res| {
                return res;
            }
            const res = try self.arena.allocator().alloc(T, slice.len);
            @memcpy(res, slice);
            try self.slice_map.put(res, {});
            return res;
        }

        pub fn alloc(self: Self, len: usize) error{OutOfMemory}![]T {
            return self.slice_map.allocator.alloc(T, len);
        }

        pub fn free(self: Self, slice: []const T) void {
            self.slice_map.allocator.free(slice);
        }
    };
}
