import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const root = '../Packages/BakaKit/Sources/BakaUI/Resources/';
const discovery = fs.readFileSync(new URL(root + 'EpisodeDiscovery.js', import.meta.url), 'utf8');
const prepare = fs.readFileSync(new URL(root + 'PrepareEpisode.js', import.meta.url), 'utf8');
const messages = [];
const nodes = [
    ['/item/view/10/s1e1', '1'], ['/item/view/10/s1e1', 'First episode'],
    ['/item/view/10/s1e2?token=synthetic', 'Second episode'], ['/item/view/10/s2e1', 'Other season'],
    ['https://other.example/item/view/10/s1e3', 'External'],
    ['https://user:secret@mirror.example/item/view/10/s1e4', 'Credentials'],
    ['/item/view/10', 'Title'], ['javascript:alert(1)', 'Script']
].map(([href, textContent]) => ({textContent, getAttribute: name => name === 'href' ? href : null}));
let clicked = 0, scans = 0, ready = false;
const context = vm.createContext({
    URL, Map, JSON, setTimeout: fn => fn(), MutationObserver: class { observe() {} },
    document: {
        baseURI: 'https://mirror.example/item/view/10/s1e1', documentElement: {},
        querySelectorAll(selector) {
            if (selector === 'video source') return ready ? [{getAttribute: () => '/manifest/hls4/current.m3u8?token=synthetic'}] : [];
            return nodes;
        },
        querySelector: () => ({querySelector: () => ({click: () => { clicked++; }})})
    },
    location: {href: 'https://mirror.example/item/view/10/s1e1', origin: 'https://mirror.example'},
    window: {addEventListener() {}, webkit: {messageHandlers: {bakaEpisodes: {postMessage: value => messages.push(value)}}}}
});
vm.runInContext(discovery, context);
assert.equal(messages.length, 1);
assert.equal(messages[0].episodes.length, 3);
assert.equal(messages[0].episodes[0].title, 'First episode');
assert(!messages[0].episodes.some(value => value.address.includes('?') || value.address.includes('secret')));
vm.runInContext(discovery, context);
assert.equal(messages.length, 1, 'Duplicate injection must not register more observers');
context.window.__bakaScanEpisodes();
assert.equal(messages.length, 2, 'A native rescan must report episode metadata again');
context.window.__bakaScanMedia = () => { scans++; };
const request = vm.runInContext('(function(requested) {' + prepare + '})', context);
assert.equal(request(false), 'requested');
assert.equal(clicked, 1);
assert.equal(request(true), 'waiting');
assert.equal(clicked, 1, 'Polling must not repeatedly toggle the web player');
ready = true;
assert.equal(request(true), 'ready');
assert.equal(clicked, 1, 'An already prepared manifest must not toggle playback');
assert.equal(scans, 2);
console.log('Episode discovery checks passed: URL filtering, deduplication, rescan and single web-player activation.');
