target triple = "x86_64-pc-linux-gnu"
@.s0 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
declare i32 @printf(ptr, i32)
define i32 @main() {
entry:
  %t0 = mul i32 2, 2
  %t1 = sdiv i32 %t0, 4
  %t2 = add i32 2, %t1
  %t3 = sub i32 %t2, 2
  %t4 = call i32 @printf(ptr @.s0, i32 %t3)
  ret i32 0
}
