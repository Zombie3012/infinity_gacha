import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Identity = { id: string; provider: string; providerUserId: string; linkedAt: string };

async function call<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const when = (value: string) => new Date(value).toLocaleString('vi-VN');

export function AccountPage({ token, username, onError, onNotice }: {
  token: string; username: string; onError: (message: string) => void; onNotice: (message: string) => void;
}) {
  const [identities, setIdentities] = useState<Identity[]>([]);
  const [provider, setProvider] = useState('GOOGLE');
  const [providerUserId, setProviderUserId] = useState('');
  const [providerToken, setProviderToken] = useState('');
  const [recovery, setRecovery] = useState<{ token: string; expiresAt: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setIdentities(await call<Identity[]>('/api/account/identities', token));
  }, [token]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const run = async (action: () => Promise<unknown>, message: string) => {
    setBusy(true);
    onError('');
    try {
      await action();
      await load();
      onNotice(message);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const link = () => run(
    () => call('/api/account/identities', token, {
      method: 'POST',
      body: JSON.stringify({ provider, providerUserId, providerToken }),
    }),
    `Đã liên kết ${provider}.`,
  );

  const unlink = (value: string) => run(
    () => call(`/api/account/identities/${value}`, token, { method: 'DELETE' }),
    `Đã huỷ liên kết ${value}.`,
  );

  const issueRecovery = async () => {
    setBusy(true);
    onError('');
    try {
      const issued = await call<{ token: string; expiresAt: string }>('/api/account/recovery-token', token, { method: 'POST' });
      setRecovery(issued);
      onNotice('Đã tạo mã khôi phục — chỉ hiển thị một lần.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">ACCOUNT · PHASE 1</div>
        <h1>Tài khoản & khôi phục</h1>
        <p>Liên kết Google Play Games / Apple Game Center và tạo mã khôi phục dùng một lần.</p>
      </div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">IDENTITIES</div><h2>Liên kết bên thứ ba</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Provider</span><span>ID bên thứ ba</span><span>Liên kết lúc</span><span /></div>
        {identities.length === 0 && <div className="admin-row"><span>Chưa liên kết nền tảng nào.</span></div>}
        {identities.map(identity => <div className="admin-row" key={identity.id}>
          <span><em className="admin-badge ok">{identity.provider}</em></span>
          <span>{identity.providerUserId}</span>
          <span>{when(identity.linkedAt)}</span>
          <span><button type="button" className="text-button" disabled={busy} onClick={() => void unlink(identity.provider)}>Huỷ liên kết</button></span>
        </div>)}
      </div>

      <div className="admin-grid" style={{ marginTop: 16 }}>
        <label className="admin-field">Provider
          <select value={provider} onChange={event => setProvider(event.target.value)}>
            <option value="GOOGLE">GOOGLE</option>
            <option value="APPLE">APPLE</option>
          </select>
        </label>
        <label className="admin-field">Provider user id
          <input value={providerUserId} placeholder="google_uid_999" onChange={event => setProviderUserId(event.target.value)} />
        </label>
        <label className="admin-field">Provider token (HMAC)
          <input value={providerToken} placeholder="hmac sha256" onChange={event => setProviderToken(event.target.value)} />
        </label>
      </div>
      <p className="base-note">Prototype: token được kiểm tra bằng HMAC-SHA256 của <code>provider:providerUserId</code> với khoá <code>LINK_PROVIDER_SECRET</code> — không kết nối OAuth thật.</p>
      <div className="admin-actions">
        <button type="button" className="primary-button" disabled={busy || !providerUserId || !providerToken} onClick={() => void link()}>Liên kết</button>
      </div>
    </section>

    <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">RECOVERY</div><h2>Mã khôi phục</h2></div>
        <button type="button" className="secondary-button" disabled={busy} onClick={() => void issueRecovery()}>Tạo mã</button>
      </div>
      <p className="base-note">Mã dùng một lần, hết hạn sau 24 giờ. Dùng <code>POST /api/auth/recover</code> với <code>{`{ username: "${username}", recoveryToken, newPassword }`}</code> để lấy lại tài khoản; mọi phiên cũ sẽ bị thu hồi.</p>
      {recovery && <div className="recovery-box">
        <code>{recovery.token}</code>
        <small>Hết hạn: {when(recovery.expiresAt)} — sao chép ngay, hệ thống không hiển thị lại.</small>
      </div>}
    </section>
  </>;
}
