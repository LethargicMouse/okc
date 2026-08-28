watch:
  watchexec -c -w src -w examples "zig build test --color on 2>&1 | head -n 20"

run name:
  zig build run -- examples/{{name}}.ok
