const std = @import("std");

const HashContext = @import("hash_context.zig").HashContext;

pub fn Memo(T: type) type {
    return struct {
        const Self = @This();

        arena: *std.heap.ArenaAllocator,
        map: std.HashMap(
            T,
            *const T,
            HashContext(T),
            std.hash_map.default_max_load_percentage,
        ),

        pub fn init(arena: *std.heap.ArenaAllocator) Self {
            return .{
                .arena = arena,
                .map = .init(arena.child_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.* = undefined;
        }

        pub fn box(self: *Self, val: T) !*const T {
            const entry = try self.map.getOrPut(val);
            if (!entry.found_existing) {
                const ptr = try self.arena.allocator().create(T);
                ptr.* = val;
                entry.value_ptr.* = ptr;
            }
            return entry.value_ptr.*;
        }
    };
}
