pub mod api;
pub mod feed;
pub mod ffi;
pub mod i18n;
pub mod import;
pub mod locale;
pub mod perf;
pub mod proxy;
pub mod recommend;
pub mod shorts_preload;
pub mod store;
pub mod url_util;

uniffi::setup_scaffolding!();
