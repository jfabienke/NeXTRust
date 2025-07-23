//! nextstep-io - Basic I/O support for NeXTSTEP
//! 
//! Provides console I/O and file operations using system calls

#![no_std]
#![feature(error_in_core)]

extern crate alloc;

use core::fmt;
use nextstep_sys::*;

/// Standard output handle
pub struct Stdout;

/// Standard error handle  
pub struct Stderr;

/// Standard input handle
pub struct Stdin;

/// Error type for I/O operations
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IoError {
    pub kind: IoErrorKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IoErrorKind {
    NotFound,
    PermissionDenied,
    ConnectionRefused,
    ConnectionReset,
    ConnectionAborted,
    NotConnected,
    AddrInUse,
    AddrNotAvailable,
    BrokenPipe,
    AlreadyExists,
    WouldBlock,
    InvalidInput,
    InvalidData,
    TimedOut,
    WriteZero,
    Interrupted,
    Other,
    UnexpectedEof,
}

impl From<i32> for IoError {
    fn from(errno: i32) -> Self {
        let kind = match errno {
            ENOENT => IoErrorKind::NotFound,
            EPERM | EACCES => IoErrorKind::PermissionDenied,
            EPIPE => IoErrorKind::BrokenPipe,
            EEXIST => IoErrorKind::AlreadyExists,
            EAGAIN => IoErrorKind::WouldBlock,
            EINTR => IoErrorKind::Interrupted,
            EINVAL => IoErrorKind::InvalidInput,
            _ => IoErrorKind::Other,
        };
        IoError { kind }
    }
}

impl fmt::Display for IoError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "I/O error: {:?}", self.kind)
    }
}

impl core::error::Error for IoError {}

pub type Result<T> = core::result::Result<T, IoError>;

/// Write trait for output streams
pub trait Write {
    fn write(&mut self, buf: &[u8]) -> Result<usize>;
    fn write_all(&mut self, buf: &[u8]) -> Result<()>;
    fn flush(&mut self) -> Result<()>;
}

/// Read trait for input streams
pub trait Read {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize>;
    fn read_exact(&mut self, buf: &mut [u8]) -> Result<()>;
}

impl Write for Stdout {
    fn write(&mut self, buf: &[u8]) -> Result<usize> {
        sys_write(STDOUT_FILENO, buf)
            .map_err(|_| IoError { kind: IoErrorKind::Other })
    }

    fn write_all(&mut self, mut buf: &[u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.write(buf) {
                Ok(0) => return Err(IoError { kind: IoErrorKind::WriteZero }),
                Ok(n) => buf = &buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    fn flush(&mut self) -> Result<()> {
        // No buffering, always flushed
        Ok(())
    }
}

impl Write for Stderr {
    fn write(&mut self, buf: &[u8]) -> Result<usize> {
        sys_write(STDERR_FILENO, buf)
            .map_err(|_| IoError { kind: IoErrorKind::Other })
    }

    fn write_all(&mut self, mut buf: &[u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.write(buf) {
                Ok(0) => return Err(IoError { kind: IoErrorKind::WriteZero }),
                Ok(n) => buf = &buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    fn flush(&mut self) -> Result<()> {
        Ok(())
    }
}

impl Read for Stdin {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        sys_read(STDIN_FILENO, buf)
            .map_err(|_| IoError { kind: IoErrorKind::Other })
    }

    fn read_exact(&mut self, mut buf: &mut [u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.read(buf) {
                Ok(0) => return Err(IoError { kind: IoErrorKind::UnexpectedEof }),
                Ok(n) => buf = &mut buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }
}

/// Get stdout handle
pub fn stdout() -> Stdout {
    Stdout
}

/// Get stderr handle
pub fn stderr() -> Stderr {
    Stderr
}

/// Get stdin handle
pub fn stdin() -> Stdin {
    Stdin
}

/// Write formatted output to stdout
impl fmt::Write for Stdout {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.write_all(s.as_bytes()).map_err(|_| fmt::Error)
    }
}

/// Write formatted output to stderr
impl fmt::Write for Stderr {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.write_all(s.as_bytes()).map_err(|_| fmt::Error)
    }
}

/// Print to stdout
#[macro_export]
macro_rules! print {
    ($($arg:tt)*) => {
        use core::fmt::Write;
        let _ = write!($crate::stdout(), $($arg)*);
    };
}

/// Print to stdout with newline
#[macro_export]
macro_rules! println {
    () => {
        $crate::print!("\n");
    };
    ($($arg:tt)*) => {
        use core::fmt::Write;
        let _ = write!($crate::stdout(), $($arg)*);
        let _ = $crate::stdout().write_str("\n");
    };
}

/// Print to stderr
#[macro_export]
macro_rules! eprint {
    ($($arg:tt)*) => {
        use core::fmt::Write;
        let _ = write!($crate::stderr(), $($arg)*);
    };
}

/// Print to stderr with newline
#[macro_export]
macro_rules! eprintln {
    () => {
        $crate::eprint!("\n");
    };
    ($($arg:tt)*) => {
        use core::fmt::Write;
        let _ = write!($crate::stderr(), $($arg)*);
        let _ = $crate::stderr().write_str("\n");
    };
}

/// File handle
pub struct File {
    fd: c_int,
}

impl File {
    /// Open a file
    pub fn open(path: &str, flags: i32, mode: mode_t) -> Result<File> {
        // Convert to null-terminated C string
        let mut path_buf = alloc::vec::Vec::with_capacity(path.len() + 1);
        path_buf.extend_from_slice(path.as_bytes());
        path_buf.push(0);
        
        match sys_open(&path_buf, flags, mode) {
            Ok(fd) => Ok(File { fd }),
            Err(e) => Err(IoError::from(e)),
        }
    }
    
    /// Create a new file
    pub fn create(path: &str) -> Result<File> {
        Self::open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o666)
    }
}

impl Read for File {
    fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        sys_read(self.fd, buf)
            .map_err(|e| IoError::from(e))
    }
    
    fn read_exact(&mut self, mut buf: &mut [u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.read(buf) {
                Ok(0) => return Err(IoError { kind: IoErrorKind::UnexpectedEof }),
                Ok(n) => buf = &mut buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }
}

impl Write for File {
    fn write(&mut self, buf: &[u8]) -> Result<usize> {
        sys_write(self.fd, buf)
            .map_err(|e| IoError::from(e))
    }
    
    fn write_all(&mut self, mut buf: &[u8]) -> Result<()> {
        while !buf.is_empty() {
            match self.write(buf) {
                Ok(0) => return Err(IoError { kind: IoErrorKind::WriteZero }),
                Ok(n) => buf = &buf[n..],
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }
    
    fn flush(&mut self) -> Result<()> {
        // No buffering
        Ok(())
    }
}

impl Drop for File {
    fn drop(&mut self) {
        let _ = sys_close(self.fd);
    }
}