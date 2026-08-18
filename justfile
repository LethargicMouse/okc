set shell := ["fish", "-c"]

watch:
  watchexec -w src -c -e zig "zig build test --color on 2>&1 | head -n $(math (tput lines) - 5)"

run name:
  zig build run -- examples/{{name}}.ok
