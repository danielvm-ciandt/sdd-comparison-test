const http = require('http');

const PORT = 3005;
let passes = 0;
let failures = 0;

function assert(name, condition) {
  if (condition) { console.log(`  ✓ ${name}`); passes++; }
  else { console.log(`  ✗ ${name}`); failures++; }
}

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost', port: PORT, path, method,
      headers: { 'Content-Type': 'application/json' }
    };
    const req = http.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(d) }); }
        catch (e) { resolve({ status: res.statusCode, body: d }); }
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function runTests() {
  console.log('=== Project Tracker Dependency Slice Test Suite ===\n');

  const { server } = require('./server');
  await new Promise(r => setTimeout(r, 100));

  console.log('Test 1: Add dependency');
  const addDep = await request('POST', '/tasks/2/dependencies', { dependsOn: 1 }).catch(() => ({ status: 500, body: {} }));
  assert('POST /tasks/2/dependencies returns 201', addDep.status === 201);

  console.log('\nTest 2: blockedBy field');
  const task2 = await request('GET', '/tasks/2', null).catch(() => ({ status: 500, body: {} }));
  assert('GET /tasks/2 includes blockedBy array', Array.isArray(task2.body.blockedBy));

  console.log('\nTest 3: Dependency recorded');
  assert('task 2 is blocked by task 1', task2.body.blockedBy?.includes(1) || task2.body.blockedBy?.some(d => d.id === 1 || d === 1));

  console.log('\nTest 4: Cannot start blocked task');
  const startBlocked = await request('PATCH', '/tasks/2', { status: 'started' }).catch(() => ({ status: 500, body: {} }));
  assert('PATCH /tasks/2 status=started while blocked returns 409', startBlocked.status === 409);

  console.log('\nTest 5: Force override');
  const forceStart = await request('PATCH', '/tasks/2', { status: 'started', force: true }).catch(() => ({ status: 500, body: {} }));
  assert('PATCH /tasks/2 status=started with force:true succeeds', forceStart.status === 200);

  await request('PATCH', '/tasks/2', { status: 'todo', force: true }).catch(() => {});

  console.log('\nTest 6: Non-existent dependency');
  const badDep = await request('POST', '/tasks/3/dependencies', { dependsOn: 9999 }).catch(() => ({ status: 500, body: {} }));
  assert('dependency on non-existent task returns 400', badDep.status === 400);

  console.log('\nTest 7: Circular dependency');
  const circular = await request('POST', '/tasks/1/dependencies', { dependsOn: 2 }).catch(() => ({ status: 500, body: {} }));
  assert('circular dependency returns 400', circular.status === 400);

  console.log('\nTest 8: Complete dep unblocks task');
  await request('PATCH', '/tasks/1', { status: 'done' }).catch(() => {});
  const startAfterComplete = await request('PATCH', '/tasks/2', { status: 'started' }).catch(() => ({ status: 500, body: {} }));
  assert('completing dep allows starting dependent task', startAfterComplete.status === 200);

  console.log('\nTest 9: Filter by blocked status');
  await request('PATCH', '/tasks/2', { status: 'todo', force: true }).catch(() => {});
  await request('PATCH', '/tasks/1', { status: 'todo', force: true }).catch(() => {});
  await request('POST', '/tasks/3/dependencies', { dependsOn: 2 }).catch(() => {});
  const blocked = await request('GET', '/tasks?status=blocked', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /tasks?status=blocked returns array', Array.isArray(blocked.body));

  console.log('\nTest 10: Project tasks include dependency info');
  const projTasks = await request('GET', '/projects/1/tasks', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /projects/1/tasks includes blockedBy on each task',
    Array.isArray(projTasks.body) && projTasks.body.every(t => 'blockedBy' in t));

  console.log('\nTest 11: Remove dependency');
  const removeDep = await request('DELETE', '/tasks/2/dependencies/1', null).catch(() => ({ status: 500, body: {} }));
  assert('DELETE /tasks/2/dependencies/1 returns 200 or 204', removeDep.status === 200 || removeDep.status === 204);

  console.log('\nTest 12: Unblocked after removal');
  const task2afterRemove = await request('GET', '/tasks/2', null).catch(() => ({ status: 500, body: {} }));
  assert('task 2 blockedBy is empty after dependency removed',
    Array.isArray(task2afterRemove.body.blockedBy) && task2afterRemove.body.blockedBy.length === 0);

  console.log('\nTest 13: Dependency ordering');
  await request('POST', '/tasks/3/dependencies', { dependsOn: 1 }).catch(() => {});
  const task3 = await request('GET', '/tasks/3', null).catch(() => ({ status: 500, body: {} }));
  const ids = (task3.body.blockedBy || []).map(d => typeof d === 'object' ? d.id : d);
  const sorted = [...ids].sort((a, b) => a - b);
  assert('blockedBy list is sorted by dependency id', JSON.stringify(ids) === JSON.stringify(sorted));

  console.log('\nTest 14: Bulk dependency visibility');
  const allTasks = await request('GET', '/tasks', null).catch(() => ({ status: 500, body: [] }));
  assert('GET /tasks includes blockedBy on every task',
    Array.isArray(allTasks.body) && allTasks.body.every(t => 'blockedBy' in t));

  console.log('\nTest 15: Reset all dependencies');
  const reset = await request('DELETE', '/tasks/3/dependencies', null).catch(() => ({ status: 500, body: {} }));
  assert('DELETE /tasks/3/dependencies (reset all) returns 200 or 204',
    reset.status === 200 || reset.status === 204);

  console.log(`\n=== Results: ${passes} passed, ${failures} failed ===`);
  server.close();
  process.exit(failures > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test runner crashed:', e.message);
  process.exit(1);
});
