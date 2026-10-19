const origin = location.origin;
const checkedURL = (value, base = location.href) => {
    const url = new URL(value, base);
    if (url.origin !== origin || url.protocol !== 'https:' || url.username || url.password) throw new Error('unsupported');
    return url;
};
const itemID = (anchor, base) => {
    try {
        const path = checkedURL(anchor.getAttribute('href'), base).pathname;
        const match = path.match(/^\/item\/view\/(\d+)(?:\/|$)/);
        return match && Number.isSafeInteger(Number(match[1])) ? Number(match[1]) : null;
    } catch { return null; }
};
const assertPage = doc => {
    if (doc.querySelector('input[type="password"]')) throw new Error('signInRequired');
};
const read = async (url) => {
    const abort = new AbortController();
    window.__bakaCatalogAbort = abort;
    const timer = setTimeout(() => abort.abort(), 15000);
    try {
        const response = await fetch(checkedURL(url), {credentials: 'same-origin', signal: abort.signal});
        checkedURL(response.url);
        if (!response.ok) throw new Error('unavailable');
        const html = await response.text();
        if (html.length > 4_000_000) throw new Error('unsupported');
        const doc = new DOMParser().parseFromString(html, 'text/html');
        assertPage(doc);
        return {doc, url: response.url};
    } finally { clearTimeout(timer); window.__bakaCatalogAbort = null; }
};
const extract = (doc, base) => {
    const groups = new Map();
    const links = [...doc.querySelectorAll('a[href]')];
    for (const anchor of links) {
        const id = itemID(anchor, base);
        if (!id) continue;
        let item = groups.get(id);
        if (!item) { item = {id, titles: [], year: null, seasons: []}; groups.set(id, item); }
        const title = (anchor.textContent || '').replace(/\s+/g, ' ').trim();
        if (title && title.length <= 300 && !/^\d+$/.test(title) && !item.titles.includes(title)) item.titles.push(title);
        let card = anchor;
        while (card.parentElement && !['BODY', 'HTML'].includes(card.parentElement.tagName)) {
            const ids = new Set([...card.parentElement.querySelectorAll('a[href]')].map(a => itemID(a, base)).filter(Boolean));
            if (ids.size !== 1 || !ids.has(id)) break;
            card = card.parentElement;
        }
        const walker = doc.createTreeWalker(card, NodeFilter.SHOW_TEXT);
        const fragments = [];
        while (walker.nextNode()) fragments.push(walker.currentNode.textContent);
        const year = fragments.join(' ').match(/\b(?:19|20)\d{2}\b/);
        if (year && !item.year) item.year = Number(year[0]);
    }
    return [...groups.values()].filter(item => item.titles.length);
};
try {
    assertPage(document);
    if (mode === 'details') {
        const {doc, url} = await read('/item/view/' + item.id);
        if (!new URL(url).pathname.match(new RegExp('^/item/view/' + item.id + '(?:/|$)'))) throw new Error('unsupported');
        const heading = (doc.querySelector('h1')?.textContent || '').replace(/\s+/g, ' ').trim();
        if (!heading) throw new Error('unsupported');
        const titles = [...new Set([heading, ...item.titles])];
        const seasons = new Set();
        for (const node of doc.querySelectorAll('a[href], option[value]')) {
            const value = node.getAttribute('href') || node.getAttribute('value');
            try {
                const path = checkedURL(value, url).pathname;
                const match = path.match(new RegExp('^/item/view/' + item.id + '/s(\\d+)(?:e\\d+)?(?:/|$)'));
                if (match && Number(match[1]) > 0 && Number(match[1]) <= 999) seasons.add(Number(match[1]));
            } catch { }
        }
        const formats = new Set();
        for (const node of [...doc.querySelectorAll('script[type="application/ld+json"]')].slice(0, 20)) {
            try {
                const data = JSON.parse(node.textContent);
                for (const entry of (Array.isArray(data) ? data : [data])) {
                    if (!entry || typeof entry !== 'object') continue;
                    const address = entry.url || entry['@id'];
                    if (address && checkedURL(address, url).pathname !== new URL(url).pathname) continue;
                    const types = Array.isArray(entry['@type']) ? entry['@type'] : [entry['@type']];
                    if (types.includes('Movie')) formats.add('movie');
                    if (types.includes('TVSeries')) formats.add('series');
                }
            } catch { }
        }
        const format = formats.size === 1 ? [...formats][0] : (formats.size === 0 && seasons.size ? 'series' : null);
        return JSON.stringify({item: {...item, titles, format, seasons: [...seasons].sort((a,b) => a-b)}});
    }
    const form = [...document.forms].find(form => {
        try { return checkedURL(form.action).pathname === '/item/search'; } catch { return false; }
    });
    if (!form || form.method.toLowerCase() !== 'get') throw new Error('unsupported');
    const field = form.querySelector('select[name], input[name]:not([type="hidden"]):not([type="password"]):not([type="submit"]):not([type="checkbox"])');
    if (!field) throw new Error('unsupported');
    let url = checkedURL(form.action);
    url.searchParams.set(field.name, query);
    const items = new Map();
    let complete = false;
    const visited = new Set();
    for (let page = 0; page < 5; page++) {
        if (visited.has(url.href)) break;
        visited.add(url.href);
        const result = await read(url);
        if (checkedURL(result.url).pathname !== '/item/search') throw new Error('unsupported');
        for (const item of extract(result.doc, result.url)) items.set(item.id, item);
        const next = result.doc.querySelector('a[rel="next"], .pagination li.next:not(.disabled) a');
        if (!next) { complete = true; break; }
        url = checkedURL(next.getAttribute('href'), result.url);
        if (url.pathname !== '/item/search') throw new Error('unsupported');
    }
    return JSON.stringify({items: [...items.values()], isComplete: complete});
} catch (error) {
    const code = ['signInRequired', 'unsupported'].includes(error.message) ? error.message : 'unavailable';
    return JSON.stringify({error: code});
}
