import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync(new URL('../Packages/BakaKit/Sources/BakaUI/Resources/MediaDiscovery.js', import.meta.url), 'utf8');
const messages = [];
let resourceObserver;
const videoURL = 'https://cdn.example/video/master.m3u8?token=synthetic-token';
const document = {
    baseURI: 'https://mirror.example/watch/1', documentElement: {},
    querySelectorAll(selector) {
        if (selector === 'video,audio') return [{ currentSrc: 'blob:https://mirror.example/id', src: videoURL }];
        if (selector === 'video source,audio source') return [{ getAttribute: () => videoURL }];
        if (selector === 'a[href]') return [
            { href: '/episode.mp4?download=1' }, { href: '/login?next=.mp4' },
            { href: 'javascript:alert(1)' }, { href: 'https://user:secret@cdn.example/hidden.mp4' }
        ];
        return [];
    },
    addEventListener() {}
};
const context = vm.createContext({
    URL, Set, document, location: { href: document.baseURI }, setTimeout: fn => fn(),
    performance: { getEntriesByType: () => [{ name: videoURL }, { name: 'https://cdn.example/style.css' }] },
    MutationObserver: class { observe() {} },
    PerformanceObserver: class { constructor(callback) { resourceObserver = callback; } observe() {} },
    window: { webkit: { messageHandlers: { bakaMedia: { postMessage: value => messages.push(value) } } } }
});
vm.runInContext(script, context);
assert.equal(messages.length, 2);
assert.equal(messages[0].address, videoURL);
assert.equal(messages[1].address, 'https://mirror.example/episode.mp4?download=1');
resourceObserver({ getEntries: () => [{ name: 'https://cdn.example/live/playlist.m3u8?session=synthetic' }] });
assert.equal(messages.length, 3);
assert.equal(messages[2].source, 'Resource');
vm.runInContext(script, context);
assert.equal(messages.length, 3, 'Repeated injection must not install another observer');
context.window.__bakaScanMedia();
assert.equal(messages.length, 5, 'Rescan must rediscover current page sources');
assert(messages.every(value => value.pageAddress === document.baseURI));
console.log('Media discovery checks passed: DOM sources, relative links, blob rejection, deduplication, resources, rescan.');
