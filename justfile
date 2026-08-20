watch:
  watchexec -w src -c -e zig "zig build test --color on 2>&1 | head -n 20"

run name:
  zig build run -- examples/{{name}}.ok
