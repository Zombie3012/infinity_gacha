import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canTransition, STATUS_TRANSITIONS, TICKET_STATUSES } from '../dist/modules/support/support.service.js';
import { ratio } from '../dist/modules/analytics/analytics.service.js';

test('P2 Support - ticket lifecycle', async (t) => {
  await t.test('OPEN can move to IN_PROGRESS, RESOLVED or CLOSED', () => {
    assert.equal(canTransition('OPEN', 'IN_PROGRESS'), true);
    assert.equal(canTransition('OPEN', 'RESOLVED'), true);
    assert.equal(canTransition('OPEN', 'CLOSED'), true);
  });

  await t.test('CLOSED is terminal', () => {
    assert.deepEqual(STATUS_TRANSITIONS.CLOSED, []);
    for (const status of TICKET_STATUSES) {
      assert.equal(canTransition('CLOSED', status), status === 'CLOSED' ? false : false);
    }
  });

  await t.test('RESOLVED can be reopened to IN_PROGRESS', () => {
    assert.equal(canTransition('RESOLVED', 'IN_PROGRESS'), true);
    assert.equal(canTransition('RESOLVED', 'CLOSED'), true);
  });

  await t.test('unknown statuses are rejected', () => {
    assert.equal(canTransition('NEW', 'OPEN'), false);
    assert.equal(canTransition('OPEN', 'PENDING'), false);
  });
});

test('P2 Analytics - ratio helper', async (t) => {
  await t.test('computes a four-decimal rate', () => {
    assert.deepEqual(ratio(1, 4), { numerator: 1, denominator: 4, rate: 0.25 });
    assert.equal(ratio(2, 3).rate, 0.6667);
  });

  await t.test('an empty denominator yields zero instead of NaN', () => {
    assert.equal(ratio(0, 0).rate, 0);
    assert.equal(ratio(5, 0).rate, 0);
  });

  await t.test('negative inputs are clamped to zero', () => {
    assert.equal(ratio(-3, 10).numerator, 0);
  });
});
