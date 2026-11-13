watch:
    watchexec -c -w Std -w Std.ok -w Std_Test.ok -w src "zig build test --error-style minimal_clear 2>&1 | head -n20"

run name *args:
  zig build run {{args}} -- examples/{{name}}.ok
