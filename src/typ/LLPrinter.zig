const std = @import("std");

const okc = @import("okc");

typ: okc.Typ,

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    std.log.debug("llvm of `{f}`", .{self.typ});
    switch (self.typ) {
        .prime => |prime| {
            const sprime = switch (prime) {
                .u8 => "i8",
                .i32 => "i32",
                .u32 => "i32",
                .u64 => "i64",
                .bool => "i1",
                .void => "void",
            };
            try writer.writeAll(sprime);
        },
        .array => |array| {
            try writer.print("[{} x {f}]", .{
                array.index.len,
                @This(){ .typ = array.typ.* },
            });
        },
        .slice => try writer.writeAll("%\"[]\""),
        .ptr, .fun => try writer.writeAll("ptr"),
        .name => |name| try writer.print("%\"{f}\"", .{name}),
        .loc_name => |located| try writer.print("%\"{f}\"", .{located.bare}),
        .lazy, .any, .int, .err, .typ => unreachable,
    }
}
