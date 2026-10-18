import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';

const messages = [];
const saved = new Map();
globalThis.window = {
  __HOUSE_BOOT__: { platform: 'macos' },
  webkit: { messageHandlers: { house: { postMessage(message) { messages.push(structuredClone(message)); } } } },
};
globalThis.localStorage = {
  getItem(key) { return saved.get(key) ?? null; },
  setItem(key, value) { saved.set(key, value); },
};

const { createStore, AC_MODES, AC_FANS } = await import('../src/store.js');
const STORAGE_KEY = 'house-control:state:v1';
const config = {
  name: 'Test home', outdoorTemp: 30,
  lights: [{ id: 'lamp', capabilities: ['brightness', 'temp', 'color'] }],
  acs: [{ id: 'ac', min: 16, max: 30, sensor: { id: 'sensor' } }],
  scenes: [],
};
const features = { modes: ['cool', 'dry'], fans: ['low', 'high'], sleep: false, eco: true, swing: false };
const update = {
  lights: { lamp: { on: true, brightness: 0.4, temp: 3500 } },
  acs: { ac: { on: true, target: 22, mode: 'dry', fan: 'high', swing: 'off', sleep: false, eco: true, roomTemp: 25.5 } },
  features: { ac: features },
};

beforeEach((t) => {
  messages.length = 0;
  saved.clear();
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
});

test('share carries the real AC capabilities and device state to another store', () => {
  const a = createStore(config);
  const b = createStore(config);
  a.applyRemote(update);
  messages.length = 0;
  a.share();
  const shared = messages.find((m) => m.type === 'state');
  assert.deepEqual(shared.features, update.features);
  b.adopt(shared);
  assert.deepEqual(b.state, a.state);
  assert.deepEqual(b.acFeatures('ac'), a.acFeatures('ac'));
});

test('adopt never sends device commands or echoes state to the other view', (t) => {
  const store = createStore(config);
  store.adopt({ ...update, scene: 'evening' });
  t.mock.timers.tick(30000);
  assert.deepEqual(store.state.acs.ac, update.acs.ac);
  assert.equal(store.state.lights.lamp.on, true);
  assert.equal(store.state.scene, 'evening');
  assert.deepEqual(store.acFeatures('ac'), features);
  assert.equal(messages.filter((m) => m.type === 'command').length, 0);
  assert.equal(messages.filter((m) => m.type === 'state').length, 0);
});

test('capability-only reports broadcast, notify, and persist when adopted', (t) => {
  const a = createStore(config);
  const b = createStore(config);
  const changes = [];
  b.on((change) => changes.push(change));
  a.applyRemote({ features: update.features });
  const broadcast = messages.find((m) => m.type === 'state');
  assert.deepEqual(broadcast.features, update.features);
  b.adopt(broadcast);
  assert.deepEqual(b.acFeatures('ac'), features);
  assert.equal(changes.length, 1);
  assert.equal(changes[0].adopted, true);
  b.adopt(broadcast);
  assert.equal(changes.length, 1, 'unchanged capabilities do not notify again');
  t.mock.timers.tick(200);
  assert.deepEqual(JSON.parse(saved.get(STORAGE_KEY)).features, update.features);
  assert.deepEqual(createStore(config).acFeatures('ac'), features);
});

test('older saved state without capabilities still restores and can be adopted', () => {
  const legacy = { home: config.name, lights: update.lights, acs: update.acs, scene: 'evening' };
  saved.set(STORAGE_KEY, JSON.stringify(legacy));
  const store = createStore(config);
  assert.equal(store.restored, true);
  assert.deepEqual(store.state.acs.ac, legacy.acs.ac);
  assert.equal(store.state.lights.lamp.brightness, 0.4);
  assert.equal(store.state.scene, 'evening');
  assert.deepEqual(store.acFeatures('ac'), { modes: AC_MODES, fans: AC_FANS, sleep: true, eco: true, swing: true });
  store.adopt({ ...legacy, acs: { ac: { target: 23 } } });
  assert.equal(store.state.acs.ac.target, 23);
});
