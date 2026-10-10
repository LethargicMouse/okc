const std = @import("std");

const Memo = @import("../memo.zig").Memo;
const Typ = @import("mod.zig").Typ;

const Self = @This();
mem: *Memo(Typ),
map: std.StringHashMap(Typ),
