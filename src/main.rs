mod codegen;
mod compile;
mod display_location;
mod lex;
mod parse;
mod source;

use crate::compile::compile;
use std::{
    env::args,
    fmt::Display,
    process::{Command, exit},
};

// untestable
fn main() {
    let mut args = args();
    // skip exec name
    args.next();
    match args.next() {
        Some(path) => run(&path),
        None => die(NoPathGiven),
    }
}

struct NoPathGiven;

impl Display for NoPathGiven {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{RED}error:{RESET} no source path given")
    }
}

// untestable
fn run(path: &str) {
    compile(path);
    run_command("build/out", []);
}

// untestable
fn run_command(name: &str, args: impl IntoIterator<Item = &'static str>) {
    let status = Command::new(name).args(args).status().unwrap();
    if !status.success() {
        exit(status.code().unwrap_or(1))
    }
}

// untestable
fn die(e: impl Display) -> ! {
    eprintln!("{e}");
    exit(1)
}

const RED: &str = "\x1b[0;31m";
const RESET: &str = "\x1b[0m";
