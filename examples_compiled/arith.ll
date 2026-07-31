target triple = "x86_64-pc-linux-gnu"
%str = type { ptr, i64 }
@.s0 = private unnamed_addr constant [3 x i8] c"%d\00", align 1
declare i32 @printf(ptr, i32)
define i32 @main() {
entry:
  %t0 = alloca %str, align 8
  store %str { ptr @.s0, i64 2 }, ptr %t0
  %t1 = getelementptr inbounds %str, ptr %t0, i32 0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = mul i32 2, 2
  %t4 = sdiv i32 %t3, 4
  %t5 = add i32 2, %t4
  %t6 = sub i32 %t5, 2
  %t7 = call i32 @printf(ptr %t2, i32 %t6)
  ret i32 0
}
