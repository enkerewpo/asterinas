// SPDX-License-Identifier: MPL-2.0

//! This module offers `/proc/version` file support, which provides
//! information about the kernel version.
//!
//! Reference: <https://man7.org/linux/man-pages/man5/proc_version.5.html>

use alloc::format;

use crate::{
    fs::{
        procfs::template::{FileOps, ProcFileBuilder},
        utils::{mkmod, Inode},
    },
    net::UtsNamespace,
    prelude::*,
};

pub struct VersionFileOps;

impl VersionFileOps {
    pub fn new_inode(parent: Weak<dyn Inode>) -> Arc<dyn Inode> {
        ProcFileBuilder::new(Self, mkmod!(a+r))
            .parent(parent)
            .build()
            .unwrap()
    }

    fn collect_version() -> Result<String> {
        // Get UTS namespace information from the init namespace
        let uts_name = UtsNamespace::get_init_singleton().uts_name();

        let sysname = uts_name.sysname()?;
        let release = uts_name.release()?;
        let version = uts_name.version()?;

        let compile_by = option_env!("LINUX_COMPILE_BY").unwrap_or("unknown");
        let compile_host = option_env!("LINUX_COMPILE_HOST").unwrap_or("unknown");
        let compiler = option_env!("LINUX_COMPILER").unwrap_or("rustc, rust-lld");

        // Reference:
        // <https://elixir.bootlin.com/linux/v6.17/source/init/version.c>
        // <https://elixir.bootlin.com/linux/v6.17/source/fs/proc/version.c>
        Ok(format!(
            "{} version {} ({}@{}) ({}) {}\n",
            sysname, release, compile_by, compile_host, compiler, version
        ))
    }
}

impl FileOps for VersionFileOps {
    fn data(&self) -> Result<Vec<u8>> {
        let output = Self::collect_version()?;
        Ok(output.into_bytes())
    }
}
