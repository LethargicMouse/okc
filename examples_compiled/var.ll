target triple = "x86_64-pc-linux-gnu"
@.s0 = private unnamed_addr constant [14 x i8] c"wazzup niggas\00", align 1
declare i32 @puts(ptr)
define i32 @main() {
entry:
  %t0 = alloca ptr
  store ptr @.s0, ptr %t0
  %t1 = load ptr, ptr %t0
  %t2 = call i32 @puts(ptr %t1)
  ret i32 0
}
