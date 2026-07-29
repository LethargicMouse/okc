target triple = "x86_64-pc-linux-gnu"
@.s0 = private unnamed_addr constant [5 x i8] c"hello", align 1
declare i32 @puts(ptr)
define i32 @main() {
entry:
  call i32 @puts(ptr @.s0)
  ret i32 0
}