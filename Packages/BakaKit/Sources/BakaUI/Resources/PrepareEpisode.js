// A native Continue action requests a fresh manifest; no signed URL is persisted or guessed.
const player = document.querySelector('media-player');
const ready = [...document.querySelectorAll('video source')].some(source => {
    try {
        const url = new URL(source.getAttribute('src'), document.baseURI);
        return url.origin === location.origin && url.pathname.startsWith('/manifest/') && url.pathname.endsWith('.m3u8');
    } catch { return false; }
});
if (ready) {
    window.__bakaScanMedia?.();
    return 'ready';
}
if (!requested && player) {
    const button = player.querySelector('#centerPlayBtn, .centerPlayButton, button[aria-label="Play/Pause"], .vds-play-button');
    if (button) { button.click(); return 'requested'; }
}
window.__bakaScanMedia?.();
return 'waiting';
