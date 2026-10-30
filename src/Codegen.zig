const std = @import("std");

const okc = @import("okc");

io: std.Io, // expr
gpa: std.mem.Allocator, // expr
arena: std.mem.Allocator,
file: std.Io.File,
writer: std.Io.File.Writer,
buffer: ?std.ArrayList(u8) = null,
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
    try self.print("target triple = \"x86_64-pc-linux-gnu\"", .{});
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
    try self.print("\n", .{});
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
    try self.genFun(req.name, fun, req.fun);
}

fn genSliceDecl(self: *@This()) !void {
    try self.print("\n%\"[]\" = type {{ ptr, i64 }}", .{});
}

fn genExtFun(self: *@This(), name: []const u8, ext_fun: okc.Item.Fun.Extern) !void {
    try self.print("\ndeclare {f} @{s}(", .{
        okc.Typ.LLPrinter{ .typ = ext_fun.header.ret_typ },
        name,
    });
    if (ext_fun.header.params.len != 0) {
        try self.print("{f}", .{okc.Typ.LLPrinter{ .typ = ext_fun.header.params[0].typ }});
        for (ext_fun.header.params[1..]) |param| {
            try self.print(", {f}", .{okc.Typ.LLPrinter{ .typ = param.typ }});
        }
    }
    try self.print(")", .{});
}

pub fn genStrDecl(self: *@This(), str: []const u8) !okc.Expr.Str.GenInfo {
    const buffer = self.buffer.?;
    self.buffer = null;
    defer self.buffer = buffer;
    const unescaped = try unescape(self.gpa, str);
    defer self.gpa.free(unescaped.repr);
    const tmp = self.newTmp();
    try self.print("\n@.s{} = private unnamed_addr constant [{} x i8] c\"{s}\\00\", align 1", .{
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

fn genFun(
    self: *@This(),
    name: okc.Typ.Name,
    fun: okc.Item.Fun,
    fun_typ: okc.Typ.Fun,
) !void {
    self.buffer = self.extra_buffer;
    try self.print(
        "\ndefine {f} @\"{f}\"(",
        .{ okc.Typ.LLPrinter{ .typ = fun_typ.ret_typ.* }, name },
    );
    var param_typ_vals = try self.gpa.alloc(okc.Val.Typed, fun.header.params.len);
    defer self.gpa.free(param_typ_vals);
    if (fun.header.params.len != 0) {
        param_typ_vals[0] = try self.genParam(fun_typ.params[0]);
        for (param_typ_vals[1..], fun_typ.params[1..]) |*target, param_typ| {
            try self.print(", ", .{});
            target.* = try self.genParam(param_typ);
        }
    }
    try self.print(
        \\) {{
        \\entry:
    , .{});
    self.extra_buffer = self.buffer.?;
    self.buffer = .empty;
    for (
        param_typ_vals[0..fun.header.params.len],
        fun.header.params,
    ) |typ_val, param| {
        const vari = try self.toStack(typ_val);
        try self.vars.put(param.name, vari);
    }
    try fun.body.gen(self);
    if (fun.header.ret_typ.isVoid()) {
        try okc.Stmt.Return.gen(.{ .expr = null }, self);
    } else {
        try self.genUnreachable();
    }
    try self.print("\n}}", .{});
    var buffer = self.buffer.?;
    defer buffer.deinit(self.gpa);
    self.buffer = null;
    try self.print("{s}{s}", .{ self.extra_buffer.items, buffer.items });
    self.extra_buffer.clearRetainingCapacity();
    self.vars.clearRetainingCapacity();
    self.resolve_map.clearRetainingCapacity();
}

fn genParam(self: *@This(), typ: okc.Typ) !okc.Val.Typed {
    const tmp = self.newTmp();
    try self.print("{f} %t{}", .{ okc.Typ.LLPrinter{ .typ = typ }, tmp });
    return .{ .typ = typ, .bare = .{ .tmp = tmp } };
}

pub fn genUnreachable(self: *@This()) !void {
    try self.print("\n  unreachable", .{});
}

pub fn genIgnore(self: *@This(), ignore: okc.Stmt.Ignore) !void {
    _ = try ignore.expr.gen(self);
}

pub fn genBreak(self: *@This()) !void {
    const label = self.newTmp();
    try self.uncond(self.loop_ends.getLast(), label);
}

pub fn genWhile(self: *@This(), whi: okc.Stmt.While) !void {
    const condition_label = self.newTmp();
    try self.uncond(condition_label, condition_label);
    try self.genBranch(whi.branch, condition_label, .loop);
}

pub fn genForRange(self: *@This(), forr: okc.Stmt.ForRange) !void {
    // int i = start
    try self.genDeclare(forr.vari, .{
        .expr = forr.start,
        .typ = null,
        .mutable = false,
    });
    const end = try forr.end.gen(self);
    // goto cond
    // start:
    const start_label = self.newTmp();
    const cond_label = self.newTmp();
    try self.uncond(cond_label, start_label);
    // i++
    const ival = try self.vars.get(forr.vari).?.loadTypVal(self);
    const inew = try okc.Expr.Binary.genOnVals(.add, ival.typ, ival.bare, .{ .int = 1 }, self);
    try self.storeInto(
        self.vars.get(forr.vari).?.val,
        .{ .typ = ival.typ, .bare = .{ .tmp = inew } },
    );
    // goto cond
    // cond:
    try self.uncond(cond_label, cond_label);
    // cond = i != end
    const ival_ = try self.vars.get(forr.vari).?.loadTypVal(self);
    const at_end = try okc.Expr.Binary.genOnVals(.neq, ival.typ, ival_.bare, end.bare, self);
    // if cond, body, end
    // body:
    const body_label = self.newTmp();
    const end_label = self.newTmp();
    try self.cond(.{ .tmp = at_end }, body_label, end_label);
    // <body>
    try forr.body.gen(self);
    // goto start
    // end:
    try self.uncond(start_label, end_label);
}

pub fn genFor(self: *@This(), forr: okc.Stmt.For) !void {
    const slice = try forr.expr.genRef(self);
    // int i = 0
    const iref = try self.toStack(.{
        .typ = .{ .prime = .u64 },
        .bare = .{ .int = 0 },
    });
    // goto cond
    // start:
    const start_label = self.newTmp();
    const cond_label = self.newTmp();
    try self.uncond(cond_label, start_label);
    // i++
    const ival = try iref.loadTypVal(self);
    const inew = try okc.Expr.Binary.genOnVals(.add, ival.typ, ival.bare, .{ .int = 1 }, self);
    try self.storeInto(iref.val, .{ .typ = ival.typ, .bare = .{ .tmp = inew } });
    // goto cond
    // cond:
    try self.uncond(cond_label, cond_label);
    // cond = i < .len
    const ival_ = try iref.loadTypVal(self);
    const len_field: okc.Expr.Field = .{
        .expr = forr.expr,
        .vari = .{ .name = "len" },
    };
    const len = try len_field.gen(self);
    const less = try okc.Expr.Binary.genOnVals(.les, ival.typ, ival_.bare, len.bare, self);
    // if cond, body, end
    // body:
    const body_label = self.newTmp();
    const end_label = self.newTmp();
    try self.cond(.{ .tmp = less }, body_label, end_label);
    // var = slice[i]
    const elem = try slice.genElem(ival_, self);
    try self.vars.put(forr.vari, elem);
    // <body>
    try forr.body.gen(self);
    // goto start
    // end:
    try self.uncond(start_label, end_label);
}

fn cond(
    self: *@This(),
    condition: okc.Val,
    then_label: u32,
    else_label: u32,
) !void {
    try self.print(
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
    try self.print(
        \\
        \\  br label %l{}
        \\l{}:
    , .{ to, next });
}

pub fn genIf(self: *@This(), iff: okc.Stmt.IfStmt) !void {
    const end_label = self.newTmp();
    try self.genBranch(iff.branch, end_label, .simple);
    for (iff.else_ifs) |branch| {
        try self.genBranch(branch, end_label, .simple);
    }
    try iff.else_block.gen(self);
    try self.uncond(end_label, end_label);
}

fn genBranch(self: *@This(), branch: okc.Stmt.Branch, end_label: u32, kind: okc.Stmt.Branch.Kind) !void {
    const condition = try branch.condition.gen(self);
    const then_label = self.newTmp();
    const else_label = self.newTmp();
    if (kind == .loop) {
        try self.loop_ends.append(self.gpa, else_label);
    }
    try self.cond(condition.bare, then_label, else_label);
    try branch.body.gen(self);
    try self.uncond(end_label, else_label);
    if (kind == .loop) {
        _ = self.loop_ends.pop();
    }
}

pub fn genOpAssign(self: *@This(), op_assign: okc.Stmt.OpAssign) !void {
    const vari = try op_assign.left.genRef(self);
    const typ_val = try okc.Expr.Binary.gen(.{
        .left = op_assign.left,
        .kind = op_assign.kind,
        .right = op_assign.right,
    }, self);
    try self.storeInto(vari.val, typ_val);
}

pub fn genAssign(self: *@This(), assign: okc.Stmt.Assign) !void {
    const vari = try assign.left.genRef(self);
    const typ_val = try assign.expr.gen(self);
    try self.storeInto(vari.val, typ_val);
}

pub fn genDeclare(self: *@This(), name: []const u8, declare: okc.Stmt.Declare) !void {
    const typ_val = try declare.expr.gen(self);
    const vari = try self.toStack(typ_val);
    try self.vars.put(name, vari);
}

pub fn toStack(self: *@This(), typ_val: okc.Val.Typed) !okc.Val.Ref {
    if (typ_val.typ.getName()) |name| {
        try okc.Item.TypDecl.genNamed(name, self);
    }
    const tmp = self.newTmp();
    try self.genAlloca(tmp, typ_val.typ);
    try self.storeInto(.{ .tmp = tmp }, typ_val);
    return .{
        .val = .{ .tmp = tmp },
        .inner_typ = typ_val.typ,
    };
}

fn genAlloca(self: *@This(), tmp: u32, typ: okc.Typ) !void {
    const buffer = self.buffer;
    // so that all allocs are in entry block
    self.buffer = self.extra_buffer;
    defer {
        self.extra_buffer = self.buffer.?;
        self.buffer = buffer;
    }
    try self.print("\n  %t{} = alloca {f}", .{ tmp, okc.Typ.LLPrinter{ .typ = typ } });
}

fn storeInto(self: *@This(), val: okc.Val, typ_val: okc.Val.Typed) !void {
    try self.print("\n  store {f}, ptr {f}", .{ typ_val, val });
}

fn newTmp(self: *@This()) u32 {
    return self.counter.next();
}

fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
    if (self.buffer) |*buffer| {
        try buffer.print(self.gpa, fmt, args);
    } else {
        try self.writer.interface.print(fmt, args);
    }
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
    self.* = undefined;
}
