target triple = "x86_64-pc-linux-gnu"
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
  %t6 = call i32 @puts(ptr @.s0)
  br label %l1
l5:
  %t7 = call i32 @puts(ptr @.s1)
  br label %l1
l1:
  ret i32 0
}
