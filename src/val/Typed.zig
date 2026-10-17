const std = @import("std");

const okc = @import("okc");

bare: okc.Val,
typ: okc.Typ,

pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("{f} {f}", .{ okc.Typ.LLPrinter{ .typ = self.typ }, self.bare });
}

pub fn int(n: u64) okc.Val.Typed {
    return .{
        .typ = .{ .prime = .i32 },
        .bare = .{ .int = n },
    };
}
