const std = @import("std");

const Memo = @import("memo.zig").Memo;

pub fn Resolver(T: type) type {
    return struct {
        const Self = @This();
        memo: *Memo(T),
        map: std.StringHashMap(T),

        pub fn init(gpa: std.mem.Allocator, memo: *Memo(T)) Self {
            return .{
                .memo = memo,
                .map = .init(gpa),
            };
        }
    };
}
