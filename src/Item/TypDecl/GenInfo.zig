const std = @import("std");

const okc = @import("okc");

fields: std.StringHashMap(okc.Item.TypDecl.Field.GenInfo),
variants: std.StringHashMap(usize),
default_fields: []const okc.Item.TypDecl.Field.DefaultedGenInfo,
layout: okc.Layout,

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    self.fields.deinit();
    self.variants.deinit();
    gpa.free(self.default_fields);
    self.* = undefined;
}
