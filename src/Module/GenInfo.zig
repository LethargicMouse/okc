const std = @import("std");

const okc = @import("okc");

structs: okc.HashMap(okc.Typ.Name, okc.Item.Struct.GenInfo),

pub fn init(gpa: std.mem.Allocator) @This() {
    return .{
        .structs = .init(gpa),
    };
}

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    var iter = self.structs.valueIterator();
    while (iter.next()) |info| {
        info.fields.deinit();
        gpa.free(info.default_fields);
    }
    self.structs.deinit();
    self.* = undefined;
}
