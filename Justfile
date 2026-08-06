test:
  gleam test

review:
  gleam run -m birdie

help:
	gleam run -- --help

input := env("INPUT")

run:
	gleam run -- --file {{input}}
