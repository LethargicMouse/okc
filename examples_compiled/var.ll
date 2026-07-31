target triple = "x86_64-pc-linux-gnu"
%str = type { ptr, i64 }
@.s0 = private unnamed_addr constant [14 x i8] c"wazzup niggas\00", align 1
declare i32 @puts(ptr)
define i32 @main() {
entry:
  %t0 = alloca %str, align 8
  store %str { ptr @.s0, i64 13 }, ptr %t0
  %t1 = getelementptr inbounds %str, ptr %t0, i32 0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = alloca ptr
  store ptr %t2, ptr %t3
  %t4 = load ptr, ptr %t3
  %t5 = call i32 @puts(ptr %t4)
  ret i32 0
}
