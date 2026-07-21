; ModuleID = 'main'
source_filename = "main"
target triple = "x86_64-pc-linux-gnu"

@.s17 = private unnamed_addr constant [9 x i8] c"fizzbuzz\00", align 1
@.s25 = private unnamed_addr constant [5 x i8] c"buzz\00", align 1
@.s33 = private unnamed_addr constant [5 x i8] c"fizz\00", align 1
@.s35 = private unnamed_addr constant [4 x i8] c"%d\0A\00", align 1

declare i32 @printf(ptr, i32)

declare i32 @puts(ptr)

define i32 @main() {
entry:
  %t0 = alloca i32, align 4
  store i32 0, ptr %t0, align 4
  br label %s1

s1:                                               ; preds = %s31, %s29, %s21, %s13, %entry
  %t3 = load i32, ptr %t0, align 4
  %t4 = add i32 %t3, 1
  store i32 %t4, ptr %t0, align 4
  %t5 = load i32, ptr %t0, align 4
  %t6 = icmp eq i32 %t5, 21
  br i1 %t6, label %s7, label %s8

s2:                                               ; preds = %s7
  ret i32 0

s7:                                               ; preds = %s1
  br label %s2
  br label %s9

s8:                                               ; preds = %s1
  br label %s9

s9:                                               ; preds = %s8, %s7
  %t10 = load i32, ptr %t0, align 4
  %t11 = srem i32 %t10, 15
  %t12 = icmp eq i32 %t11, 0
  br i1 %t12, label %s13, label %s14

s13:                                              ; preds = %s9
  %t16 = call i32 @puts(ptr @.s17)
  br label %s1
  br label %s15

s14:                                              ; preds = %s9
  br label %s15

s15:                                              ; preds = %s14, %s13
  %t18 = load i32, ptr %t0, align 4
  %t19 = srem i32 %t18, 5
  %t20 = icmp eq i32 %t19, 0
  br i1 %t20, label %s21, label %s22

s21:                                              ; preds = %s15
  %t24 = call i32 @puts(ptr @.s25)
  br label %s1
  br label %s23

s22:                                              ; preds = %s15
  br label %s23

s23:                                              ; preds = %s22, %s21
  %t26 = load i32, ptr %t0, align 4
  %t27 = srem i32 %t26, 3
  %t28 = icmp eq i32 %t27, 0
  br i1 %t28, label %s29, label %s30

s29:                                              ; preds = %s23
  %t32 = call i32 @puts(ptr @.s33)
  br label %s1
  br label %s31

s30:                                              ; preds = %s23
  br label %s31

s31:                                              ; preds = %s30, %s29
  %t36 = load i32, ptr %t0, align 4
  %t34 = call i32 @printf(ptr @.s35, i32 %t36)
  br label %s1
}
