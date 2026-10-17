const std = @import("std");

const okc = @import("okc");

pub const Prime = enum {
    bool,
    i32,
    u32,
    u64,
    u8, // zlinter-disable-current-line field_naming
    void,

    pub fn getLayout(self: @This()) okc.Layout {
        return switch (self) {
            .u8, .bool => .new(1, 1),
            .i32, .u32 => .new(4, 4),
            .u64 => .new(8, 8),
            .void => .new(0, 1),
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.writeAll(@tagName(self));
    }

    pub fn isNumber(self: @This()) bool {
        switch (self) {
            .i32, .u8, .u32, .u64 => return true,
            .bool, .void => return false,
        }
    }

    pub fn hashIn(self: @This(), hasher: *std.hash.Wyhash) void {
        hasher.update(&.{@backingInt(self)});
    }
};
