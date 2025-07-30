#![no_std]
#![no_main]
#![no_builtins]

// Extremely minimal test to verify M68k code generation
// Avoids compiler_builtins entirely

#[no_mangle]
pub extern "C" fn _start() -> ! {
    loop {}
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}