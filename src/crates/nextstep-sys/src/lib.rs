//! nextstep-sys - Minimal NeXTSTEP system call bindings
//! 
//! Provides raw FFI bindings to NeXTSTEP system calls via trap #0

#![no_std]
#![allow(non_camel_case_types)]

use core::ffi::c_void;

// Type definitions
pub type c_int = i32;
pub type c_uint = u32;
pub type c_long = i32;
pub type c_ulong = u32;
pub type size_t = usize;
pub type ssize_t = isize;
pub type off_t = i32;
pub type pid_t = i32;
pub type uid_t = u32;
pub type gid_t = u32;
pub type mode_t = u16;
pub type time_t = i32;
pub type dev_t = i32;
pub type ino_t = u32;

// File flags for open()
pub const O_RDONLY: c_int = 0x0000;
pub const O_WRONLY: c_int = 0x0001;
pub const O_RDWR: c_int = 0x0002;
pub const O_NONBLOCK: c_int = 0x0004;
pub const O_APPEND: c_int = 0x0008;
pub const O_CREAT: c_int = 0x0200;
pub const O_TRUNC: c_int = 0x0400;
pub const O_EXCL: c_int = 0x0800;

// File mode bits
pub const S_IFMT: mode_t = 0o170000;
pub const S_IFDIR: mode_t = 0o040000;
pub const S_IFREG: mode_t = 0o100000;
pub const S_IFLNK: mode_t = 0o120000;
pub const S_IRUSR: mode_t = 0o400;
pub const S_IWUSR: mode_t = 0o200;
pub const S_IXUSR: mode_t = 0o100;
pub const S_IRGRP: mode_t = 0o040;
pub const S_IWGRP: mode_t = 0o020;
pub const S_IXGRP: mode_t = 0o010;
pub const S_IROTH: mode_t = 0o004;
pub const S_IWOTH: mode_t = 0o002;
pub const S_IXOTH: mode_t = 0o001;

// Seek whence values
pub const SEEK_SET: c_int = 0;
pub const SEEK_CUR: c_int = 1;
pub const SEEK_END: c_int = 2;

// Error codes
pub const EPERM: c_int = 1;
pub const ENOENT: c_int = 2;
pub const ESRCH: c_int = 3;
pub const EINTR: c_int = 4;
pub const EIO: c_int = 5;
pub const ENXIO: c_int = 6;
pub const E2BIG: c_int = 7;
pub const ENOEXEC: c_int = 8;
pub const EBADF: c_int = 9;
pub const ECHILD: c_int = 10;
pub const EAGAIN: c_int = 11;
pub const ENOMEM: c_int = 12;
pub const EACCES: c_int = 13;
pub const EFAULT: c_int = 14;
pub const ENOTBLK: c_int = 15;
pub const EBUSY: c_int = 16;
pub const EEXIST: c_int = 17;
pub const EXDEV: c_int = 18;
pub const ENODEV: c_int = 19;
pub const ENOTDIR: c_int = 20;
pub const EISDIR: c_int = 21;
pub const EINVAL: c_int = 22;
pub const ENFILE: c_int = 23;
pub const EMFILE: c_int = 24;
pub const ENOTTY: c_int = 25;
pub const ETXTBSY: c_int = 26;
pub const EFBIG: c_int = 27;
pub const ENOSPC: c_int = 28;
pub const ESPIPE: c_int = 29;
pub const EROFS: c_int = 30;
pub const EMLINK: c_int = 31;
pub const EPIPE: c_int = 32;

// Mach VM constants
pub const VM_PROT_NONE: c_int = 0;
pub const VM_PROT_READ: c_int = 1;
pub const VM_PROT_WRITE: c_int = 2;
pub const VM_PROT_EXECUTE: c_int = 4;
pub const VM_PROT_DEFAULT: c_int = VM_PROT_READ | VM_PROT_WRITE;

// Mach error codes
pub const KERN_SUCCESS: c_int = 0;
pub const KERN_INVALID_ADDRESS: c_int = 1;
pub const KERN_PROTECTION_FAILURE: c_int = 2;
pub const KERN_NO_SPACE: c_int = 3;
pub const KERN_INVALID_ARGUMENT: c_int = 4;
pub const KERN_FAILURE: c_int = 5;
pub const KERN_RESOURCE_SHORTAGE: c_int = 6;

// stat structure for NeXTSTEP
#[repr(C)]
pub struct stat {
    pub st_dev: dev_t,
    pub st_ino: ino_t,
    pub st_mode: mode_t,
    pub st_nlink: u16,
    pub st_uid: uid_t,
    pub st_gid: gid_t,
    pub st_rdev: dev_t,
    pub st_size: off_t,
    pub st_atime: time_t,
    pub st_spare1: c_int,
    pub st_mtime: time_t,
    pub st_spare2: c_int,
    pub st_ctime: time_t,
    pub st_spare3: c_int,
    pub st_blksize: c_long,
    pub st_blocks: c_long,
    pub st_spare4: [c_long; 2],
}

// timeval structure
#[repr(C)]
pub struct timeval {
    pub tv_sec: time_t,
    pub tv_usec: c_long,
}

// timezone structure
#[repr(C)]
pub struct timezone {
    pub tz_minuteswest: c_int,
    pub tz_dsttime: c_int,
}

// File descriptors
pub const STDIN_FILENO: i32 = 0;
pub const STDOUT_FILENO: i32 = 1;
pub const STDERR_FILENO: i32 = 2;

// System call numbers for trap #0
pub const SYS_EXIT: i32 = 1;
pub const SYS_FORK: i32 = 2;
pub const SYS_READ: i32 = 3;
pub const SYS_WRITE: i32 = 4;
pub const SYS_OPEN: i32 = 5;
pub const SYS_CLOSE: i32 = 6;
pub const SYS_WAIT4: i32 = 7;
pub const SYS_LINK: i32 = 9;
pub const SYS_UNLINK: i32 = 10;
pub const SYS_CHDIR: i32 = 12;
pub const SYS_MKNOD: i32 = 14;
pub const SYS_CHMOD: i32 = 15;
pub const SYS_CHOWN: i32 = 16;
pub const SYS_LSEEK: i32 = 19;
pub const SYS_GETPID: i32 = 20;
pub const SYS_MOUNT: i32 = 21;
pub const SYS_UMOUNT: i32 = 22;
pub const SYS_SETUID: i32 = 23;
pub const SYS_GETUID: i32 = 24;
pub const SYS_GETEUID: i32 = 25;
pub const SYS_ACCESS: i32 = 33;
pub const SYS_SYNC: i32 = 36;
pub const SYS_KILL: i32 = 37;
pub const SYS_STAT: i32 = 38;
pub const SYS_GETPPID: i32 = 39;
pub const SYS_DUP: i32 = 41;
pub const SYS_PIPE: i32 = 42;
pub const SYS_GETGID: i32 = 47;
pub const SYS_GETEGID: i32 = 48;
pub const SYS_IOCTL: i32 = 54;
pub const SYS_SYMLINK: i32 = 57;
pub const SYS_READLINK: i32 = 58;
pub const SYS_EXECVE: i32 = 59;
pub const SYS_UMASK: i32 = 60;
pub const SYS_CHROOT: i32 = 61;
pub const SYS_FSTAT: i32 = 62;
pub const SYS_GETPAGESIZE: i32 = 64;
pub const SYS_VFORK: i32 = 66;
pub const SYS_SBRK: i32 = 69;
pub const SYS_MMAP: i32 = 71;
pub const SYS_MUNMAP: i32 = 73;
pub const SYS_MPROTECT: i32 = 74;
pub const SYS_GETTIMEOFDAY: i32 = 116;
pub const SYS_GETRUSAGE: i32 = 117;
pub const SYS_GETSOCKOPT: i32 = 118;
pub const SYS_READV: i32 = 120;
pub const SYS_WRITEV: i32 = 121;
pub const SYS_SETTIMEOFDAY: i32 = 122;
pub const SYS_FCHOWN: i32 = 123;
pub const SYS_FCHMOD: i32 = 124;
pub const SYS_RENAME: i32 = 128;
pub const SYS_TRUNCATE: i32 = 129;
pub const SYS_FTRUNCATE: i32 = 130;
pub const SYS_FLOCK: i32 = 131;
pub const SYS_MKDIR: i32 = 136;
pub const SYS_RMDIR: i32 = 137;
pub const SYS_UTIMES: i32 = 138;
pub const SYS_GETDIRENTRIES: i32 = 156;

// Mach VM syscalls (negative numbers)
pub const SYS_VM_ALLOCATE: i32 = -64;
pub const SYS_VM_DEALLOCATE: i32 = -65;
pub const SYS_VM_PROTECT: i32 = -66;
pub const SYS_VM_INHERIT: i32 = -67;
pub const SYS_VM_READ: i32 = -68;
pub const SYS_VM_WRITE: i32 = -69;
pub const SYS_VM_COPY: i32 = -70;
pub const SYS_VM_REGION: i32 = -71;
pub const SYS_VM_STATISTICS: i32 = -72;
pub const SYS_TASK_CREATE: i32 = -168;

// Raw system call interface
#[link(name = "System")]
extern "C" {
    // Process control
    pub fn _exit(status: i32) -> !;
    pub fn fork() -> pid_t;
    pub fn vfork() -> pid_t;
    pub fn getpid() -> pid_t;
    pub fn getppid() -> pid_t;
    pub fn getuid() -> uid_t;
    pub fn geteuid() -> uid_t;
    pub fn getgid() -> gid_t;
    pub fn getegid() -> gid_t;
    pub fn setuid(uid: uid_t) -> c_int;
    pub fn kill(pid: pid_t, sig: c_int) -> c_int;
    pub fn wait4(pid: pid_t, status: *mut c_int, options: c_int, rusage: *mut c_void) -> pid_t;
    pub fn execve(path: *const u8, argv: *const *const u8, envp: *const *const u8) -> c_int;
    
    // File I/O
    pub fn open(path: *const u8, flags: c_int, mode: mode_t) -> c_int;
    pub fn close(fd: c_int) -> c_int;
    pub fn read(fd: c_int, buf: *mut u8, count: size_t) -> ssize_t;
    pub fn write(fd: c_int, buf: *const u8, count: size_t) -> ssize_t;
    pub fn lseek(fd: c_int, offset: off_t, whence: c_int) -> off_t;
    pub fn dup(fd: c_int) -> c_int;
    pub fn pipe(pipefd: *mut c_int) -> c_int;
    pub fn readv(fd: c_int, iov: *const c_void, iovcnt: c_int) -> ssize_t;
    pub fn writev(fd: c_int, iov: *const c_void, iovcnt: c_int) -> ssize_t;
    
    // File operations
    pub fn stat(path: *const u8, buf: *mut stat) -> c_int;
    pub fn fstat(fd: c_int, buf: *mut stat) -> c_int;
    pub fn chmod(path: *const u8, mode: mode_t) -> c_int;
    pub fn fchmod(fd: c_int, mode: mode_t) -> c_int;
    pub fn chown(path: *const u8, owner: uid_t, group: gid_t) -> c_int;
    pub fn fchown(fd: c_int, owner: uid_t, group: gid_t) -> c_int;
    pub fn access(path: *const u8, mode: c_int) -> c_int;
    pub fn umask(mask: mode_t) -> mode_t;
    pub fn truncate(path: *const u8, length: off_t) -> c_int;
    pub fn ftruncate(fd: c_int, length: off_t) -> c_int;
    pub fn flock(fd: c_int, operation: c_int) -> c_int;
    
    // Directory operations
    pub fn chdir(path: *const u8) -> c_int;
    pub fn chroot(path: *const u8) -> c_int;
    pub fn mkdir(path: *const u8, mode: mode_t) -> c_int;
    pub fn rmdir(path: *const u8) -> c_int;
    pub fn getdirentries(fd: c_int, buf: *mut u8, nbytes: c_int, basep: *mut c_long) -> c_int;
    
    // Link operations
    pub fn link(from: *const u8, to: *const u8) -> c_int;
    pub fn unlink(path: *const u8) -> c_int;
    pub fn symlink(from: *const u8, to: *const u8) -> c_int;
    pub fn readlink(path: *const u8, buf: *mut u8, bufsiz: size_t) -> ssize_t;
    pub fn rename(from: *const u8, to: *const u8) -> c_int;
    
    // Time operations
    pub fn gettimeofday(tv: *mut timeval, tz: *mut timezone) -> c_int;
    pub fn settimeofday(tv: *const timeval, tz: *const timezone) -> c_int;
    pub fn utimes(path: *const u8, times: *const timeval) -> c_int;
    
    // Memory operations
    pub fn sbrk(increment: isize) -> *mut c_void;
    pub fn mmap(addr: *mut c_void, len: size_t, prot: c_int, flags: c_int, fd: c_int, offset: off_t) -> *mut c_void;
    pub fn munmap(addr: *mut c_void, len: size_t) -> c_int;
    pub fn mprotect(addr: *mut c_void, len: size_t, prot: c_int) -> c_int;
    
    // System operations
    pub fn sync() -> c_int;
    pub fn getpagesize() -> c_int;
    pub fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    pub fn mount(special: *const u8, name: *const u8, flags: c_int, data: *mut c_void) -> c_int;
    pub fn umount(special: *const u8) -> c_int;
    pub fn getrusage(who: c_int, usage: *mut c_void) -> c_int;
    pub fn getsockopt(s: c_int, level: c_int, optname: c_int, optval: *mut c_void, optlen: *mut c_uint) -> c_int;
    pub fn mknod(path: *const u8, mode: mode_t, dev: dev_t) -> c_int;
}

// Mach VM system calls
// These use negative syscall numbers and different calling conventions
#[link(name = "System")]
extern "C" {
    // VM operations
    pub fn vm_allocate(target_task: c_int, address: *mut *mut c_void, size: size_t, anywhere: c_int) -> c_int;
    pub fn vm_deallocate(target_task: c_int, address: *mut c_void, size: size_t) -> c_int;
    pub fn vm_protect(target_task: c_int, address: *mut c_void, size: size_t, set_maximum: c_int, new_protection: c_int) -> c_int;
    pub fn vm_inherit(target_task: c_int, address: *mut c_void, size: size_t, new_inheritance: c_int) -> c_int;
    pub fn vm_read(target_task: c_int, address: *mut c_void, size: size_t, data: *mut *mut c_void, data_count: *mut size_t) -> c_int;
    pub fn vm_write(target_task: c_int, address: *mut c_void, data: *const c_void, data_count: size_t) -> c_int;
    pub fn vm_copy(target_task: c_int, source_address: *mut c_void, count: size_t, dest_address: *mut c_void) -> c_int;
    pub fn vm_region(target_task: c_int, address: *mut *mut c_void, size: *mut size_t, protection: *mut c_int, max_protection: *mut c_int, inheritance: *mut c_int, shared: *mut c_int, object_name: *mut c_int, offset: *mut size_t) -> c_int;
    pub fn vm_statistics(target_task: c_int, info: *mut c_void) -> c_int;
    
    // Task operations
    pub fn task_create(parent_task: c_int, inherit_memory: c_int, child_task: *mut c_int) -> c_int;
    pub fn task_self() -> c_int;
}

/// Safe wrapper for write syscall
#[inline]
pub fn sys_write(fd: i32, data: &[u8]) -> Result<usize, i32> {
    let ret = unsafe { write(fd, data.as_ptr(), data.len()) };
    if ret < 0 {
        Err(-1)
    } else {
        Ok(ret as usize)
    }
}

/// Safe wrapper for read syscall
#[inline]
pub fn sys_read(fd: i32, buf: &mut [u8]) -> Result<usize, i32> {
    let ret = unsafe { read(fd, buf.as_mut_ptr(), buf.len()) };
    if ret < 0 {
        Err(-1)
    } else {
        Ok(ret as usize)
    }
}

/// Safe wrapper for open syscall
#[inline]
pub fn sys_open(path: &[u8], flags: i32, mode: mode_t) -> Result<i32, i32> {
    let ret = unsafe { open(path.as_ptr(), flags, mode) };
    if ret < 0 {
        Err(-1)
    } else {
        Ok(ret)
    }
}

/// Safe wrapper for close syscall
#[inline]
pub fn sys_close(fd: i32) -> Result<(), i32> {
    let ret = unsafe { close(fd) };
    if ret < 0 {
        Err(-1)
    } else {
        Ok(())
    }
}

/// Safe wrapper for exit syscall
#[inline]
pub fn sys_exit(code: i32) -> ! {
    unsafe { _exit(code) }
}

/// Safe wrapper for getpid syscall
#[inline] 
pub fn sys_getpid() -> pid_t {
    unsafe { getpid() }
}

/// Safe wrapper for vm_allocate
#[inline]
pub fn sys_vm_allocate(size: usize, anywhere: bool) -> Result<*mut c_void, i32> {
    let mut addr: *mut c_void = core::ptr::null_mut();
    let ret = unsafe {
        vm_allocate(
            task_self(),
            &mut addr,
            size,
            if anywhere { 1 } else { 0 }
        )
    };
    if ret != KERN_SUCCESS {
        Err(ret)
    } else {
        Ok(addr)
    }
}

/// Safe wrapper for vm_deallocate
#[inline]
pub fn sys_vm_deallocate(addr: *mut c_void, size: usize) -> Result<(), i32> {
    let ret = unsafe {
        vm_deallocate(task_self(), addr, size)
    };
    if ret != KERN_SUCCESS {
        Err(ret)
    } else {
        Ok(())
    }
}

/// Constants for current task
pub const TASK_SELF: c_int = 0;

// Additional type definitions for NeXTSTEP
pub type vm_offset_t = c_ulong;
pub type vm_size_t = c_ulong;
pub type vm_address_t = vm_offset_t;
pub type mach_port_t = c_int;
pub type kern_return_t = c_int;

// VM inheritance values
pub const VM_INHERIT_SHARE: c_int = 0;
pub const VM_INHERIT_COPY: c_int = 1;
pub const VM_INHERIT_NONE: c_int = 2;

// Signal numbers
pub const SIGHUP: c_int = 1;
pub const SIGINT: c_int = 2;
pub const SIGQUIT: c_int = 3;
pub const SIGILL: c_int = 4;
pub const SIGTRAP: c_int = 5;
pub const SIGABRT: c_int = 6;
pub const SIGEMT: c_int = 7;
pub const SIGFPE: c_int = 8;
pub const SIGKILL: c_int = 9;
pub const SIGBUS: c_int = 10;
pub const SIGSEGV: c_int = 11;
pub const SIGSYS: c_int = 12;
pub const SIGPIPE: c_int = 13;
pub const SIGALRM: c_int = 14;
pub const SIGTERM: c_int = 15;

// Wait options
pub const WNOHANG: c_int = 1;
pub const WUNTRACED: c_int = 2;

// Helper macros for wait status
#[inline]
pub fn WIFEXITED(status: c_int) -> bool {
    (status & 0xff) == 0
}

#[inline]
pub fn WEXITSTATUS(status: c_int) -> c_int {
    (status >> 8) & 0xff
}

#[inline]
pub fn WIFSIGNALED(status: c_int) -> bool {
    ((status & 0xff) != 0) && ((status & 0xff) != 0x7f)
}

#[inline]
pub fn WTERMSIG(status: c_int) -> c_int {
    status & 0x7f
}

// dirent structure for getdirentries
#[repr(C)]
pub struct dirent {
    pub d_ino: ino_t,
    pub d_reclen: u16,
    pub d_type: u8,
    pub d_namlen: u8,
    pub d_name: [u8; 256],
}

// iovec structure for readv/writev
#[repr(C)]
pub struct iovec {
    pub iov_base: *mut c_void,
    pub iov_len: size_t,
}

// rusage structure for getrusage
#[repr(C)]
pub struct rusage {
    pub ru_utime: timeval,    // user time used
    pub ru_stime: timeval,    // system time used
    pub ru_maxrss: c_long,    // max resident set size
    pub ru_ixrss: c_long,     // integral shared text memory size
    pub ru_idrss: c_long,     // integral unshared data size
    pub ru_isrss: c_long,     // integral unshared stack size
    pub ru_minflt: c_long,    // page reclaims
    pub ru_majflt: c_long,    // page faults
    pub ru_nswap: c_long,     // swaps
    pub ru_inblock: c_long,   // block input operations
    pub ru_oublock: c_long,   // block output operations
    pub ru_msgsnd: c_long,    // messages sent
    pub ru_msgrcv: c_long,    // messages received
    pub ru_nsignals: c_long,  // signals received
    pub ru_nvcsw: c_long,     // voluntary context switches
    pub ru_nivcsw: c_long,    // involuntary context switches
}

// Who values for getrusage
pub const RUSAGE_SELF: c_int = 0;
pub const RUSAGE_CHILDREN: c_int = -1;

// mmap constants
pub const MAP_SHARED: c_int = 0x0001;
pub const MAP_PRIVATE: c_int = 0x0002;
pub const MAP_FIXED: c_int = 0x0010;
pub const MAP_ANON: c_int = 0x1000;
pub const MAP_FILE: c_int = 0x0000;

// fcntl operations (for future use)
pub const F_DUPFD: c_int = 0;
pub const F_GETFD: c_int = 1;
pub const F_SETFD: c_int = 2;
pub const F_GETFL: c_int = 3;
pub const F_SETFL: c_int = 4;