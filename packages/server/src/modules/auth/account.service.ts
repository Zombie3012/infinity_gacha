import { and, desc, eq, isNull } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { accountExternalIdentities, accountRecoveryTokens, accountSessions, accounts } from '../../database/drizzle-schema.js';
import { hashPassword } from './auth.js';
import {
  hashRecoveryToken, isRecoveryTokenUsable, isSupportedProvider, recoveryExpiry, recoveryToken, verifyProviderSignature,
} from './account-rules.js';

export class AccountError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'AccountError';
  }
}

export class AccountLinkService {
  private secret(): string {
    const secret = process.env.LINK_PROVIDER_SECRET ?? '';
    if (!secret) throw new AccountError('LINK_PROVIDER_NOT_CONFIGURED', 503);
    return secret;
  }

  async identities(accountId: string) {
    const rows = await db.select().from(accountExternalIdentities)
      .where(eq(accountExternalIdentities.accountId, accountId))
      .orderBy(desc(accountExternalIdentities.linkedAt));
    return rows.map(row => ({
      id: row.id,
      provider: row.provider,
      providerUserId: row.providerUserId,
      linkedAt: row.linkedAt,
    }));
  }

  /** Scenario 1.1 / 1.2: verify the provider hand-off, then claim the identity. */
  async link(accountId: string, providerInput: unknown, providerUserIdInput: unknown, providerTokenInput: unknown) {
    const provider = String(providerInput ?? '').toUpperCase();
    const providerUserId = String(providerUserIdInput ?? '').trim();
    const providerToken = String(providerTokenInput ?? '');
    if (!isSupportedProvider(provider)) throw new AccountError('Provider không hỗ trợ (GOOGLE | APPLE).', 400);
    if (!/^[A-Za-z0-9_.:@-]{3,128}$/.test(providerUserId)) throw new AccountError('providerUserId không hợp lệ.', 400);
    if (!verifyProviderSignature(this.secret(), provider, providerUserId, providerToken)) {
      throw new AccountError('ERR_AUTH_INVALID_PROVIDER_TOKEN', 401);
    }

    const [existing] = await db.select().from(accountExternalIdentities)
      .where(and(eq(accountExternalIdentities.provider, provider), eq(accountExternalIdentities.providerUserId, providerUserId))).limit(1);
    if (existing) throw new AccountError('ERR_AUTH_EXTERNAL_ID_ALREADY_LINKED', 409);

    const [alreadyLinked] = await db.select().from(accountExternalIdentities)
      .where(and(eq(accountExternalIdentities.accountId, accountId), eq(accountExternalIdentities.provider, provider))).limit(1);
    if (alreadyLinked) throw new AccountError('ERR_AUTH_PROVIDER_ALREADY_LINKED', 409);

    const [row] = await db.insert(accountExternalIdentities).values({
      id: uuidv4(), accountId, provider, providerUserId, linkedAt: new Date(),
    }).returning();
    return { id: row.id, provider: row.provider, providerUserId: row.providerUserId, linkedAt: row.linkedAt };
  }

  async unlink(accountId: string, providerInput: string) {
    const provider = providerInput.toUpperCase();
    const deleted = await db.delete(accountExternalIdentities)
      .where(and(eq(accountExternalIdentities.accountId, accountId), eq(accountExternalIdentities.provider, provider)))
      .returning({ id: accountExternalIdentities.id });
    if (deleted.length === 0) throw new AccountError('Chưa liên kết provider này.', 404);
    return { unlinked: provider };
  }

  /** Single-use recovery token, shown once and stored only as a hash. */
  async issueRecoveryToken(accountId: string, now = new Date()) {
    const token = recoveryToken();
    await db.insert(accountRecoveryTokens).values({
      id: uuidv4(),
      accountId,
      tokenHash: hashRecoveryToken(token),
      expiresAt: recoveryExpiry(now),
      createdAt: now,
    });
    return { token, expiresAt: recoveryExpiry(now) };
  }

  /** Scenario 1.3: redeem the token, rotate the password and revoke old sessions. */
  async recover(usernameInput: unknown, tokenInput: unknown, newPasswordInput: unknown, now = new Date()) {
    const username = String(usernameInput ?? '').trim().toLowerCase();
    const token = String(tokenInput ?? '').trim();
    const newPassword = String(newPasswordInput ?? '');
    if (!/^[a-z0-9]{3,32}$/.test(username)) throw new AccountError('ERR_AUTH_INVALID_REGISTRATION', 400);
    if (token.length < 8) throw new AccountError('ERR_AUTH_INVALID_RECOVERY_TOKEN', 401);
    if (newPassword.length < 8) throw new AccountError('Mật khẩu mới cần tối thiểu 8 ký tự.', 400);

    const [account] = await db.select().from(accounts).where(eq(accounts.username, username)).limit(1);
    if (!account) throw new AccountError('ERR_AUTH_INVALID_RECOVERY_TOKEN', 401);

    const [row] = await db.select().from(accountRecoveryTokens)
      .where(and(eq(accountRecoveryTokens.accountId, account.id), eq(accountRecoveryTokens.tokenHash, hashRecoveryToken(token))))
      .orderBy(desc(accountRecoveryTokens.createdAt)).limit(1);
    if (!row || !isRecoveryTokenUsable({ expiresAt: row.expiresAt, usedAt: row.usedAt }, now)) {
      throw new AccountError('ERR_AUTH_INVALID_RECOVERY_TOKEN', 401);
    }

    const passwordHash = await hashPassword(newPassword);
    await db.transaction(async tx => {
      await tx.update(accounts).set({ passwordHash, updatedAt: now }).where(eq(accounts.id, account.id));
      await tx.update(accountRecoveryTokens).set({ usedAt: now }).where(eq(accountRecoveryTokens.id, row.id));
      await tx.update(accountSessions).set({ revokedAt: now })
        .where(and(eq(accountSessions.accountId, account.id), isNull(accountSessions.revokedAt)));
    });

    return { recovered: true, username: account.username };
  }
}

export const accountLinkService = new AccountLinkService();
