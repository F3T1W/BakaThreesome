(() => {
    if (window.__bakaMediaDiscovery) return;
    window.__bakaMediaDiscovery = true;
    const seen = new Map();
    const mediaPath = /\.(m3u8|mpd|mp4|m4v|webm|mkv|mov)$/i;
    function report(value, source, requireExtension) {
        try {
            const url = new URL(value, document.baseURI);
            if (url.protocol !== 'https:' || url.username || url.password) return;
            if (requireExtension && !mediaPath.test(url.pathname)) return;
            if ((seen.has(url.href) && !(seen.get(url.href) === 'Resource' && source === 'Video')) || seen.size >= 100) return;
            seen.set(url.href, source);
            window.webkit.messageHandlers.bakaMedia.postMessage({
                address: url.href, pageAddress: location.href, source
            });
        } catch (_) {}
    }
    function scan() {
        document.querySelectorAll('video,audio').forEach(video => {
            if (video.currentSrc) report(video.currentSrc, 'Video', false);
            if (video.src) report(video.src, 'Video', false);
        });
        document.querySelectorAll('video source,audio source').forEach(source => {
            const address = source.getAttribute('src');
            if (address) report(address, 'Video', false);
        });
        document.querySelectorAll('a[href]').forEach(link => report(link.href, 'Link', true));
        performance.getEntriesByType('resource').forEach(entry => report(entry.name, 'Resource', true));
    }
    window.__bakaScanMedia = () => { seen.clear(); scan(); };
    let pending = false;
    new MutationObserver(() => {
        if (pending) return;
        pending = true;
        setTimeout(() => { pending = false; scan(); }, 250);
    }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['src'] });
    document.addEventListener('loadedmetadata', scan, true);
    try {
        new PerformanceObserver(list => list.getEntries().forEach(entry => report(entry.name, 'Resource', true)))
            .observe({ entryTypes: ['resource'] });
    } catch (_) {}
    scan();
})();
