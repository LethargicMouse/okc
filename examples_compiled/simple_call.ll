target triple = "x86_64-pc-linux-gnu"
@.s0 = private unnamed_addr constant [6 x i8] c"hello\00", align 1
declare i32 @puts(ptr)
define i32 @main() {
entry:
  %t0 = call i32 @puts(ptr @.s0)
  ret i32 0
}
