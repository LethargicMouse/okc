const std = @import("std");

const okc = @import("okc");

pub fn Memo(T: type) type {
    return struct {
        map: okc.PtrHashMap(T, void),
        slice_map: okc.SliceHashMap(T, void),

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

        pub fn box(self: *@This(), val: T, arena: std.mem.Allocator) error{OutOfMemory}!*const T {
            if (self.map.getKey(&val)) |ptr| {
                return ptr;
            }
            const ptr = try arena.create(T);
            ptr.* = val;
            try self.map.put(ptr, {});
            return ptr;
        }

        pub fn save(self: *@This(), slice: []const T, arena: std.mem.Allocator) error{OutOfMemory}![]const T {
            if (self.slice_map.getKey(slice)) |res| {
                return res;
            }
            const res = try arena.dupe(T, slice);
            try self.slice_map.put(res, {});
            return res;
        }
    };
}
