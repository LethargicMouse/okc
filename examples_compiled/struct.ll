; ModuleID = 'main'
source_filename = "main"
target triple = "x86_64-pc-linux-gnu"

@.s1 = private unnamed_addr constant [7 x i8] c"siiiix\00", align 1
@.s6 = private unnamed_addr constant [8 x i8] c"seveeen\00", align 1
@.s11 = private unnamed_addr constant [5 x i8] c"%zu\0A\00", align 1
@.s16 = private unnamed_addr constant [5 x i8] c"%zu\0A\00", align 1

declare i32 @printf(ptr, ptr)

define i32 @main() {
entry:
  %t0 = alloca { ptr, i64 }, align 8
  %t2 = getelementptr inbounds nuw { ptr, i64 }, ptr %t0, i32 0, i32 0
  store ptr @.s1, ptr %t2, align 8
  %t3 = getelementptr inbounds nuw { ptr, i64 }, ptr %t0, i32 0, i32 1
  store i64 6, ptr %t3, align 4
  %t4 = alloca ptr, align 8
  store ptr %t0, ptr %t4, align 8
  %t5 = alloca { ptr, i64 }, align 8
  %t7 = getelementptr inbounds nuw { ptr, i64 }, ptr %t5, i32 0, i32 0
  store ptr @.s6, ptr %t7, align 8
  %t8 = getelementptr inbounds nuw { ptr, i64 }, ptr %t5, i32 0, i32 1
  store i64 7, ptr %t8, align 4
  %t9 = alloca ptr, align 8
  store ptr %t5, ptr %t9, align 8
  %t12 = load ptr, ptr %t4, align 8
  %t13 = getelementptr inbounds nuw { ptr, ptr }, ptr %t12, i32 0, i32 1
  %t14 = load ptr, ptr %t13, align 8
  %t10 = call i32 @printf(ptr @.s11, ptr %t14)
  %t17 = load ptr, ptr %t9, align 8
  %t18 = getelementptr inbounds nuw { ptr, ptr }, ptr %t17, i32 0, i32 1
  %t19 = load ptr, ptr %t18, align 8
  %t15 = call i32 @printf(ptr @.s16, ptr %t19)
  ret i32 0
}
