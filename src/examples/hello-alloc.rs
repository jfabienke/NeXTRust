//! Example using allocator and I/O

#![no_std]
#![no_main]
#![feature(error_in_core)]

extern crate alloc;
extern crate nextstep_alloc;
extern crate nextstep_io;

use alloc::string::String;
use alloc::vec::Vec;
use nextstep_io::{println, eprintln};
use core::panic::PanicInfo;

#[no_mangle]
pub extern "C" fn main() -> i32 {
    println!("Hello from NeXTSTEP with allocation support!");
    
    // Test allocation
    let mut v = Vec::new();
    for i in 0..10 {
        v.push(i);
    }
    println!("Created vector: {:?}", v);
    
    // Test string allocation
    let s = String::from("Dynamic string on NeXTSTEP!");
    println!("String: {}", s);
    
    // Test larger allocation
    let big_vec: Vec<u8> = Vec::with_capacity(4096);
    println!("Allocated {} bytes", big_vec.capacity());
    
    0
}

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    eprintln!("PANIC: {}", info);
    nextstep_sys::sys_exit(1);
}