const std = @import("std");

const Typ = @import("mod.zig").Typ;

typ: *Typ,

pub fn from(typ: *Typ) @This() {
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

pub fn set(self: @This(), typ: Typ) void {
    self.typ.* = typ;
    std.log.debug("=> {f}", .{Typ{ .lazy = self }});
}

pub fn format(self: @This(), writer: *std.Io.Writer) !void {
    if (debug) {
        try writer.print("@{x}<{f}>", .{ @intFromPtr(self.typ) & 0xffff, self.typ.* });
    } else {
        try self.typ.format(writer);
    }
}
