target triple = "x86_64-pc-linux-gnu"
%str = type { ptr, i64 }
@.s0 = private unnamed_addr constant [12 x i8] c"SIXSEVEEEN!\00", align 1
@.s1 = private unnamed_addr constant [13 x i8] c"no sixseven(\00", align 1
declare i32 @puts(ptr)
define i32 @main() {
entry:
  %t0 = alloca i32
  store i32 67, ptr %t0
  %t2 = load i32, ptr %t0
  %t3 = icmp eq i32 %t2, 67
  br i1 %t3, label %l4, label %l5
l4:
  %t6 = alloca %str, align 8
  store %str { ptr @.s0, i64 11 }, ptr %t6
  %t7 = getelementptr inbounds %str, ptr %t6, i32 0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = call i32 @puts(ptr %t8)
  br label %l1
l5:
  %t10 = alloca %str, align 8
  store %str { ptr @.s1, i64 12 }, ptr %t10
  %t11 = getelementptr inbounds %str, ptr %t10, i32 0, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = call i32 @puts(ptr %t12)
  br label %l1
l1:
  ret i32 0
}
