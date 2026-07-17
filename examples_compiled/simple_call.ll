target triple = "x86_64-pc-linux-gnu"
declare i32 @puts(ptr)
define i32 @main() {
entry:
call i32 (ptr) @puts(ptr @.str0)
ret i32 0
}
@.str0 = private unnamed_addr constant [12 x i8] c"hello world\00", align 1
