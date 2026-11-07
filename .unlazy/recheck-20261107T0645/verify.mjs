import fs from 'node:fs';
import assert from 'node:assert/strict';
const load = name => JSON.parse(fs.readFileSync(new URL(name, import.meta.url)));
const pr = load('pr.json');
const run = load('after-run.json');
assert.equal(pr.state, 'MERGED');
assert.equal(run.head_sha, pr.mergeCommit.oid);
assert.equal(run.conclusion, 'success');
assert.equal(run.head_branch, 'main');
const durations = ['before', 'after'].map(side => {
  const job = load(`${side}-jobs.json`).jobs.find(job => job.name === 'ci');
  assert.equal(job.conclusion, 'success');
  return (Date.parse(job.completed_at) - Date.parse(job.started_at)) / 1000;
});
assert(durations.every(value => value > 0));
assert(durations[1] < durations[0]);
console.log(`MERGED_RUN_PROVEN: ${durations[0]}s -> ${durations[1]}s; n=1 each, queue excluded`);
