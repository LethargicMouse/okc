target triple = "x86_64-pc-linux-gnu"
@.s0 = private unnamed_addr constant [9 x i8] c"fizzbuzz\00", align 1
@.s1 = private unnamed_addr constant [5 x i8] c"buzz\00", align 1
@.s2 = private unnamed_addr constant [5 x i8] c"fizz\00", align 1
@.s3 = private unnamed_addr constant [4 x i8] c"%d\0A\00", align 1
declare i32 @printf(ptr, i32)
declare i32 @puts(ptr)
define i32 @main() {
entry:
  %t0 = alloca i32
  store i32 0, ptr %t0
  br label %l1
l1:
  %t2 = load i32, ptr %t0
  %t3 = icmp slt i32 %t2, 20
  br i1 %t3, label %l4, label %l5
l4:
  %t6 = load i32, ptr %t0
  %t7 = add i32 %t6, 1
  store i32 %t7, ptr %t0
  %t9 = load i32, ptr %t0
  %t10 = srem i32 %t9, 15
  %t11 = icmp eq i32 %t10, 0
  br i1 %t11, label %l12, label %l13
l12:
  %t14 = call i32 @puts(ptr @.s0)
  br label %l8
l13:
  %t15 = load i32, ptr %t0
  %t16 = srem i32 %t15, 5
  %t17 = icmp eq i32 %t16, 0
  br i1 %t17, label %l18, label %l19
l18:
  %t20 = call i32 @puts(ptr @.s1)
  br label %l8
l19:
  %t21 = load i32, ptr %t0
  %t22 = srem i32 %t21, 3
  %t23 = icmp eq i32 %t22, 0
  br i1 %t23, label %l24, label %l25
l24:
  %t26 = call i32 @puts(ptr @.s2)
  br label %l8
l25:
  %t27 = load i32, ptr %t0
  %t28 = call i32 @printf(ptr @.s3, i32 %t27)
  br label %l8
l8:
  br label %l1
l5:
  ret i32 0
}
