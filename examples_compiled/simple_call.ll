; ModuleID = 'main'
source_filename = "main"
target triple = "x86_64-pc-linux-gnu"

@.s1 = private unnamed_addr constant [12 x i8] c"hello world\00", align 1

declare i32 @puts(ptr)

define i32 @main() {
entry:
  %t0 = call i32 @puts(ptr @.s1)
  ret i32 0
}
