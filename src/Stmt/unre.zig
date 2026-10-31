const okc = @import("okc");

pub fn gen(ctx: *okc.Codegen) !void {
    try ctx.buffer.appendSlice(ctx.gpa, "\n  unreachable");
}
