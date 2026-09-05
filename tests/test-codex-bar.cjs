const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../zebar/zebar-minimal-bar.html'), 'utf8');
const script = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1];
const moduleStub = script.replace(/import \* as zebar from '[^']+';/, 'const zebar = {};');
new vm.Script(moduleStub);
console.log('PASS Bar JavaScript parses.');
const render = script.slice(script.indexOf('function renderCodexUsage()'), script.indexOf('function updateBluetoothAvailability()'));
function element() {
  const label = { textContent: '' };
  const classes = new Set();
  const attributes = new Map();
  const styles = new Map();
  return { label, title: '', classes, attributes, styles, querySelector: () => label,
    style: { setProperty: (name, value) => styles.set(name, value) },
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name),
    classList: { toggle: (name, enabled) => enabled ? classes.add(name) : classes.delete(name) } };
}
const context = { codexUsageEl: element(), codexResetsEl: element(), codexStatus: null };
vm.createContext(context);
vm.runInContext(render, context);
function check(status, usage, resets) {
  context.codexStatus = status;
  vm.runInContext('renderCodexUsage()', context);
  assert.equal(context.codexUsageEl.label.textContent, usage);
  assert.equal(context.codexResetsEl.label.textContent, resets);
}
const fixture = { state: 'ok', timestamp: new Date().toISOString(), windows: [
  { name: 'primary', remainingPercent: 43, windowDurationMins: 10080, resetsAt: 1900000000 },
  { name: 'secondary', remainingPercent: 70, windowDurationMins: 300 },
], availableResets: 3 };
check(fixture, 'Codex 43%', 'Resets 3');
assert.equal(context.codexUsageEl.styles.get('--usage-fill'), '43%');
assert.equal(context.codexUsageEl.attributes.get('aria-valuenow'), '43');
assert.match(context.codexUsageEl.title, /Weekly: 43% remaining/);
assert.match(context.codexUsageEl.title, /5-hour: 70% remaining/);
console.log('PASS Display the limiting window, both tooltip periods, and available resets.');
check({ ...fixture, windows: [{ remainingPercent: 0 }], availableResets: 0 }, 'Codex 0%', 'Resets 0');
assert(context.codexUsageEl.classes.has('low'));
console.log('PASS Zero values display correctly and low usage is highlighted.');
check({ ...fixture, windows: [{ remainingPercent: 100 }], availableResets: null }, 'Codex 100%', 'Resets --');
console.log('PASS Unknown resets are not shown as zero.');
check({ ...fixture, timestamp: new Date(Date.now() - 360000).toISOString() }, 'Codex --', 'Resets --');
check({ ...fixture, state: 'unavailable' }, 'Codex --', 'Resets --');
check({ ...fixture, timestamp: 'invalid' }, 'Codex --', 'Resets --');
check(null, 'Codex --', 'Resets --');
assert.equal(context.codexUsageEl.styles.get('--usage-fill'), '0%');
assert(!context.codexUsageEl.attributes.has('aria-valuenow'));
console.log('PASS Stale, failed, missing, and invalid-timestamp reads do not show current values.');
check(fixture, 'Codex 43%', 'Resets 3');
assert(!context.codexUsageEl.classes.has('low'));
assert(!context.codexResetsEl.classes.has('unavailable'));
console.log('PASS Valid data restores the normal widget state.');
