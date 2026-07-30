target triple = "x86_64-pc-linux-gnu"
@.s0 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
declare i32 @printf(ptr, i32)
define i32 @main() {
entry:
  %t0 = call i32 @calc()
  %t1 = call i32 @printf(ptr @.s0, i32 %t0)
  ret i32 0
}
define i32 @calc() {
entry:
  ret i32 123
}
