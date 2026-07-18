; ModuleID = 'main'
source_filename = "main"
target triple = "x86_64-pc-linux-gnu"

@.s0 = private unnamed_addr constant [13 x i8] c"wazzup nigas\00", align 1

declare i32 @puts(ptr)

define i32 @main() {
entry:
  %t1 = call i32 @puts(ptr @.s0)
  ret i32 0
}
