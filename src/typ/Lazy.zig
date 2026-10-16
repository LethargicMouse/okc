const std = @import("std");

const okc = @import("okc");

typ: *okc.Typ,

pub fn from(typ: *okc.Typ) @This() {
    const res = @This(){ .typ = typ };
    std.log.debug("=> {f}", .{res});
    return res;
}

pub fn shorten(self: @This()) @This() {
    if (self.typ.* == .lazy) {
        self.typ.lazy = self.typ.lazy.shorten();
        std.log.debug("=> {f}", .{self});
        return self.typ.lazy;
    } else {
        return self;
    }
}

const debug = true;

pub fn set(self: @This(), typ: okc.Typ) void {
    self.typ.* = typ;
    std.log.debug("=> {f}", .{okc.Typ{ .lazy = self }});
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    if (debug) {
        try writer.print("@{x}<{f}>", .{ @intFromPtr(self.typ) & 0xffff, self.typ.* });
    } else {
        try self.typ.format(writer);
    }
}
