const okc = @import("okc");

typ: okc.Typ,
mutable: bool,

pub fn getElem(self: @This(), location: okc.Location, failer: *okc.Failer) ?@This() {
    switch (self.typ.normalise()) {
        .array => |array| return .{
            .typ = array.typ.*,
            .mutable = self.mutable,
        },
        .slice => |slice| return .{
            .typ = slice.typ.*,
            .mutable = slice.mutable,
        },
        .err => return null,
        .prime, .name, .loc_name, .ptr, .any, .fun, .int => {
            failer.fail(location, "type `{f}` does not support indexing", .{self.typ});
            return null;
        },
        .lazy => unreachable,
    }
}
