target triple = "x86_64-pc-linux-gnu"
%str = type { ptr, i64 }
@.s0 = private unnamed_addr constant [14 x i8] c"wazzup niggas\00", align 1
@.s1 = private unnamed_addr constant [20 x i8] c"oh gotta go nvm bye\00", align 1
declare i32 @puts(ptr)
define i32 @main() {
entry:
  %t0 = alloca %str, align 8
  store %str { ptr @.s0, i64 13 }, ptr %t0
  %t1 = alloca ptr
  store ptr %t0, ptr %t1
  %t2 = alloca %str, align 8
  store %str { ptr @.s1, i64 19 }, ptr %t2
  store ptr %t2, ptr %t1
  %t3 = load ptr, ptr %t1
  %t4 = getelementptr inbounds %str, ptr %t3, i32 0, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = call i32 @puts(ptr %t5)
  ret i32 0
}
