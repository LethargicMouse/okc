; ModuleID = 'main'
source_filename = "main"
target triple = "x86_64-pc-linux-gnu"

@.s0 = private unnamed_addr constant [13 x i8] c"wazzup nigas\00", align 1
@.s2 = private unnamed_addr constant [20 x i8] c"oh gotta go nvm bye\00", align 1

declare i32 @puts(ptr)

define i32 @main() {
entry:
  %t1 = alloca ptr, align 8
  store ptr @.s0, ptr %t1, align 8
  store ptr @.s2, ptr %t1, align 8
  %t4 = load ptr, ptr %t1, align 8
  %t3 = call i32 @puts(ptr %t4)
  ret i32 0
}
