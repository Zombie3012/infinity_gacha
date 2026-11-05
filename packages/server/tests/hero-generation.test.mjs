import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  affinityColumns, buildSummonedHero, HERO_STAR_LOCKED, legacyClassFor,
} from '../dist/modules/hero/hero-generation.js';

const mageTemplate = {
  code: 'HERO_TEST_MAGE',
  defaultRarity: 5,
  heroClass: 'MAGE',
  archetypeWeights: { str: 0.15, int: 0.45, sta: 0.2, agi: 0.2 },
  classOptions: ['MAGE'],
  combatRole: 'MAGIC_DPS',
};

const thiefTemplate = {
  code: 'HERO_TEST_THIEF',
  defaultRarity: 5,
  heroClass: 'ASSASSIN',
  archetypeWeights: { str: 0.25, int: 0.15, sta: 0.2, agi: 0.4 },
  classOptions: ['THIEF'],
  combatRole: 'ASSASSIN',
};

test('Combat v2 - server summon build', async (t) => {
  await t.test('builds persisted values for a Mage', () => {
    const build = buildSummonedHero({ template: mageTemplate, bannerKind: 'STANDARD' });
    assert.equal(build.classCode, 'MAGE');
    assert.equal(build.legacyClass, 'MAGE');
    assert.ok(build.elementAffinity);
    assert.equal(build.base.str + build.base.int + build.base.sta + build.base.agi, 280);
    assert.equal(build.derived.maxHp, 20 * build.base.sta);
    assert.equal(build.derived.maxMp, 10 * build.base.int);
    assert.equal(build.legacySpeed, 60 + build.base.agi);
    const columns = affinityColumns(build.elementAffinity);
    assert.ok(columns.fire >= 0 && columns.fire <= 100);
    assert.ok(columns.lightning >= 0 && columns.lightning <= 100);
  });

  await t.test('maps Combat v2 classes to the legacy skill taxonomy', () => {
    assert.equal(legacyClassFor('THIEF'), 'ASSASSIN');
    assert.equal(legacyClassFor('SPEARMAN'), 'WARRIOR');
    assert.equal(legacyClassFor('MAGE'), 'MAGE');
    assert.equal(legacyClassFor('UNCLASSIFIED'), 'UNCLASSIFIED');
    const build = buildSummonedHero({ template: thiefTemplate, bannerKind: 'SPECIAL' });
    assert.equal(build.classCode, 'THIEF');
    assert.equal(build.legacyClass, 'ASSASSIN');
    assert.equal(build.elementAffinity, null);
  });

  await t.test('refuses locked 6-7 star templates', () => {
    assert.throws(
      () => buildSummonedHero({ template: { ...mageTemplate, defaultRarity: 6 } }),
      error => error.message === HERO_STAR_LOCKED,
    );
    assert.throws(
      () => buildSummonedHero({ template: { ...thiefTemplate, defaultRarity: 7 } }),
      error => error.message === HERO_STAR_LOCKED,
    );
  });

  await t.test('1-star templates always build an unclassified Hero', () => {
    const build = buildSummonedHero({
      template: { ...mageTemplate, defaultRarity: 1 },
      bannerKind: 'STANDARD',
    });
    assert.equal(build.classCode, 'UNCLASSIFIED');
    assert.equal(build.elementAffinity, null);
    assert.equal(build.base.str + build.base.int + build.base.sta + build.base.agi, 100);
  });
});
