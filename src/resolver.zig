const std = @import("std");

const memo = @import("memo.zig");

pub fn Resolver(T: type) type {
    return struct {
        const Self = @This();
        mem: *memo.Memo(T),
        map: std.StringHashMap(T),

        pub fn init(mem: *memo.Memo(T)) Self {
            return .{
                .mem = mem,
                .map = .init(mem.arena.child_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }
    };
}
