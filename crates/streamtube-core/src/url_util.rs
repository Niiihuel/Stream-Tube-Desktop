//! URL normalization helpers shared between desktop and iOS deep links.

/// Turns a `streamtube:` or `youtube:` link back into the YouTube URL it wraps.
/// Accepts `streamtube://open?url=<encoded>`, `streamtube:https://…`,
/// `youtube://watch?v=…`, and `streamtube://www.youtube.com/watch?v=…`;
/// anything else is returned unchanged.
pub fn normalize(arg: &str) -> String {
    let a = arg.trim().trim_matches('"');
    if let Some(rest) = a
        .strip_prefix("youtube://")
        .or_else(|| a.strip_prefix("YOUTUBE://"))
        .or_else(|| a.strip_prefix("vnd.youtube://"))
    {
        let rest = rest.trim_start_matches('/');
        if rest.starts_with("watch") || rest.starts_with("shorts/") || rest.starts_with("playlist") || rest.starts_with("channel/") || rest.starts_with('@') {
            return format!("https://www.youtube.com/{rest}");
        }
        if rest.len() == 11 {
            return format!("https://www.youtube.com/watch?v={rest}");
        }
        return format!("https://www.youtube.com/{rest}");
    }
    let Some(rest) = a.strip_prefix("streamtube:").or_else(|| a.strip_prefix("STREAMTUBE:")) else {
        return a.to_string();
    };
    let rest = rest.trim_start_matches('/');
    if let Some(q) = rest.strip_prefix("open?").or_else(|| rest.strip_prefix("open/?")) {
        if let Some(u) = q.split('&').find_map(|kv| kv.strip_prefix("url=")) {
            return crate::api::http::urldecode(u);
        }
        if let Some(v) = q.split('&').find_map(|kv| kv.strip_prefix("v=")) {
            return format!("https://www.youtube.com/watch?v={v}");
        }
    }
    if rest.starts_with("http:") || rest.starts_with("https:") {
        let (scheme, tail) = rest.split_once(':').unwrap_or(("https", ""));
        return format!("{scheme}://{}", tail.trim_start_matches('/'));
    }
    format!("https://{rest}")
}

#[cfg(test)]
mod tests {
    use super::normalize;

    #[test]
    fn scheme_links() {
        assert_eq!(
            normalize("streamtube://open?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc"),
            "https://www.youtube.com/watch?v=abc"
        );
        assert_eq!(normalize("streamtube:https://youtu.be/abc"), "https://youtu.be/abc");
        assert_eq!(normalize("streamtube://https:/youtu.be/abc"), "https://youtu.be/abc");
        assert_eq!(
            normalize("streamtube://www.youtube.com/watch?v=abc"),
            "https://www.youtube.com/watch?v=abc"
        );
        assert_eq!(
            normalize("youtube://watch?v=dQw4w9WgXcQ"),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        );
        assert_eq!(normalize("https://youtu.be/abc"), "https://youtu.be/abc");
    }
}
