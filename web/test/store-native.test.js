// The store in the Mac app, where the state lives in Swift: it sends intents and shows
// what the app answers (store.js, nativeState).
import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';

const messages = [];
const saved = new Map();
const STORAGE_KEY = 'house-control:state:v1';
saved.set(STORAGE_KEY, JSON.stringify({ home: 'Test home', lights: { lamp: { on: true } }, scene: 'old' }));
globalThis.window = {
  __HOUSE_BOOT__: {
    platform: 'macos',
    nativeState: true,
    state: { lights: { lamp: { on: false, brightness: 0.5 } }, acs: {}, features: {}, scene: 'cozy' },
  },
  webkit: { messageHandlers: { house: { postMessage(message) { messages.push(structuredClone(message)); } } } },
};
globalThis.localStorage = {
  getItem(key) { return saved.get(key) ?? null; },
  setItem(key, value) { saved.set(key, value); },
};

const { createStore } = await import('../src/store.js');
const config = {
  name: 'Test home', outdoorTemp: 30,
  lights: [{ id: 'lamp', capabilities: ['brightness'] }, { id: 'plug', capabilities: [] }],
  acs: [{ id: 'ac', min: 16, max: 30 }],
  scenes: [{ id: 'bright', lights: { '*': { on: true } }, acs: {} }],
};

beforeEach((t) => {
  messages.length = 0;
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
});

test('starts from the state the app booted it with; what the browser saved is handed over', () => {
  const store = createStore(config);
  assert.equal(store.restored, true);
  assert.equal(store.state.lights.lamp.brightness, 0.5);
  assert.equal(store.state.scene, 'cozy');
  assert.equal(store.legacy.scene, 'old');
  assert.equal(store.state.lights.lamp.on, false);
});

test('a change is shown at once and sent as an intent, never as a device command', (t) => {
  const store = createStore(config);
  store.source = 'ChatGPT';
  store.setLight('lamp', { on: true });
  store.applyScene('bright');
  t.mock.timers.tick(30000);
  assert.equal(store.state.lights.lamp.on, true);
  const intents = messages.filter((m) => m.type === 'intent');
  assert.deepEqual(intents.map((m) => [m.op, m.seq, m.source]), [['setLight', 1, 'ChatGPT'], ['applyScene', 2, 'ChatGPT']]);
  assert.equal(messages.filter((m) => ['command', 'state', 'summary'].includes(m.type)).length, 0);
  assert.equal(JSON.parse(saved.get(STORAGE_KEY)).scene, 'old'); // nothing saved here
});

test('the app\'s state is taken once it has seen every intent', () => {
  const store = createStore(config);
  store.setLight('lamp', { brightness: 0.6 });
  store.setLight('lamp', { brightness: 0.7 });
  const answer = (brightness, ack) => store.sync({ state: { lights: { lamp: { brightness } }, scene: null }, ack });
  answer(0.6, 1);
  assert.equal(store.state.lights.lamp.brightness, 0.7); // still ahead of the app
  answer(0.7, 2);
  assert.equal(store.state.lights.lamp.brightness, 0.7);
  const seen = [];
  store.on((change) => seen.push(change));
  store.sync({ state: { lights: { plug: { on: true } } }, ack: 2, source: 'Widget' });
  assert.equal(store.state.lights.plug.on, true);
  assert.equal(seen[0].remote, true);
  assert.equal(seen[0].source, 'Widget');
});

test('a tick only says the room temperature moved', () => {
  const store = createStore(config);
  const seen = [];
  store.on((change) => seen.push(change.type));
  store.sync({ state: { acs: { ac: { roomTemp: 21.3 } } }, ack: 0, tick: true });
  assert.equal(store.state.acs.ac.roomTemp, 21.3);
  assert.deepEqual(seen, ['tick']);
});
