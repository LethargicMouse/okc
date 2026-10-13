watch:
    watchexec -c -w src zig build test --watch --error-style minimal_clear

run name *args:
  zig build run {{args}} -- examples/{{name}}.ok
