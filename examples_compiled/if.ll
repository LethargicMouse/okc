; ModuleID = 'main'
source_filename = "main"
target triple = "x86_64-pc-linux-gnu"

@.s7 = private unnamed_addr constant [12 x i8] c"SIX SEVEEEN\00", align 1
@.s9 = private unnamed_addr constant [12 x i8] c"SIX SEVEEEN\00", align 1

declare i32 @puts(ptr)

define i32 @main() {
entry:
  %t0 = alloca i32, align 4
  store i32 67, ptr %t0, align 4
  %t1 = load i32, ptr %t0, align 4
  %t2 = icmp eq i32 %t1, 67
  br i1 %t2, label %s3, label %s4

s3:                                               ; preds = %entry
  %t6 = call i32 @puts(ptr @.s7)
  br label %s5

s4:                                               ; preds = %entry
  %t8 = call i32 @puts(ptr @.s9)
  br label %s5

s5:                                               ; preds = %s4, %s3
  ret i32 0
}
