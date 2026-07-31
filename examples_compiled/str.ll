target triple = "x86_64-pc-linux-gnu"
%str = type { ptr, i64 }
@.s0 = private unnamed_addr constant [7 x i8] c"siiiix\00", align 1
@.s1 = private unnamed_addr constant [8 x i8] c"seveeen\00", align 1
@.s2 = private unnamed_addr constant [5 x i8] c"%zu-\00", align 1
@.s3 = private unnamed_addr constant [8 x i8] c"%zu!!!\0A\00", align 1
declare i32 @printf(ptr, ptr)
define i32 @main() {
entry:
  %t0 = alloca %str, align 8
  store %str { ptr @.s0, i64 6 }, ptr %t0
  %t1 = alloca ptr
  store ptr %t0, ptr %t1
  %t2 = alloca %str, align 8
  store %str { ptr @.s1, i64 7 }, ptr %t2
  %t3 = alloca ptr
  store ptr %t2, ptr %t3
  %t4 = alloca %str, align 8
  store %str { ptr @.s2, i64 4 }, ptr %t4
  %t5 = getelementptr inbounds %str, ptr %t4, i32 0, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = load ptr, ptr %t1
  %t8 = getelementptr inbounds %str, ptr %t7, i32 0, i32 1
  %t9 = load i64, ptr %t8
  %t10 = call i32 @printf(ptr %t6, i64 %t9)
  %t11 = alloca %str, align 8
  store %str { ptr @.s3, i64 7 }, ptr %t11
  %t12 = getelementptr inbounds %str, ptr %t11, i32 0, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = load ptr, ptr %t3
  %t15 = getelementptr inbounds %str, ptr %t14, i32 0, i32 1
  %t16 = load i64, ptr %t15
  %t17 = call i32 @printf(ptr %t13, i64 %t16)
  ret i32 0
}
