pub mod bundle;
pub mod transaction;
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
pub const EMBEDDED: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/bundle.zip"));
