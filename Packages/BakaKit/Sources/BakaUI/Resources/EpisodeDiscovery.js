(() => {
    if (window.__bakaEpisodeDiscovery) return;
    window.__bakaEpisodeDiscovery = true;
    let previous = '';
    const scan = () => {
        const episodes = new Map();
        for (const node of document.querySelectorAll('a[href], option[value]')) {
            try {
                const url = new URL(node.getAttribute('href') || node.getAttribute('value'), document.baseURI);
                if (url.origin !== location.origin || url.username || url.password) continue;
                if (!/^\/item\/view\/\d+\/s\d+e\d+\/?$/.test(url.pathname)) continue;
                const address = url.origin + url.pathname;
                const title = (node.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 200);
                const existing = episodes.get(address);
                if (!existing || (!existing.title && title) || (/^\d+$/.test(existing.title) && title && !/^\d+$/.test(title))) {
                    episodes.set(address, {address, title});
                }
                if (episodes.size >= 2000) break;
            } catch { }
        }
        const payload = {pageAddress: location.href, episodes: [...episodes.values()]};
        const fingerprint = JSON.stringify(payload);
        if (fingerprint === previous) return;
        previous = fingerprint;
        window.webkit.messageHandlers.bakaEpisodes.postMessage(payload);
    };
    window.__bakaScanEpisodes = () => { previous = ''; scan(); };
    let pending = false;
    new MutationObserver(() => {
        if (pending) return;
        pending = true;
        setTimeout(() => { pending = false; scan(); }, 250);
    }).observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['href', 'value']});
    window.addEventListener('popstate', scan);
    scan();
})();
