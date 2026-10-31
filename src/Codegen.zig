const std = @import("std");

const okc = @import("okc");

io: std.Io, // expr
gpa: std.mem.Allocator, // expr
arena: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
buffer: std.ArrayList(u8) = .empty,
extra_buffer: std.ArrayList(u8) = .empty,
module: *okc.Module.GenInfo,
consts: std.StringHashMap(okc.Typ),
typ_decls: okc.HashMap(okc.Typ.Name, okc.Item.TypDecl.GenInfo),
vars: std.StringHashMap(okc.Val.Ref),
loop_ends: std.ArrayList(u32) = .empty,
fun_queue: std.ArrayList(okc.Item.Fun.GenReq) = .empty,
generated: okc.HashMap(okc.Typ.Name, void),
resolve_map: std.StringHashMap(okc.Typ),
counter: okc.Counter = .init(),
modules: std.StringHashMap(*okc.Module.GenInfo),
ast_modules: std.StringHashMap(okc.Module),

pub fn init(
    ctx: struct {
        io: std.Io,
        gpa: std.mem.Allocator,
        arena: std.mem.Allocator,
        ast_modules: std.StringHashMap(okc.Module),
        write_buf: []u8,
        path: []const u8,
    },
) error{ OutOfMemory, Handled }!@This() {
    const file = std.Io.Dir.cwd().createFile(ctx.io, ctx.path, .{}) catch {
        std.log.err("failed to create `{s}`", .{ctx.path});
        return error.Handled;
    };
    return .{
        .typ_decls = .init(ctx.gpa),
        .io = ctx.io,
        .gpa = ctx.gpa,
        .arena = ctx.arena,
        .file = file,
        .ast_modules = ctx.ast_modules,
        .modules = .init(ctx.gpa),
        .resolve_map = .init(ctx.gpa),
        .writer = file.writer(ctx.io, ctx.write_buf),
        .vars = .init(ctx.gpa),
        .module = undefined,
        .consts = .init(ctx.gpa),
        .generated = .init(ctx.gpa),
    };
}

pub fn deinit(self: *@This()) void {
    var iter = self.modules.valueIterator();
    while (iter.next()) |module| {
        module.*.deinit();
        self.gpa.destroy(module.*);
    }
    var structs_iter = self.typ_decls.valueIterator();
    while (structs_iter.next()) |info| {
        info.deinit(self.gpa);
    }
    self.typ_decls.deinit();
    self.modules.deinit();
    self.vars.deinit();
    self.file.close(self.io);
    self.loop_ends.deinit(self.gpa);
    self.fun_queue.deinit(self.gpa);
    self.generated.deinit();
    self.resolve_map.deinit();
    self.consts.deinit();
    self.extra_buffer.deinit(self.gpa);
    self.buffer.deinit(self.gpa);
    self.* = undefined;
}
