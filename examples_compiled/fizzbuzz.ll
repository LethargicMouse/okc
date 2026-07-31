target triple = "x86_64-pc-linux-gnu"
%str = type { ptr, i64 }
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
  %t14 = alloca %str, align 8
  store %str { ptr @.s0, i64 8 }, ptr %t14
  %t15 = getelementptr inbounds %str, ptr %t14, i32 0, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = call i32 @puts(ptr %t16)
  br label %l8
l13:
  %t18 = load i32, ptr %t0
  %t19 = srem i32 %t18, 5
  %t20 = icmp eq i32 %t19, 0
  br i1 %t20, label %l21, label %l22
l21:
  %t23 = alloca %str, align 8
  store %str { ptr @.s1, i64 4 }, ptr %t23
  %t24 = getelementptr inbounds %str, ptr %t23, i32 0, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = call i32 @puts(ptr %t25)
  br label %l8
l22:
  %t27 = load i32, ptr %t0
  %t28 = srem i32 %t27, 3
  %t29 = icmp eq i32 %t28, 0
  br i1 %t29, label %l30, label %l31
l30:
  %t32 = alloca %str, align 8
  store %str { ptr @.s2, i64 4 }, ptr %t32
  %t33 = getelementptr inbounds %str, ptr %t32, i32 0, i32 0
  %t34 = load ptr, ptr %t33
  %t35 = call i32 @puts(ptr %t34)
  br label %l8
l31:
  %t36 = alloca %str, align 8
  store %str { ptr @.s3, i64 3 }, ptr %t36
  %t37 = getelementptr inbounds %str, ptr %t36, i32 0, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = load i32, ptr %t0
  %t40 = call i32 @printf(ptr %t38, i32 %t39)
  br label %l8
l8:
  br label %l1
l5:
  ret i32 0
}
