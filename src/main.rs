#![allow(unused)]

mod codegen;
mod compile;
mod display;
mod display_location;
mod lex;
mod parse;
mod source;

use crate::{compile::compile, display::LogError};
use std::{
    env::args,
    fmt::Display,
    process::{Command, exit},
};

fn main() {
    let mut args = args();
    // skip exec name
    args.next();
    match args.next() {
        Some(path) => run(&path),
        None => {
            eprintln!("{LogError} no source path given");
            exit(1)
        }
    }
}

fn run(path: &str) {
    compile(path);
    run_command("build/out", []);
}

fn run_command<'a>(name: &str, args: impl IntoIterator<Item = &'a str>) {
    let status = Command::new(name).args(args).status().unwrap();
    if !status.success() {
        exit(status.code().unwrap_or(1))
    }
}
