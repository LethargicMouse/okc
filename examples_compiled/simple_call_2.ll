target triple = "x86_64-pc-linux-gnu"
declare i32 @printf(ptr, i32)
define i32 @main() {
entry:
%t0 = call i32 () @calc()
call i32 (ptr) @printf(ptr @.str0, i32 %t0)
ret i32 0
}
define i32 @calc() {
entry:
ret i32 123
}
@.str0 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
