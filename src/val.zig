const std = @import("std");

const okc = @import("okc");

pub const Val = union(enum) {
    global: okc.Typ.Name,
    int: u64,
    str: usize,
    tmp: u32,
    undef,

    pub const Ref = @import("val/Ref.zig");
    pub const Typed = @import("val/Typed.zig");

    pub fn format(val: Val, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (val) {
            .int => |int| try writer.print("{d}", .{int}),
            .str => |str| try writer.print("@.s{}", .{str}),
            .tmp => |tmp| try writer.print("%t{}", .{tmp}),
            .global => |name| try writer.print("@\"{f}\"", .{name}),
            .undef => try writer.writeAll("poison"),
        }
    }
};
