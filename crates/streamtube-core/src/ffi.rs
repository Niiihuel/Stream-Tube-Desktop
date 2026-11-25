//! UniFFI bindings exposing StreamTube's Rust core to Swift / iOS.
use crate::api::{auth, innertube, services, streams, types, web};
use crate::{feed, import, proxy, recommend, store, url_util};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("{message}")]
    Api { message: String },
    #[error("{message}")]
    Storage { message: String },
    #[error("{message}")]
    InvalidInput { message: String },
}

impl From<anyhow::Error> for CoreError {
    fn from(err: anyhow::Error) -> Self {
        Self::Api {
            message: format!("{err:#}"),
        }
    }
}

// ───────────────────────── Core Data Models ─────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiVideoItem {
    pub id: String,
    pub title: String,
    pub channel_name: String,
    pub channel_id: Option<String>,
    pub channel_avatar: Option<String>,
    pub thumbnail: String,
    pub compact_thumbnail: Option<String>,
    pub duration_text: Option<String>,
    pub duration_secs: Option<u64>,
    pub views_text: Option<String>,
    pub published_text: Option<String>,
    pub published_ts: Option<i64>,
    pub description_snippet: Option<String>,
    pub is_live: bool,
    pub is_short: bool,
    pub is_upcoming: bool,
    pub playlist_id: Option<String>,
    pub resume_progress: Option<f64>,
}

impl FfiVideoItem {
    fn from_core(mut v: types::VideoItem, settings: &store::Settings, progress: Option<&HashMap<String, (f64, f64)>>) -> Self {
        if settings.dearrow_titles || settings.dearrow_thumbnails {
            if let Some(Some(b)) = services::branding_cached(&v.id) {
                if settings.dearrow_titles {
                    if let Some(t) = b.title {
                        v.title = t;
                    }
                }
                if settings.dearrow_thumbnails {
                    if let Some(ts) = b.thumbnail_time {
                        v.thumbnail = services::dearrow_thumbnail_url(&v.id, ts);
                    }
                }
            }
        }
        let resume_progress = progress
            .and_then(|m| m.get(&v.id))
            .and_then(|(pos, dur)| {
                if *dur > 0.0 && *pos > 2.0 {
                    Some((*pos / *dur).clamp(0.0, 1.0))
                } else {
                    None
                }
            });
        Self {
            id: v.id,
            title: v.title,
            channel_name: v.channel_name,
            channel_id: v.channel_id,
            channel_avatar: v.channel_avatar,
            thumbnail: v.thumbnail,
            compact_thumbnail: v.compact_thumbnail,
            duration_text: v.duration_text,
            duration_secs: v.duration_secs,
            views_text: v.views_text,
            published_text: v.published_text,
            published_ts: v.published_ts,
            description_snippet: v.description_snippet,
            is_live: v.is_live,
            is_short: v.is_short,
            is_upcoming: v.is_upcoming,
            playlist_id: v.playlist_id,
            resume_progress,
        }
    }

    fn into_core(self) -> types::VideoItem {
        types::VideoItem {
            id: self.id,
            title: self.title,
            channel_name: self.channel_name,
            channel_id: self.channel_id,
            channel_avatar: self.channel_avatar,
            thumbnail: self.thumbnail,
            compact_thumbnail: self.compact_thumbnail,
            duration_text: self.duration_text,
            duration_secs: self.duration_secs,
            views_text: self.views_text,
            published_text: self.published_text,
            published_ts: self.published_ts,
            description_snippet: self.description_snippet,
            is_live: self.is_live,
            is_short: self.is_short,
            is_upcoming: self.is_upcoming,
            playlist_id: self.playlist_id,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiChannelItem {
    pub id: String,
    pub name: String,
    pub avatar: Option<String>,
    pub handle: Option<String>,
    pub subscribers_text: Option<String>,
    pub video_count_text: Option<String>,
    pub description: Option<String>,
}

impl From<types::ChannelItem> for FfiChannelItem {
    fn from(c: types::ChannelItem) -> Self {
        Self {
            id: c.id,
            name: c.name,
            avatar: c.avatar,
            handle: c.handle,
            subscribers_text: c.subscribers_text,
            video_count_text: c.video_count_text,
            description: c.description,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiPlaylistItem {
    pub id: String,
    pub title: String,
    pub thumbnail: Option<String>,
    pub channel_name: Option<String>,
    pub channel_id: Option<String>,
    pub video_count_text: Option<String>,
    pub first_video_id: Option<String>,
}

impl From<types::PlaylistItem> for FfiPlaylistItem {
    fn from(p: types::PlaylistItem) -> Self {
        Self {
            id: p.id,
            title: p.title,
            thumbnail: p.thumbnail,
            channel_name: p.channel_name,
            channel_id: p.channel_id,
            video_count_text: p.video_count_text,
            first_video_id: p.first_video_id,
        }
    }
}

#[derive(Clone, Debug, uniffi::Enum)]
pub enum FfiFeedItem {
    Video { video: FfiVideoItem },
    Channel { channel: FfiChannelItem },
    Playlist { playlist: FfiPlaylistItem },
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiFeedPage {
    pub items: Vec<FfiFeedItem>,
    pub continuation: Option<String>,
    /// "auth_tv" | "auth_web" | "local_recommend" | "explore" | "search" | "browse"
    pub source: String,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiExploreCategory {
    pub name: String,
    pub channel_id: String,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiShortsPage {
    pub videos: Vec<FfiVideoItem>,
    pub continuation: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiSearchFilter {
    /// 0 relevance, 1 rating, 2 upload date, 3 view count
    pub sort: u8,
    /// 0 any, 1 hour, 2 today, 3 week, 4 month, 5 year
    pub date: u8,
    /// 0 any, 1 video, 2 channel, 3 playlist
    pub kind: u8,
    /// 0 any, 1 short (<4m), 2 long (>20m), 3 medium (4-20m)
    pub duration: u8,
    pub hd: bool,
    pub subtitles: bool,
    pub live: bool,
    pub four_k: bool,
}

impl Default for FfiSearchFilter {
    fn default() -> Self {
        Self {
            sort: 0,
            date: 0,
            kind: 0,
            duration: 0,
            hd: false,
            subtitles: false,
            live: false,
            four_k: false,
        }
    }
}

#[derive(Clone, Debug, uniffi::Enum)]
pub enum FfiResolvedTarget {
    Video { video_id: String },
    Channel { channel_id: String },
    Playlist { playlist_id: String },
}

// ───────────────────────── Playback, SponsorBlock & Watch ─────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiQualityOption {
    pub height: u32,
    pub fps: u32,
    pub label: String,
    pub codecs: String,
    pub bitrate: u64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiAudioTrack {
    pub language_code: String,
    pub display_name: String,
    pub is_original: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiCaptionTrack {
    pub lang: String,
    pub name: String,
    pub vtt_url: String,
    pub auto_generated: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiPlaybackBundle {
    pub video_id: String,
    pub title: String,
    pub author: String,
    pub channel_id: String,
    pub duration_secs: u64,
    pub is_live: bool,
    /// Local loopback proxy URL (HLS `.m3u8` or ranged MP4) ready for iOS `AVPlayer`.
    pub stream_url: String,
    /// Direct upstream HLS manifest URL as fallback.
    pub direct_hls_url: Option<String>,
    pub source_client: String,
    pub qualities: Vec<FfiQualityOption>,
    pub selected_max_height: u32,
    pub audio_tracks: Vec<FfiAudioTrack>,
    pub selected_audio: Option<String>,
    pub captions: Vec<FfiCaptionTrack>,
    pub resume_position_secs: f64,
    pub playback_speed: f64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiSponsorSegment {
    pub uuid: String,
    pub category: String,
    pub category_title: String,
    /// "skip" | "show" | "mute" | "poi"
    pub action: String,
    pub start_secs: f64,
    pub end_secs: f64,
    /// 0xRRGGBB hex color
    pub color_rgb: u32,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiChapter {
    pub title: String,
    pub start_secs: f64,
    pub thumbnail: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiHeatmapPoint {
    pub start_secs: f64,
    pub duration_secs: f64,
    pub intensity: f32,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiVotes {
    pub likes: u64,
    pub dislikes: u64,
    pub views: u64,
    pub rating: f64,
    pub likes_compact: String,
    pub dislikes_compact: String,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiWatchDetails {
    pub id: String,
    pub title: String,
    pub views_text: String,
    pub date_text: String,
    pub likes_text: Option<String>,
    pub description: String,
    pub channel: FfiChannelItem,
    pub is_subscribed: bool,
    pub user_rating: i8,
    pub is_live: bool,
    pub chapters: Vec<FfiChapter>,
    pub heatmap: Vec<FfiHeatmapPoint>,
    pub sponsor_segments: Vec<FfiSponsorSegment>,
    pub votes: Option<FfiVotes>,
    pub related: Vec<FfiFeedItem>,
    pub related_continuation: Option<String>,
    pub comments_token: Option<String>,
    pub comments_top_token: Option<String>,
    pub comments_newest_token: Option<String>,
    pub comment_count_text: Option<String>,
    pub live_chat_top_token: Option<String>,
    pub live_chat_all_token: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiComment {
    pub id: String,
    pub author: String,
    pub author_id: Option<String>,
    pub author_avatar: Option<String>,
    pub text: String,
    pub published: String,
    pub likes: String,
    pub reply_count: String,
    pub replies_token: Option<String>,
    pub is_creator: bool,
    pub is_verified: bool,
    pub is_pinned: bool,
    pub hearted: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiCommentPage {
    pub comments: Vec<FfiComment>,
    pub continuation: Option<String>,
    pub count_text: Option<String>,
    pub sort_top_token: Option<String>,
    pub sort_new_token: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiChatMessage {
    pub id: String,
    pub author: String,
    pub author_photo: Option<String>,
    pub text: String,
    pub role: String,
    pub verified: bool,
    pub paid: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiChatBatch {
    pub messages: Vec<FfiChatMessage>,
    pub next_token: Option<String>,
    pub timeout_ms: u64,
}

// ───────────────────────── Channels, Playlists, Subscriptions & Store ─────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiChannelTab {
    pub title: String,
    pub kind: String,
    pub params: Option<String>,
    pub selected: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiChannelPage {
    pub info: FfiChannelItem,
    pub banner: Option<String>,
    pub is_subscribed: bool,
    pub tabs: Vec<FfiChannelTab>,
    pub items: Vec<FfiFeedItem>,
    pub continuation: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiPlaylistPage {
    pub info: FfiPlaylistItem,
    pub description: Option<String>,
    pub videos: Vec<FfiVideoItem>,
    pub continuation: Option<String>,
    pub is_saved: bool,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiSubscription {
    pub channel_id: String,
    pub name: String,
    pub avatar: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiRefreshResult {
    pub videos: Vec<FfiVideoItem>,
    pub failed_channels: u32,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiLocalPlaylist {
    pub id: i64,
    pub name: String,
    pub is_protected: bool,
    pub count: u32,
    pub thumbnail: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiHistoryEntry {
    pub video: FfiVideoItem,
    pub watched_at: i64,
    pub progress_secs: f64,
    pub duration_secs: f64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiSettings {
    pub region: String,
    pub language: String,
    pub default_quality: u32,
    pub default_speed: f64,
    pub remember_speed_per_channel: bool,
    pub autoplay_next: bool,
    pub resume_playback: bool,
    pub background_play: bool,
    pub original_audio: bool,
    pub sponsorblock: bool,
    pub sponsorblock_server: String,
    pub sb_skip_sponsors: bool,
    pub sb_skip_selfpromo: bool,
    pub sb_skip_interaction: bool,
    pub sb_skip_intro: bool,
    pub sb_skip_outro: bool,
    pub sb_skip_preview: bool,
    pub sb_skip_filler: bool,
    pub sb_skip_music_offtopic: bool,
    pub sb_notify: bool,
    pub dearrow_titles: bool,
    pub dearrow_thumbnails: bool,
    pub ryd: bool,
    pub hide_shorts: bool,
    pub hide_live: bool,
    pub hide_upcoming: bool,
    pub hide_comments: bool,
    pub hide_related: bool,
    pub hide_watched_in_feed: bool,
    pub history_enabled: bool,
    pub search_history_enabled: bool,
    pub ipv4_only: bool,
    pub proxy: String,
    pub blocked_keywords: Vec<String>,
}

impl FfiSettings {
    fn from_store(s: &store::Settings) -> Self {
        let skips = |cat: &str| s.sb_actions.get(cat).map(|a| a == "skip").unwrap_or(false);
        Self {
            region: s.region.clone(),
            language: s.language.clone(),
            default_quality: s.default_quality,
            default_speed: s.default_speed,
            remember_speed_per_channel: s.remember_speed_per_channel,
            autoplay_next: s.autoplay_next,
            resume_playback: s.resume_playback,
            background_play: s.background_play,
            original_audio: s.original_audio,
            sponsorblock: s.sponsorblock,
            sponsorblock_server: s.sponsorblock_server.clone(),
            sb_skip_sponsors: skips("sponsor"),
            sb_skip_selfpromo: skips("selfpromo"),
            sb_skip_interaction: skips("interaction"),
            sb_skip_intro: skips("intro"),
            sb_skip_outro: skips("outro"),
            sb_skip_preview: skips("preview"),
            sb_skip_filler: skips("filler"),
            sb_skip_music_offtopic: skips("music_offtopic"),
            sb_notify: s.sb_notify,
            dearrow_titles: s.dearrow_titles,
            dearrow_thumbnails: s.dearrow_thumbnails,
            ryd: s.ryd,
            hide_shorts: s.hide_shorts,
            hide_live: s.hide_live,
            hide_upcoming: s.hide_upcoming,
            hide_comments: s.hide_comments,
            hide_related: s.hide_related,
            hide_watched_in_feed: s.hide_watched_in_feed,
            history_enabled: s.history_enabled,
            search_history_enabled: s.search_history_enabled,
            ipv4_only: s.ipv4_only,
            proxy: s.proxy.clone(),
            blocked_keywords: s.blocked_keywords.clone(),
        }
    }

    fn apply_to(&self, s: &mut store::Settings) {
        s.region = self.region.clone();
        s.language = self.language.clone();
        s.default_quality = self.default_quality;
        s.default_speed = self.default_speed;
        s.remember_speed_per_channel = self.remember_speed_per_channel;
        s.autoplay_next = self.autoplay_next;
        s.resume_playback = self.resume_playback;
        s.background_play = self.background_play;
        s.original_audio = self.original_audio;
        s.sponsorblock = self.sponsorblock;
        if !self.sponsorblock_server.trim().is_empty() {
            s.sponsorblock_server = self.sponsorblock_server.trim().to_string();
        }
        let mut set_cat = |cat: &str, skip: bool, default_non_skip: &str| {
            s.sb_actions
                .insert(cat.to_string(), if skip { "skip" } else { default_non_skip }.to_string());
        };
        set_cat("sponsor", self.sb_skip_sponsors, "show");
        set_cat("selfpromo", self.sb_skip_selfpromo, "show");
        set_cat("interaction", self.sb_skip_interaction, "show");
        set_cat("intro", self.sb_skip_intro, "show");
        set_cat("outro", self.sb_skip_outro, "show");
        set_cat("preview", self.sb_skip_preview, "show");
        set_cat("filler", self.sb_skip_filler, "show");
        set_cat("music_offtopic", self.sb_skip_music_offtopic, "show");
        s.sb_notify = self.sb_notify;
        s.dearrow_titles = self.dearrow_titles;
        s.dearrow_thumbnails = self.dearrow_thumbnails;
        s.ryd = self.ryd;
        s.hide_shorts = self.hide_shorts;
        s.hide_live = self.hide_live;
        s.hide_upcoming = self.hide_upcoming;
        s.hide_comments = self.hide_comments;
        s.hide_related = self.hide_related;
        s.hide_watched_in_feed = self.hide_watched_in_feed;
        s.history_enabled = self.history_enabled;
        s.search_history_enabled = self.search_history_enabled;
        s.ipv4_only = self.ipv4_only;
        s.proxy = self.proxy.clone();
        s.blocked_keywords = self.blocked_keywords.clone();
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiAuthStatus {
    pub signed_in: bool,
    pub account_name: Option<String>,
    pub account_handle: Option<String>,
    pub account_avatar: Option<String>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiDeviceCode {
    pub device_code: String,
    pub user_code: String,
    pub verification_url: String,
    pub interval_secs: u64,
    pub expires_in_secs: u64,
}

#[derive(Clone, Debug, uniffi::Enum)]
pub enum FfiPollLoginStatus {
    Pending,
    SlowDown,
    Done { account_name: String, account_handle: Option<String>, account_avatar: Option<String> },
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiImportReport {
    pub subscriptions: u32,
    pub history: u32,
    pub playlists: u32,
    pub playlist_videos: u32,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FfiCodeLabel {
    pub code: String,
    pub name: String,
}

// ───────────────────────── Helpers ─────────────────────────

fn map_items(items: Vec<types::Item>, filter_content: bool) -> Vec<FfiFeedItem> {
    let settings = store::settings_snapshot();
    let progress = store::progress_map();
    items
        .into_iter()
        .filter_map(|item| match item {
            types::Item::Video(v) => {
                if filter_content && store::is_filtered(&v, &settings) {
                    return None;
                }
                if filter_content && settings.hide_watched_in_feed {
                    if let Some((pos, dur)) = progress.get(&v.id) {
                        if *dur > 0.0 && *pos / *dur >= 0.85 {
                            return None;
                        }
                    }
                }
                Some(FfiFeedItem::Video {
                    video: FfiVideoItem::from_core(v, &settings, Some(&progress)),
                })
            }
            types::Item::Channel(c) => Some(FfiFeedItem::Channel { channel: c.into() }),
            types::Item::Playlist(p) => Some(FfiFeedItem::Playlist { playlist: p.into() }),
        })
        .collect()
}

fn ensure_loopback_no_proxy() {
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        // Ensure iOS/macOS URLSession or Rust HTTP never proxies 127.0.0.1 stream URLs
        unsafe {
            std::env::set_var("no_proxy", "127.0.0.1,localhost,::1");
            std::env::set_var("NO_PROXY", "127.0.0.1,localhost,::1");
        }
    });
}

// ───────────────────────── Exported Client Object ─────────────────────────

#[derive(uniffi::Object)]
pub struct StreamTubeClient {}

#[uniffi::export]
impl StreamTubeClient {
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Arc<Self> {
        ensure_loopback_no_proxy();
        if !data_dir.trim().is_empty() {
            store::init_with_dir(PathBuf::from(data_dir));
        } else {
            store::init();
        }
        Arc::new(Self {})
    }

    // ─── Settings & Locales ───

    pub fn get_settings(&self) -> FfiSettings {
        FfiSettings::from_store(&store::settings_snapshot())
    }

    pub fn save_settings(&self, settings: FfiSettings) {
        let prev_region = store::settings_snapshot().region.clone();
        let prev_lang = store::settings_snapshot().language.clone();
        let prev_ipv4 = store::settings_snapshot().ipv4_only;
        let prev_proxy = store::settings_snapshot().proxy.clone();
        store::update_settings(|s| settings.apply_to(s));
        if settings.region != prev_region
            || settings.language != prev_lang
            || settings.ipv4_only != prev_ipv4
            || settings.proxy != prev_proxy
        {
            streams::clear_cache();
        }
    }

    pub fn supported_regions(&self) -> Vec<FfiCodeLabel> {
        crate::locale::REGIONS
            .iter()
            .map(|(code, name)| FfiCodeLabel {
                code: (*code).to_string(),
                name: (*name).to_string(),
            })
            .collect()
    }

    pub fn supported_languages(&self) -> Vec<FfiCodeLabel> {
        crate::locale::LANGUAGES
            .iter()
            .map(|(code, name)| FfiCodeLabel {
                code: (*code).to_string(),
                name: (*name).to_string(),
            })
            .collect()
    }

    // ─── Feeds & Discovery ───

    pub fn home_feed(&self) -> Result<FfiFeedPage, CoreError> {
        if web::connected() {
            if let Ok(page) = web::home() {
                if !page.items.is_empty() {
                    return Ok(FfiFeedPage {
                        items: map_items(page.items, true),
                        continuation: page.continuation,
                        source: "auth_web".into(),
                    });
                }
            }
        }
        if auth::signed_in() {
            if let Ok(page) = auth::home() {
                if !page.items.is_empty() {
                    return Ok(FfiFeedPage {
                        items: map_items(page.items, true),
                        continuation: page.continuation,
                        source: "auth_tv".into(),
                    });
                }
            }
        }
        if recommend::available() {
            let items = recommend::for_you();
            if !items.is_empty() {
                return Ok(FfiFeedPage {
                    items: map_items(items, true),
                    continuation: None,
                    source: "local_recommend".into(),
                });
            }
        }
        // Fallback when signed out with empty watch history: aggregate popular Explore categories
        let lists: Vec<Vec<types::Item>> = std::thread::scope(|s| {
            let mut handles = Vec::new();
            for (_, channel_id) in innertube::EXPLORE.iter().take(4) {
                handles.push(s.spawn(move || innertube::explore(channel_id).map(|p| p.items).unwrap_or_default()));
            }
            handles.into_iter().filter_map(|h| h.join().ok()).collect()
        });
        let mut combined = Vec::new();
        let mut seen = std::collections::HashSet::new();
        let mut iters: Vec<_> = lists.into_iter().map(|l| l.into_iter()).collect();
        loop {
            let mut any = false;
            for it in iters.iter_mut() {
                if let Some(item) = it.next() {
                    any = true;
                    let keep = match &item {
                        types::Item::Video(v) => seen.insert(v.id.clone()),
                        _ => true,
                    };
                    if keep {
                        combined.push(item);
                    }
                }
            }
            if !any {
                break;
            }
        }
        Ok(FfiFeedPage {
            items: map_items(combined, true),
            continuation: None,
            source: "explore".into(),
        })
    }

    pub fn explore_categories(&self) -> Vec<FfiExploreCategory> {
        innertube::EXPLORE
            .iter()
            .map(|(name, id)| FfiExploreCategory {
                name: (*name).to_string(),
                channel_id: (*id).to_string(),
            })
            .collect()
    }

    pub fn explore_feed(&self, channel_id: String) -> Result<FfiFeedPage, CoreError> {
        let page = innertube::explore(&channel_id)?;
        Ok(FfiFeedPage {
            items: map_items(page.items, true),
            continuation: page.continuation,
            source: "explore".into(),
        })
    }

    pub fn continue_feed(&self, continuation: String, source: String) -> Result<FfiFeedPage, CoreError> {
        let page = match source.as_str() {
            "auth_web" => web::browse_continue(&continuation)?,
            "auth_tv" => auth::browse_continue(&continuation)?,
            "search" => innertube::search_continue(&continuation)?,
            "related" => innertube::related_continue(&continuation)?,
            _ => innertube::browse_continue(&continuation)?,
        };
        Ok(FfiFeedPage {
            items: map_items(page.items, source != "search"),
            continuation: page.continuation,
            source,
        })
    }

    pub fn shorts_feed(&self, continuation: Option<String>) -> Result<FfiShortsPage, CoreError> {
        let seed = if continuation.is_none() {
            store::history_list("", 50)
                .into_iter()
                .find(|h| h.video.is_short)
                .map(|h| h.video.id)
        } else {
            None
        };
        let (videos, cont) = innertube::shorts_feed(continuation.as_deref(), seed.as_deref())?;
        let settings = store::settings_snapshot();
        let items = videos
            .into_iter()
            .map(|v| FfiVideoItem::from_core(v, &settings, None))
            .collect();
        Ok(FfiShortsPage {
            videos: items,
            continuation: cont,
        })
    }

    // ─── Search & Deep Links ───

    pub fn search(&self, query: String, filter: FfiSearchFilter) -> Result<FfiFeedPage, CoreError> {
        let trimmed = query.trim();
        if trimmed.is_empty() {
            return Err(CoreError::InvalidInput {
                message: "Search query cannot be empty".into(),
            });
        }
        store::search_history_add(trimmed);
        let core_filter = innertube::SearchFilter {
            sort: filter.sort,
            date: filter.date,
            kind: filter.kind,
            duration: filter.duration,
            hd: filter.hd,
            subtitles: filter.subtitles,
            creative_commons: false,
            live: filter.live,
            four_k: filter.four_k,
            hdr: false,
        };
        let page = innertube::search(trimmed, &core_filter)?;
        Ok(FfiFeedPage {
            items: map_items(page.items, false),
            continuation: page.continuation,
            source: "search".into(),
        })
    }

    pub fn search_suggestions(&self, query: String) -> Vec<String> {
        if query.trim().is_empty() {
            return store::search_history("", 10);
        }
        innertube::suggestions(query.trim()).unwrap_or_default()
    }

    pub fn search_history(&self, prefix: String, limit: u32) -> Vec<String> {
        store::search_history(&prefix, limit as usize)
    }

    pub fn remove_search_history(&self, query: String) {
        store::search_history_remove(&query);
    }

    pub fn clear_search_history(&self) {
        store::search_history_clear();
    }

    pub fn resolve_youtube_url(&self, url: String) -> Result<FfiResolvedTarget, CoreError> {
        let normalized = url_util::normalize(&url);
        let resolved = match innertube::parse_youtube_url(&normalized) {
            Some(r) => r,
            None => innertube::resolve_url(&normalized)?,
        };
        Ok(match resolved {
            innertube::ResolvedUrl::Video(video_id) => FfiResolvedTarget::Video { video_id },
            innertube::ResolvedUrl::Channel(channel_id) => FfiResolvedTarget::Channel { channel_id },
            innertube::ResolvedUrl::Playlist(playlist_id) => FfiResolvedTarget::Playlist { playlist_id },
        })
    }

    // ─── Playback, Streams (AVPlayer HLS) & SponsorBlock ───

    pub fn prefetch_stream(&self, video_id: String) {
        std::thread::spawn(move || {
            let _ = streams::get_ios_streams(&video_id);
        });
    }

    pub fn invalidate_stream(&self, video_id: String) {
        streams::invalidate(&video_id);
    }

    pub fn resolve_playback(
        &self,
        video_id: String,
        max_height: u32,
        preferred_audio: Option<String>,
    ) -> Result<FfiPlaybackBundle, CoreError> {
        let info = streams::get_ios_streams(&video_id)?;
        let settings = store::settings_snapshot();
        let target_height = if max_height > 0 {
            max_height
        } else {
            settings.default_quality
        };
        let audio_choice = streams::hls_audio_choice(&info, preferred_audio.as_deref());

        let stream_url = if let Some(ref hls) = info.hls_url {
            proxy::ios_hls(hls, target_height, audio_choice.as_deref())
        } else if let Some(muxed) = info
            .muxed
            .iter()
            .filter(|f| target_height == 0 || streams::fmt_class(f) <= target_height)
            .max_by_key(|f| (streams::is_avc(&f.codecs), streams::fmt_class(f), f.bitrate))
            .or_else(|| info.muxed.first())
        {
            proxy::local_url(&muxed.url, muxed.content_length, &muxed.mime)
        } else if let Some(vid) = info
            .video
            .iter()
            .filter(|f| streams::is_avc(&f.codecs))
            .max_by_key(|f| streams::fmt_class(f))
        {
            proxy::local_url(&vid.url, vid.content_length, &vid.mime)
        } else {
            return Err(CoreError::Api {
                message: "No AVPlayer-compatible stream found for this video".into(),
            });
        };

        let mut qualities: Vec<FfiQualityOption> = info
            .video
            .iter()
            .map(|f| {
                let h = streams::fmt_class(f);
                let label = if !f.quality_label.is_empty() {
                    f.quality_label.clone()
                } else if f.fps > 30 {
                    format!("{h}p{}", f.fps)
                } else {
                    format!("{h}p")
                };
                FfiQualityOption {
                    height: h,
                    fps: f.fps,
                    label,
                    codecs: f.codecs.clone(),
                    bitrate: f.bitrate,
                }
            })
            .collect();
        qualities.sort_by(|a, b| (b.height, b.fps, b.bitrate).cmp(&(a.height, a.fps, a.bitrate)));
        qualities.dedup_by(|a, b| a.height == b.height && a.fps == b.fps);

        let audio_tracks: Vec<FfiAudioTrack> = info
            .audio
            .iter()
            .filter_map(|a| {
                let name = a.audio_language.clone()?;
                Some(FfiAudioTrack {
                    language_code: a.quality_label.clone(),
                    display_name: name,
                    is_original: a.audio_default,
                })
            })
            .collect();

        let captions: Vec<FfiCaptionTrack> = info
            .captions
            .iter()
            .map(|c| FfiCaptionTrack {
                lang: c.lang.clone(),
                name: c.name.clone(),
                vtt_url: proxy::local_pass(&c.url),
                auto_generated: c.auto,
            })
            .collect();

        let resume_position_secs = if settings.resume_playback && !info.is_live {
            store::progress_map()
                .get(&video_id)
                .and_then(|(pos, dur)| {
                    let total = if *dur > 0.0 { *dur } else { info.length_secs as f64 };
                    if *pos > 5.0 && (total <= 0.0 || *pos < total - 10.0) {
                        Some(*pos)
                    } else {
                        None
                    }
                })
                .unwrap_or(0.0)
        } else {
            0.0
        };

        let playback_speed = if settings.remember_speed_per_channel && !info.channel_id.is_empty() {
            store::channel_speed(&info.channel_id).unwrap_or(settings.default_speed)
        } else {
            settings.default_speed
        };

        Ok(FfiPlaybackBundle {
            video_id,
            title: info.title,
            author: info.author,
            channel_id: info.channel_id,
            duration_secs: info.length_secs,
            is_live: info.is_live,
            stream_url,
            direct_hls_url: info.hls_url,
            source_client: info.source.to_string(),
            qualities,
            selected_max_height: target_height,
            audio_tracks,
            selected_audio: audio_choice,
            captions,
            resume_position_secs,
            playback_speed,
        })
    }

    pub fn switch_playback_stream(
        &self,
        video_id: String,
        max_height: u32,
        preferred_audio: Option<String>,
    ) -> Result<String, CoreError> {
        let bundle = self.resolve_playback(video_id, max_height, preferred_audio)?;
        Ok(bundle.stream_url)
    }

    pub fn watch_details(
        &self,
        video_id: String,
        playlist_id: Option<String>,
    ) -> Result<FfiWatchDetails, CoreError> {
        let settings = store::settings_snapshot();
        let sb_enabled = settings.sponsorblock;
        let sb_server = settings.sponsorblock_server.clone();
        let sb_min = settings.sb_min_duration;
        let sb_actions = settings.sb_actions.clone();
        let sb_cats: Vec<String> = sb_actions
            .iter()
            .filter(|(_, act)| *act != "off")
            .map(|(cat, _)| cat.clone())
            .collect();
        let ryd_enabled = settings.ryd;
        let dearrow_titles = settings.dearrow_titles;

        let vid_ref = &video_id;
        let pl_ref = playlist_id.as_deref();
        let sb_srv_ref = &sb_server;
        let sb_cats_ref = &sb_cats;

        let (watch_res, sb_res, ryd_res, branding_opt) = std::thread::scope(|s| {
            let w_handle = s.spawn(move || innertube::watch_next(vid_ref, pl_ref));
            let sb_handle = s.spawn(move || {
                if sb_enabled && !sb_cats_ref.is_empty() {
                    services::sponsor_segments(vid_ref, sb_srv_ref, sb_cats_ref).unwrap_or_default()
                } else {
                    Vec::new()
                }
            });
            let ryd_handle = s.spawn(move || {
                if ryd_enabled {
                    services::ryd_votes(vid_ref).ok()
                } else {
                    None
                }
            });
            let da_handle = s.spawn(move || {
                if dearrow_titles {
                    services::dearrow_branding(vid_ref)
                } else {
                    None
                }
            });
            (
                w_handle.join().unwrap_or_else(|_| Err(anyhow::anyhow!("watch_next thread panicked"))),
                sb_handle.join().unwrap_or_default(),
                ryd_handle.join().unwrap_or_default(),
                da_handle.join().unwrap_or_default(),
            )
        });

        let mut w = watch_res?;
        if let Some(b) = branding_opt {
            if let Some(clean_title) = b.title {
                w.title = clean_title;
            }
        }

        let sponsor_segments: Vec<FfiSponsorSegment> = sb_res
            .into_iter()
            .filter(|seg| (seg.end - seg.start) >= sb_min)
            .filter_map(|seg| {
                let user_action = sb_actions.get(&seg.category).map(String::as_str).unwrap_or("off");
                if user_action == "off" {
                    return None;
                }
                let effective_action = if seg.action == "poi" {
                    "poi".to_string()
                } else {
                    user_action.to_string()
                };
                Some(FfiSponsorSegment {
                    uuid: seg.uuid,
                    category_title: services::sponsor_category_name(&seg.category).to_string(),
                    color_rgb: services::sponsor_category_color(&seg.category),
                    category: seg.category,
                    action: effective_action,
                    start_secs: seg.start,
                    end_secs: seg.end,
                })
            })
            .collect();

        let votes = ryd_res.map(|v| FfiVotes {
            likes_compact: services::compact_count(v.likes),
            dislikes_compact: services::compact_count(v.dislikes),
            likes: v.likes,
            dislikes: v.dislikes,
            views: v.views,
            rating: v.rating,
        });

        let is_sub = !w.channel.id.is_empty() && store::is_subscribed(&w.channel.id);
        let user_rating = store::rating(&video_id);
        let (comments_top_token, comments_newest_token) = w.comments_sort;
        let (live_chat_top_token, live_chat_all_token) = match w.live_chat {
            Some((t, a)) => (Some(t), Some(a)),
            None => (None, None),
        };

        Ok(FfiWatchDetails {
            id: w.id,
            title: w.title,
            views_text: w.views_text,
            date_text: w.date_text,
            likes_text: w.likes_text,
            description: w.description,
            channel: w.channel.into(),
            is_subscribed: is_sub,
            user_rating,
            is_live: w.is_live,
            chapters: w
                .chapters
                .into_iter()
                .map(|c| FfiChapter {
                    title: c.title,
                    start_secs: c.start,
                    thumbnail: c.thumbnail,
                })
                .collect(),
            heatmap: w
                .heatmap
                .into_iter()
                .map(|(start_secs, duration_secs, intensity)| FfiHeatmapPoint {
                    start_secs,
                    duration_secs,
                    intensity,
                })
                .collect(),
            sponsor_segments,
            votes,
            related: map_items(w.related, true),
            related_continuation: w.related_continuation,
            comments_token: w.comments_token,
            comments_top_token,
            comments_newest_token,
            comment_count_text: w.comment_count_text,
            live_chat_top_token,
            live_chat_all_token,
        })
    }

    pub fn mark_sponsor_viewed(&self, uuid: String) {
        let server = store::settings_snapshot().sponsorblock_server.clone();
        std::thread::spawn(move || {
            services::sponsor_viewed(&server, &uuid);
        });
    }

    pub fn comments(&self, token: String) -> Result<FfiCommentPage, CoreError> {
        let p = innertube::comments(&token)?;
        Ok(FfiCommentPage {
            comments: p
                .comments
                .into_iter()
                .map(|c| FfiComment {
                    id: c.id,
                    author: c.author,
                    author_id: c.author_id,
                    author_avatar: c.author_avatar,
                    text: c.text,
                    published: c.published,
                    likes: c.likes,
                    reply_count: c.reply_count,
                    replies_token: c.replies_token,
                    is_creator: c.is_creator,
                    is_verified: c.is_verified,
                    is_pinned: c.is_pinned,
                    hearted: c.hearted,
                })
                .collect(),
            continuation: p.continuation,
            count_text: p.count_text,
            sort_top_token: p.sort_top_token,
            sort_new_token: p.sort_new_token,
        })
    }

    pub fn live_chat(&self, token: String) -> Result<FfiChatBatch, CoreError> {
        let batch = innertube::live_chat(&token)?;
        Ok(FfiChatBatch {
            messages: batch
                .messages
                .into_iter()
                .map(|m| FfiChatMessage {
                    id: m.id,
                    author: m.author,
                    author_photo: m.author_photo,
                    text: m.text,
                    role: match m.role {
                        types::ChatRole::Owner => "owner".into(),
                        types::ChatRole::Moderator => "moderator".into(),
                        types::ChatRole::Member => "member".into(),
                        types::ChatRole::Viewer => "viewer".into(),
                    },
                    verified: m.verified,
                    paid: m.paid,
                })
                .collect(),
            next_token: batch.next,
            timeout_ms: batch.timeout_ms,
        })
    }

    // ─── Channels & Playlists ───

    pub fn channel_page(&self, channel_id: String, tab_params: Option<String>) -> Result<FfiChannelPage, CoreError> {
        let p = innertube::channel(&channel_id, tab_params.as_deref())?;
        let is_subscribed = store::is_subscribed(&p.info.id);
        Ok(FfiChannelPage {
            info: p.info.into(),
            banner: p.banner,
            is_subscribed,
            tabs: p
                .tabs
                .into_iter()
                .map(|t| FfiChannelTab {
                    title: t.title,
                    kind: t.kind,
                    params: t.params,
                    selected: t.selected,
                })
                .collect(),
            items: map_items(p.page.items, false),
            continuation: p.page.continuation,
        })
    }

    pub fn remote_playlist(&self, playlist_id: String) -> Result<FfiPlaylistPage, CoreError> {
        let p = if auth::signed_in() {
            auth::playlist(&playlist_id).or_else(|_| innertube::playlist(&playlist_id))?
        } else {
            innertube::playlist(&playlist_id)?
        };
        let settings = store::settings_snapshot();
        let progress = store::progress_map();
        let is_saved = store::is_playlist_saved(&playlist_id);
        Ok(FfiPlaylistPage {
            info: p.info.into(),
            description: p.description,
            videos: p
                .videos
                .into_iter()
                .map(|v| FfiVideoItem::from_core(v, &settings, Some(&progress)))
                .collect(),
            continuation: p.continuation,
            is_saved,
        })
    }

    pub fn subscriptions(&self) -> Vec<FfiSubscription> {
        store::subscriptions()
            .into_iter()
            .map(|s| FfiSubscription {
                channel_id: s.channel_id,
                name: s.name,
                avatar: s.avatar,
            })
            .collect()
    }

    pub fn is_subscribed(&self, channel_id: String) -> bool {
        store::is_subscribed(&channel_id)
    }

    pub fn subscribe(&self, channel_id: String, name: String, avatar: Option<String>) {
        store::subscribe(&channel_id, &name, avatar.as_deref());
        if auth::signed_in() {
            std::thread::spawn(move || {
                let _ = auth::subscribe(&channel_id, true);
            });
        }
    }

    pub fn unsubscribe(&self, channel_id: String) {
        store::unsubscribe(&channel_id);
        if auth::signed_in() {
            std::thread::spawn(move || {
                let _ = auth::subscribe(&channel_id, false);
            });
        }
    }

    pub fn subscriptions_cached(&self, channel_filter: Option<Vec<String>>) -> Vec<FfiVideoItem> {
        let (videos, _) = feed::cached_feed(channel_filter.as_deref());
        let settings = store::settings_snapshot();
        let progress = store::progress_map();
        videos
            .into_iter()
            .filter(|v| !store::is_filtered(v, &settings))
            .map(|v| FfiVideoItem::from_core(v, &settings, Some(&progress)))
            .collect()
    }

    pub fn refresh_subscriptions(&self, channel_filter: Option<Vec<String>>) -> Result<FfiRefreshResult, CoreError> {
        if channel_filter.is_none() && auth::signed_in() && store::subscriptions().is_empty() {
            let _ = auth::sync_subscriptions();
        }
        let (videos, failed) = feed::refresh(channel_filter, |_, _| {});
        let settings = store::settings_snapshot();
        let progress = store::progress_map();
        Ok(FfiRefreshResult {
            videos: videos
                .into_iter()
                .filter(|v| !store::is_filtered(v, &settings))
                .map(|v| FfiVideoItem::from_core(v, &settings, Some(&progress)))
                .collect(),
            failed_channels: failed as u32,
        })
    }

    // ─── Local Playlists ───

    pub fn local_playlists(&self) -> Vec<FfiLocalPlaylist> {
        store::playlists()
            .into_iter()
            .map(|p| FfiLocalPlaylist {
                id: p.id,
                name: p.name,
                is_protected: p.protected,
                count: p.count as u32,
                thumbnail: p.thumbnail,
            })
            .collect()
    }

    pub fn create_local_playlist(&self, name: String) -> i64 {
        store::playlist_create(name.trim())
    }

    pub fn rename_local_playlist(&self, playlist_id: i64, name: String) {
        store::playlist_rename(playlist_id, name.trim());
    }

    pub fn delete_local_playlist(&self, playlist_id: i64) {
        store::playlist_delete(playlist_id);
    }

    pub fn local_playlist_videos(&self, playlist_id: i64) -> Vec<FfiVideoItem> {
        let settings = store::settings_snapshot();
        let progress = store::progress_map();
        store::playlist_items(playlist_id)
            .into_iter()
            .map(|v| FfiVideoItem::from_core(v, &settings, Some(&progress)))
            .collect()
    }

    pub fn add_to_local_playlist(&self, playlist_id: i64, video: FfiVideoItem) {
        store::playlist_add(playlist_id, &video.into_core());
    }

    pub fn remove_from_local_playlist(&self, playlist_id: i64, video_id: String) {
        store::playlist_remove(playlist_id, &video_id);
    }

    pub fn local_playlist_contains(&self, playlist_id: i64, video_id: String) -> bool {
        store::playlist_contains(playlist_id, &video_id)
    }

    // ─── Watch History, Progress & Ratings ───

    pub fn record_watch_start(&self, video: FfiVideoItem) {
        let core_vid = video.into_core();
        let dur = core_vid.duration_secs.unwrap_or(0) as f64;
        let id = core_vid.id.clone();
        store::history_add(&core_vid);
        web::report_start(&id, dur);
    }

    pub fn record_watch_progress(&self, video_id: String, progress_secs: f64, duration_secs: f64, playing: bool) {
        store::history_progress_queued(&video_id, progress_secs, duration_secs, false);
        web::report_progress(&video_id, progress_secs, playing);
    }

    pub fn record_watch_stop(&self, video_id: String, progress_secs: f64) {
        web::report_stop(&video_id, progress_secs);
    }

    pub fn watch_history(&self, query: String, limit: u32) -> Vec<FfiHistoryEntry> {
        let settings = store::settings_snapshot();
        store::history_list(&query, limit as usize)
            .into_iter()
            .map(|h| FfiHistoryEntry {
                video: FfiVideoItem::from_core(h.video, &settings, None),
                watched_at: h.watched_at,
                progress_secs: h.progress,
                duration_secs: h.duration,
            })
            .collect()
    }

    pub fn remove_from_history(&self, video_id: String) {
        store::history_remove(&video_id);
    }

    pub fn clear_history(&self) {
        store::history_clear();
    }

    pub fn get_rating(&self, video_id: String) -> i8 {
        store::rating(&video_id)
    }

    pub fn set_rating(&self, video_id: String, rating: i8) {
        let clamped = rating.clamp(-1, 1);
        store::set_rating(&video_id, clamped);
        if auth::signed_in() {
            let kind = match clamped {
                1 => "like",
                -1 => "dislike",
                _ => "removelike",
            };
            std::thread::spawn(move || {
                let _ = auth::like(&video_id, kind);
            });
        }
    }

    pub fn channel_speed(&self, channel_id: String) -> Option<f64> {
        store::channel_speed(&channel_id)
    }

    pub fn set_channel_speed(&self, channel_id: String, speed: f64) {
        store::set_channel_speed(&channel_id, speed);
    }

    // ─── Google / YouTube TV Device OAuth & Import/Export ───

    pub fn auth_status(&self) -> FfiAuthStatus {
        if let Some(acc) = auth::account() {
            return FfiAuthStatus {
                signed_in: auth::signed_in(),
                account_name: Some(acc.name),
                account_handle: acc.handle,
                account_avatar: acc.avatar,
            };
        }
        if web::connected() {
            return FfiAuthStatus {
                signed_in: true,
                account_name: web::account_name(),
                account_handle: None,
                account_avatar: None,
            };
        }
        FfiAuthStatus {
            signed_in: auth::signed_in(),
            account_name: None,
            account_handle: None,
            account_avatar: None,
        }
    }

    pub fn start_device_login(&self) -> Result<FfiDeviceCode, CoreError> {
        let dc = auth::start_login()?;
        Ok(FfiDeviceCode {
            device_code: dc.device_code,
            user_code: dc.user_code,
            verification_url: dc.verification_url,
            interval_secs: dc.interval,
            expires_in_secs: dc.expires_in,
        })
    }

    pub fn poll_device_login(&self, dc: FfiDeviceCode) -> Result<FfiPollLoginStatus, CoreError> {
        let core_dc = auth::DeviceCode {
            device_code: dc.device_code,
            user_code: dc.user_code,
            verification_url: dc.verification_url,
            interval: dc.interval_secs,
            expires_in: dc.expires_in_secs,
        };
        Ok(match auth::poll_login(&core_dc)? {
            auth::PollResult::Pending => FfiPollLoginStatus::Pending,
            auth::PollResult::SlowDown => FfiPollLoginStatus::SlowDown,
            auth::PollResult::Done(acc) => FfiPollLoginStatus::Done {
                account_name: acc.name,
                account_handle: acc.handle,
                account_avatar: acc.avatar,
            },
        })
    }

    pub fn sign_out(&self) {
        auth::sign_out();
        web::disconnect();
    }

    pub fn sync_account_subscriptions(&self) -> Result<u32, CoreError> {
        Ok(auth::sync_subscriptions()? as u32)
    }

    pub fn sync_account_history(&self) -> Result<u32, CoreError> {
        Ok(auth::sync_history(3)? as u32)
    }

    pub fn import_data_file(&self, path: String) -> Result<FfiImportReport, CoreError> {
        let rep = import::import_file(std::path::Path::new(&path))?;
        Ok(FfiImportReport {
            subscriptions: rep.subscriptions as u32,
            history: rep.history as u32,
            playlists: rep.playlists as u32,
            playlist_videos: rep.playlist_videos as u32,
        })
    }

    pub fn export_backup_file(&self, path: String) -> Result<(), CoreError> {
        import::export_backup(std::path::Path::new(&path)).map_err(|e| CoreError::Storage {
            message: format!("{e:#}"),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_roundtrips_settings_and_playlists() {
        let tmp = std::env::temp_dir().join(format!("st-ffi-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        let client = StreamTubeClient::new(tmp.to_string_lossy().into_owned());

        let mut settings = client.get_settings();
        assert!(settings.sponsorblock);
        settings.default_quality = 720;
        settings.dearrow_titles = true;
        client.save_settings(settings);
        assert_eq!(client.get_settings().default_quality, 720);
        assert!(client.get_settings().dearrow_titles);

        let pid = client.create_local_playlist("iPhone Offline".into());
        assert!(pid > 0);
        assert!(client.local_playlists().iter().any(|p| p.name == "iPhone Offline"));
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn ios_master_filter_drops_vp9_and_keeps_h264_hevc() {
        let sample = "#EXTM3U\n\
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a1\",LANGUAGE=\"es\",NAME=\"Spanish\",DEFAULT=YES,AUTOSELECT=YES,URI=\"https://example.com/a_es.m3u8\"\n\
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a1\",LANGUAGE=\"en\",NAME=\"English (original)\",DEFAULT=NO,AUTOSELECT=YES,URI=\"https://example.com/a_en.m3u8?acont=original\"\n\
#EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,CODECS=\"vp09.00.40.08,mp4a.40.2\",AUDIO=\"a1\"\n\
https://example.com/v_1080_vp9.m3u8\n\
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,CODECS=\"avc1.640028,mp4a.40.2\",AUDIO=\"a1\"\n\
https://example.com/v_1080_h264.m3u8\n\
#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720,CODECS=\"hvc1.1.6.L93.B0,mp4a.40.2\",AUDIO=\"a1\"\n\
https://example.com/v_720_hevc.m3u8\n";

        let filtered = crate::proxy::filter_ios_master(sample, 1080, None).expect("filtered");
        assert!(!filtered.contains("v_1080_vp9.m3u8"), "VP9 removed for AVPlayer");
        assert!(filtered.contains("v_1080_h264.m3u8"), "H.264 1080p kept");
        assert!(filtered.contains("v_720_hevc.m3u8"), "HEVC 720p kept");
        assert!(
            filtered.contains("NAME=\"English (original)\",URI=\"https://example.com/a_en.m3u8?acont=original\",DEFAULT=YES"),
            "Original audio promoted to DEFAULT=YES: {filtered}"
        );
    }
}
