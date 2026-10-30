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
fun_queue: std.ArrayList(FunReq) = .empty,
generated: okc.HashMap(okc.Typ.Name, void),
resolve_map: std.StringHashMap(okc.Typ),
counter: okc.Counter = .init(),
modules: std.StringHashMap(*okc.Module.GenInfo),
ast_modules: std.StringHashMap(okc.Module),

const FunReq = struct {
    module: *okc.Module.GenInfo,
    name: okc.Typ.Name,
    fun: okc.Typ.Fun,
};

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

pub fn genAll(self: *@This()) !void {
    try self.writer.interface.writeAll("target triple = \"x86_64-pc-linux-gnu\"");
    try self.genSliceDecl();
    try self.genFunNamed(.{
        .module = self.module,
        .name = .{ .name = "main" },
        .fun = .{
            .params = &.{},
            .ret_typ = try okc.Typ.memo.box(.{ .prime = .i32 }, self.arena),
        },
    });
    while (self.fun_queue.items.len != 0) {
        const req = self.fun_queue.pop().?;
        try self.genFunNamed(req);
    }
    try self.writer.interface.print("\n", .{});
}

fn genFunNamed(self: *@This(), req: FunReq) !void {
    self.module = req.module;
    const item = self.module.items.get(req.name.name).?;
    const fun = switch (item) {
        .typ_alias, .use => unreachable,
        .ext_fun => |ext_fun| {
            const was = try self.generated.getOrPut(req.name);
            if (was.found_existing) {
                return;
            }
            try self.genExtFun(req.name.name, ext_fun);
            return;
        },
        .fun => |fun| fun,
        .constant, .typ_decl => unreachable,
    };
    const was = try self.generated.getOrPut(req.name);
    if (was.found_existing) {
        return;
    }
    for (fun.header.generics, req.name.generics) |generic, typ| {
        try self.resolve_map.put(generic.name, typ);
    }
    try fun.gen(req.name, req.fun, self);
}

fn genSliceDecl(self: *@This()) !void {
    try self.writer.interface.writeAll("\n%\"[]\" = type { ptr, i64 }");
}

fn genExtFun(self: *@This(), name: []const u8, ext_fun: okc.Item.Fun.Extern) !void {
    try self.writer.interface.print("\ndeclare {f} @{s}(", .{
        okc.Typ.LLPrinter{ .typ = ext_fun.header.ret_typ },
        name,
    });
    if (ext_fun.header.params.len != 0) {
        try self.writer.interface.print("{f}", .{okc.Typ.LLPrinter{ .typ = ext_fun.header.params[0].typ }});
        for (ext_fun.header.params[1..]) |param| {
            try self.writer.interface.print(", {f}", .{okc.Typ.LLPrinter{ .typ = param.typ }});
        }
    }
    try self.writer.interface.print(")", .{});
}

pub fn genStrDecl(self: *@This(), str: []const u8) !okc.Expr.Str.GenInfo {
    const unescaped = try unescape(self.gpa, str);
    defer self.gpa.free(unescaped.repr);
    const tmp = self.counter.next();
    try self.writer.interface.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
        tmp,
        unescaped.len + 1,
        unescaped.repr,
    });
    return .{
        .len = unescaped.len,
        .tmp = tmp,
    };
}

fn unescape(gpa: std.mem.Allocator, str: []const u8) !okc.Expr.Str.Unescaped {
    var vec = try std.ArrayList(u8).initCapacity(gpa, str.len);
    var i: usize = 0;
    var len = str.len;
    while (i < str.len) : (i += 1) {
        if (str[i] == '\\') {
            i += 1;
            len -= 1;
            switch (str[i]) {
                'n' => try vec.appendSlice(gpa, "\\0A"),
                'x' => {
                    try vec.append(gpa, '\\');
                    try vec.appendSlice(gpa, str[i + 1 .. i + 3]);
                    i += 2;
                    len -= 2;
                },
                else => {
                    std.log.err("bad escape symbol: `\\{c}`", .{str[i]});
                    // supposed to be checked by `Checker`
                    unreachable;
                },
            }
        } else {
            try vec.append(gpa, str[i]);
        }
    }
    const repr = try vec.toOwnedSlice(gpa);
    return .{
        .len = len,
        .repr = repr,
    };
}

pub fn genUnreachable(self: *@This()) !void {
    try self.buffer.print(self.gpa, "\n  unreachable", .{});
}

pub fn cond(
    self: *@This(),
    condition: okc.Val,
    then_label: u32,
    else_label: u32,
) !void {
    try self.buffer.print(self.gpa,
        \\
        \\  br i1 {f}, label %l{}, label %l{}
        \\l{}:
    , .{
        condition,
        then_label,
        else_label,
        then_label,
    });
}

pub fn uncond(self: *@This(), to: u32, next: u32) !void {
    try self.buffer.print(self.gpa,
        \\
        \\  br label %l{}
        \\l{}:
    , .{ to, next });
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
