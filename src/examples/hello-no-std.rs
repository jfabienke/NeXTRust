#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // In a real implementation, we might write to console or halt
    loop {}
}

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Simple no-std program that writes "Hello NeXT!" to console using trap
    unsafe {
        // "Hello NeXT!\n" in ASCII bytes
        let msg = b"Hello NeXT!\n";
        
        // Use inline assembly to invoke NeXT syscall
        // This uses trap #0 for Mach system calls
        core::arch::asm!(
            // Push message pointer
            "move.l {msg}, -(sp)",
            // Push length (12 bytes)
            "move.l #12, -(sp)",
            // Push file descriptor (1 = stdout)
            "move.l #1, -(sp)",
            // System call number for write (4)
            "move.w #4, -(sp)",
            // Invoke Mach syscall
            "trap #0",
            // Clean up stack (14 bytes total)
            "add.l #14, sp",
            msg = in(reg) msg.as_ptr(),
            options(nostack)
        );
        
        // Exit with code 0
        core::arch::asm!(
            // Push exit code
            "move.l #0, -(sp)",
            // System call number for exit (1)
            "move.w #1, -(sp)",
            // Invoke syscall
            "trap #0",
            // This never returns
            options(noreturn, nostack)
        );
    }
}