watch:
  watchexec -w src -c -e zig zig build test

run name:
  zig build run -- examples/{{name}}.ok
