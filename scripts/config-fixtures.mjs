// Writes core/Tests/HomeStoreTests/Fixtures/<plan>.json: what web/src/config.js normalize() makes
// of each demo plan (the parts HomeConfig reads), so the Swift reading is tested against it.
// Run with Node from the repository: node scripts/config-fixtures.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { normalize, lampIcon } from '../web/src/config.js';

const root = fileURLToPath(new URL('..', import.meta.url));
for (const plan of ['home', 'studio']) {
  const c = normalize(JSON.parse(readFileSync(`${root}web/public/plans/${plan}.json`, 'utf8')));
  const out = {
    name: c.name,
    groups: c.groups.map((g) => ({ id: g.id, name: g.name, outside: Boolean(g.outside) })),
    lights: c.lights.map((l) => ({ id: l.id, name: l.name, room: l.room, type: l.type, capabilities: l.capabilities, icon: lampIcon(l) })),
    acs: c.acs.map((a) => ({ id: a.id, name: a.name, room: a.room, min: a.min, max: a.max })),
    scenes: c.scenes.map((s) => ({ id: s.id, name: s.name, icon: s.icon })),
  };
  writeFileSync(`${root}core/Tests/HomeStoreTests/Fixtures/${plan}.json`, `${JSON.stringify(out, null, 2)}\n`);
  console.log(plan, out.groups.length, 'groups', out.lights.length, 'lights');
}
