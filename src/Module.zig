const std = @import("std");

const okc = @import("okc");

pub const Check = @import("Module/Check.zig");
pub const GenInfo = @import("Module/GenInfo.zig");
pub const Info = @import("Module/Info.zig");

items: []okc.Item,
location: okc.Location,

pub fn gen(self: @This(), name: []const u8, ctx: *okc.Codegen) error{ WriteFailed, OutOfMemory }!void {
    const info = try self.makeGenInfo(ctx.gpa, name);
    try ctx.modules.put(name, info);
    ctx.module = info;
    try ctx.genAll();
    try ctx.writer.interface.flush();
}

pub fn makeGenInfo(self: @This(), gpa: std.mem.Allocator, name: []const u8) !*GenInfo {
    const res = try gpa.create(GenInfo);
    res.* = .init(gpa, name);
    for (self.items) |item| {
        const item_name = if (std.mem.eql(u8, item.name, "Self")) name else item.name;
        try res.items.put(item_name, item.kind);
    }
    return res;
}

pub fn makeInfo(self: @This(), ctx: Check) error{ OutOfMemory, Handled }!Info {
    var res: Info = .init(ctx.gpa);
    errdefer res.deinit();
    for (self.items) |*item| {
        try item.reg(ctx.itemCheckCtx(&res.items));
    }
    return res;
}

pub fn read(
    io: std.Io,
    gpa: std.mem.Allocator,
    path: []const u8,
    arena: std.mem.Allocator,
    location: ?okc.Location,
) !@This() {
    const source: okc.Source = try .read(io, gpa, arena, path, location);
    var lexer: okc.Lexer = try .init(gpa, source);
    const tokens = try lexer.lex(gpa);
    var parser: okc.Parser = .init(gpa, arena, tokens);
    return parser.run();
}

pub fn check(self: @This(), info: *Info, kind: Kind, ctx: Check) !void {
    for (self.items) |item| {
        try item.check(ctx.itemCheckCtx(&info.items));
    }
    if (kind == .main) {
        info.checkMain(self.location, ctx);
    }
    info.checkUsage(ctx.failer);
}

pub const Kind = enum {
    main,
    simple,
};
