import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalize, OUTSIDE } from '../src/config.js';

const room = { id: 'living', name: 'Living', rect: [0, 0, 4, 4] };
const lamp = (r) => ({ id: 'l', name: 'Lamp', room: r, type: 'post', pos: [6, 6] });

test('a lamp outside the house belongs to the Outside group', () => {
  const config = normalize({ rooms: [room], lights: [lamp(OUTSIDE)] });
  assert.deepEqual(config.groups.map((g) => g.id), ['living', OUTSIDE]);
  assert.equal(config.groups.at(-1).name, 'Outside');
});

test('the Outside group only shows when a lamp is out there', () => {
  assert.deepEqual(normalize({ rooms: [room], lights: [{ ...lamp('living'), type: 'ceiling' }] }).groups.map((g) => g.id), ['living']);
});

test('a room called "outside" is still a room, and no second group appears', () => {
  const config = normalize({ rooms: [room, { id: OUTSIDE, name: 'Patio', rect: [4, 0, 3, 3] }], lights: [lamp(OUTSIDE)] });
  assert.deepEqual(config.groups.map((g) => g.name), ['Living', 'Patio']);
});

test('an unknown room is still an error, and air conditioners cannot go outside', () => {
  assert.throws(() => normalize({ rooms: [room], lights: [lamp('garage')] }), /unknown room "garage"/);
  assert.throws(() => normalize({ rooms: [room], acs: [{ id: 'a', room: OUTSIDE, wall: 'north', pos: [1, 0] }] }), /unknown room "outside"/);
});

test('lamps outside count towards the site the outside view frames', () => {
  const config = normalize({ rooms: [room], lights: [{ ...lamp(OUTSIDE), pos: [100, 100] }] });
  assert.equal(config.siteBounds.maxX, 100);
  assert.equal(config.siteBounds.maxZ, 100);
  assert.equal(config.outsideArea, true);
});

test('with a room called "outside", nothing is treated as the outside group', () => {
  const config = normalize({ rooms: [room, { id: OUTSIDE, name: 'Patio', rect: [4, 0, 3, 3] }], lights: [lamp(OUTSIDE)] });
  assert.equal(config.outsideArea, false);
  assert.ok(config.groups.every((g) => !g.outside));
});
