const std = @import("std");

const okc = @import("okc");

generics: []const okc.Item.Generic,
fields: std.StringHashMap(okc.Item.TypDecl.Field.Info),
variants: std.StringHashMap(okc.Item.TypDecl.Variant.Info),

pub fn checkUsage(self: @This(), failer: *okc.Failer) void {
    var iter = self.fields.iterator();
    while (iter.next()) |entry| {
        if (!entry.value_ptr.used) {
            failer.unused(entry.value_ptr.location, entry.key_ptr.*);
        }
    }
}

pub fn deinit(self: *@This()) void {
    self.fields.deinit();
    self.* = undefined;
}
