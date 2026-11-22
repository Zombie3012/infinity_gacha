import type { db } from './db.js';

export type GameTransaction = Parameters<Parameters<typeof db.transaction>[0]>[0];
export type GameDatabase = typeof db | GameTransaction;
