import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';
const KEY_STORAGE = 'ig-admin-key';

type ConfigRow = {
  id: string;
  configKey: string;
  version: number;
  configValue: Record<string, unknown>;
  isActive: boolean;
  updatedBy: string;
  createdAt: string;
};

type AuditRow = {
  id: string;
  actorId: string;
  actorType: string;
  action: string;
  entityType: string;
  entityId: string;
  diffPayload: Record<string, unknown>;
  createdAt: string;
};

type Snapshot = {
  status: string;
  timestamp: string;
  uptimeSeconds: number;
  database: { connected: boolean; latencyMs: number; pool: { total: number; idle: number; waiting: number } };
  process: { nodeVersion: string; rssMb: number; heapUsedMb: number };
  counts: {
    accounts: number;
    masters: number;
    activeCombatSessions: number;
    openSecurityAlerts: number;
    auditEntries24h: number;
  };
};

type AlertRow = {
  id: string;
  accountId: string;
  signal: string;
  severity: string;
  status: string;
  details: Record<string, unknown>;
  createdAt: string;
};

const CONFIG_KEYS = ['GACHA_RULES', 'GACHA_PITY', 'DEATH_RULES', 'DUNGEON_RULES', 'SEED_ALGORITHM', 'BATTLE_RULES'];
const AUDIT_ACTIONS = [
  'CONFIG_VERSION_CREATED',
  'CONFIG_VERSION_ACTIVATED',
  'BANNER_CREATED',
  'BANNER_ACTIVATED',
  'BANNER_DEACTIVATED',
  'SECURITY_ALERT_RAISED',
  'SECURITY_ALERT_RESOLVED',
];
const TABS = [
  { id: 'config', label: 'Cấu hình' },
  { id: 'audit', label: 'Audit log' },
  { id: 'monitor', label: 'Giám sát' },
  { id: 'alerts', label: 'Cảnh báo' },
];

async function adminFetch<T>(key: string, path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', 'x-admin-api-key': key, ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const when = (value: string): string => new Date(value).toLocaleString('vi-VN');

export function AdminPage({ onError, onNotice }: { onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [tab, setTab] = useState('config');
  const [keyDraft, setKeyDraft] = useState('');
  const [adminKey, setAdminKey] = useState(() => sessionStorage.getItem(KEY_STORAGE) ?? '');
  const [busy, setBusy] = useState(false);

  const [configKey, setConfigKey] = useState('GACHA_PITY');
  const [configValue, setConfigValue] = useState('{\n  "baseRate": 0.004,\n  "exponentK": 4\n}');
  const [updatedBy, setUpdatedBy] = useState('ACT-04');
  const [activate, setActivate] = useState(true);
  const [configs, setConfigs] = useState<ConfigRow[]>([]);

  const [auditAction, setAuditAction] = useState('');
  const [audit, setAudit] = useState<AuditRow[]>([]);

  const [monitoring, setMonitoring] = useState<Snapshot | null>(null);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);

  const loadConfigs = useCallback(async (key: string, selected: string) => {
    const rows = await adminFetch<ConfigRow[]>(key, `/api/admin/configs?key=${encodeURIComponent(selected)}`);
    setConfigs(rows);
  }, []);

  const loadAudit = useCallback(async (key: string, action: string) => {
    const query = action ? `&action=${encodeURIComponent(action)}` : '';
    setAudit(await adminFetch<AuditRow[]>(key, `/api/admin/audit-logs?limit=100${query}`));
  }, []);

  const loadMonitoring = useCallback(async (key: string) => {
    setMonitoring(await adminFetch<Snapshot>(key, '/api/admin/monitoring'));
  }, []);

  const loadAlerts = useCallback(async (key: string) => {
    setAlerts(await adminFetch<AlertRow[]>(key, '/api/admin/security-alerts?limit=100'));
  }, []);

  useEffect(() => {
    if (!adminKey) return;
    const run = async () => {
      try {
        if (tab === 'config') await loadConfigs(adminKey, configKey);
        if (tab === 'audit') await loadAudit(adminKey, auditAction);
        if (tab === 'monitor') await loadMonitoring(adminKey);
        if (tab === 'alerts') await loadAlerts(adminKey);
      } catch (error) {
        onError((error as Error).message);
      }
    };
    void run();
  }, [adminKey, tab, configKey, auditAction, loadConfigs, loadAudit, loadMonitoring, loadAlerts, onError]);

  const saveKey = () => {
    const trimmed = keyDraft.trim();
    if (!trimmed) return;
    sessionStorage.setItem(KEY_STORAGE, trimmed);
    setAdminKey(trimmed);
    setKeyDraft('');
    onNotice('Đã lưu khoá quản trị cho phiên trình duyệt này.');
  };

  const createVersion = async () => {
    setBusy(true);
    onError('');
    try {
      let parsed: Record<string, unknown>;
      try {
        parsed = JSON.parse(configValue) as Record<string, unknown>;
      } catch {
        throw new Error('JSON không hợp lệ.');
      }
      await adminFetch<ConfigRow>(adminKey, '/api/admin/configs', {
        method: 'POST',
        body: JSON.stringify({ configKey, configValue: parsed, updatedBy, activate }),
      });
      await loadConfigs(adminKey, configKey);
      await loadAudit(adminKey, '');
      onNotice(`Đã tạo phiên bản mới cho ${configKey}.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const activateVersion = async (id: string) => {
    setBusy(true);
    onError('');
    try {
      await adminFetch<ConfigRow>(adminKey, `/api/admin/configs/${id}/activate`, { method: 'POST' });
      await loadConfigs(adminKey, configKey);
      onNotice('Đã chuyển con trỏ cấu hình đang hoạt động.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const resolveAlert = async (id: string) => {
    setBusy(true);
    onError('');
    try {
      await adminFetch<AlertRow>(adminKey, `/api/admin/security-alerts/${id}/resolve`, { method: 'POST' });
      await loadAlerts(adminKey);
      onNotice('Đã đóng cảnh báo.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const activeConfig = configs.find(row => row.isActive);

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">OPERATIONS · DM-14</div>
        <h1>Bảng điều khiển hệ thống</h1>
        <p>Cấu hình có phiên bản, nhật ký kiểm toán, sức khoẻ dịch vụ và cảnh báo an ninh.</p>
      </div>
      <div className="admin-key-box">
        <label htmlFor="admin-key">Khoá quản trị</label>
        <div className="admin-key-row">
          <input id="admin-key" type="password" value={keyDraft} placeholder={adminKey ? '•••••••• (đã lưu)' : 'x-admin-api-key'} onChange={event => setKeyDraft(event.target.value)} />
          <button type="button" className="secondary-button" onClick={saveKey}>Lưu</button>
        </div>
      </div>
    </div>

    {!adminKey
      ? <section className="panel"><div className="empty-state"><span className="empty-symbol">⚙</span><h3>Cần khoá quản trị</h3><p>Nhập giá trị <code>ADMIN_API_KEY</code> của server để mở các công cụ vận hành.</p></div></section>
      : <>
        <div className="admin-tabs">{TABS.map(item => <button key={item.id} type="button" className={`admin-tab ${tab === item.id ? 'active' : ''}`} onClick={() => setTab(item.id)}>{item.label}</button>)}</div>

        {tab === 'config' && <section className="panel">
          <div className="panel-head"><div><div className="eyebrow">VERSIONED RULES</div><h2>Cấu hình luật chơi</h2></div><span className="sample-tag">Active: {activeConfig ? `v${activeConfig.version}` : '—'}</span></div>
          <div className="admin-grid">
            <label className="admin-field">Nhóm luật
              <select value={configKey} onChange={event => setConfigKey(event.target.value)}>{CONFIG_KEYS.map(item => <option key={item} value={item}>{item}</option>)}</select>
            </label>
            <label className="admin-field">Người cập nhật
              <input value={updatedBy} maxLength={64} onChange={event => setUpdatedBy(event.target.value)} />
            </label>
            <label className="admin-field admin-check"><input type="checkbox" checked={activate} onChange={event => setActivate(event.target.checked)} /> Kích hoạt ngay</label>
          </div>
          <label className="admin-field">Giá trị JSON
            <textarea rows={7} value={configValue} onChange={event => setConfigValue(event.target.value)} spellCheck={false} />
          </label>
          <div className="admin-actions">
            <button type="button" className="primary-button" disabled={busy} onClick={() => void createVersion()}>Tạo phiên bản →</button>
            <button type="button" className="secondary-button" disabled={busy} onClick={() => void loadConfigs(adminKey, configKey).catch(error => onError((error as Error).message))}>Tải lại</button>
          </div>
          <div className="admin-table">
            <div className="admin-row admin-row-head"><span>Phiên bản</span><span>Người sửa</span><span>Thời điểm</span><span>Trạng thái</span><span /></div>
            {configs.length === 0 && <div className="admin-row"><span>Chưa có phiên bản nào cho {configKey}.</span></div>}
            {configs.map(row => <div className="admin-row" key={row.id}>
              <span><b>v{row.version}</b></span>
              <span>{row.updatedBy}</span>
              <span>{when(row.createdAt)}</span>
              <span>{row.isActive ? <em className="admin-badge ok">Đang dùng</em> : <em className="admin-badge">Lưu trữ</em>}</span>
              <span>{row.isActive ? null : <button type="button" className="text-button" disabled={busy} onClick={() => void activateVersion(row.id)}>Kích hoạt</button>}</span>
            </div>)}
          </div>
        </section>}

        {tab === 'audit' && <section className="panel">
          <div className="panel-head"><div><div className="eyebrow">AUDIT TRAIL</div><h2>Nhật ký hệ thống</h2></div>
            <div className="admin-actions">
              <select value={auditAction} onChange={event => setAuditAction(event.target.value)}>
                <option value="">Tất cả hành động</option>
                {AUDIT_ACTIONS.map(item => <option key={item} value={item}>{item}</option>)}
              </select>
              <button type="button" className="secondary-button" onClick={() => void loadAudit(adminKey, auditAction).catch(error => onError((error as Error).message))}>Tải lại</button>
            </div>
          </div>
          <div className="admin-table">
            <div className="admin-row admin-row-head"><span>Thời điểm</span><span>Actor</span><span>Hành động</span><span>Đối tượng</span><span>Chi tiết</span></div>
            {audit.length === 0 && <div className="admin-row"><span>Chưa có bản ghi.</span></div>}
            {audit.map(row => <div className="admin-row" key={row.id}>
              <span>{when(row.createdAt)}</span>
              <span>{row.actorId}<small className="admin-muted">{row.actorType}</small></span>
              <span>{row.action}</span>
              <span>{row.entityType}<small className="admin-muted">{row.entityId.slice(0, 8)}</small></span>
              <span className="admin-diff">{JSON.stringify(row.diffPayload)}</span>
            </div>)}
          </div>
        </section>}

        {tab === 'monitor' && <section className="panel">
          <div className="panel-head"><div><div className="eyebrow">SYSTEM HEALTH</div><h2>Giám sát dịch vụ</h2></div>
            <button type="button" className="secondary-button" onClick={() => void loadMonitoring(adminKey).catch(error => onError((error as Error).message))}>Làm mới</button>
          </div>
          {!monitoring ? <div className="empty-state"><p>Chưa có dữ liệu.</p></div> : <>
            <div className="stat-grid">
              <div className="stat-card"><span className="stat-icon gold">◈</span><div><small>Trạng thái</small><b>{monitoring.status.toUpperCase()}</b><span>DB {monitoring.database.connected ? 'kết nối' : 'mất kết nối'}</span></div></div>
              <div className="stat-card"><span className="stat-icon blue">◷</span><div><small>Độ trễ DB</small><b>{monitoring.database.latencyMs} ms</b><span>pool {monitoring.database.pool.total} / idle {monitoring.database.pool.idle}</span></div></div>
              <div className="stat-card"><span className="stat-icon violet">⏱</span><div><small>Uptime</small><b>{Math.floor(monitoring.uptimeSeconds / 60)} phút</b><span>RSS {monitoring.process.rssMb} MB · heap {monitoring.process.heapUsedMb} MB</span></div></div>
              <div className="stat-card"><span className="stat-icon rose">⚑</span><div><small>Cảnh báo mở</small><b>{monitoring.counts.openSecurityAlerts}</b><span>audit 24h: {monitoring.counts.auditEntries24h}</span></div></div>
            </div>
            <div className="admin-table">
              <div className="admin-row admin-row-head"><span>Chỉ số</span><span>Giá trị</span></div>
              <div className="admin-row"><span>Tài khoản</span><span>{monitoring.counts.accounts}</span></div>
              <div className="admin-row"><span>Master</span><span>{monitoring.counts.masters}</span></div>
              <div className="admin-row"><span>Phiên chiến đấu đang mở</span><span>{monitoring.counts.activeCombatSessions}</span></div>
              <div className="admin-row"><span>Node</span><span>{monitoring.process.nodeVersion}</span></div>
              <div className="admin-row"><span>Cập nhật lúc</span><span>{when(monitoring.timestamp)}</span></div>
            </div>
          </>}
        </section>}

        {tab === 'alerts' && <section className="panel">
          <div className="panel-head"><div><div className="eyebrow">SECURITY</div><h2>Cảnh báo gian lận / lạm dụng</h2></div>
            <button type="button" className="secondary-button" onClick={() => void loadAlerts(adminKey).catch(error => onError((error as Error).message))}>Làm mới</button>
          </div>
          <div className="admin-table">
            <div className="admin-row admin-row-head"><span>Thời điểm</span><span>Tài khoản</span><span>Tín hiệu</span><span>Mức độ</span><span /></div>
            {alerts.length === 0 && <div className="admin-row"><span>Không có cảnh báo nào.</span></div>}
            {alerts.map(row => <div className="admin-row" key={row.id}>
              <span>{when(row.createdAt)}</span>
              <span>{row.accountId.slice(0, 8)}</span>
              <span>{row.signal}<small className="admin-muted">{JSON.stringify(row.details)}</small></span>
              <span><em className={`admin-badge ${row.severity === 'CRITICAL' ? 'danger' : row.severity === 'HIGH' ? 'warn' : 'ok'}`}>{row.severity}</em></span>
              <span>{row.status === 'OPEN' ? <button type="button" className="text-button" disabled={busy} onClick={() => void resolveAlert(row.id)}>Đóng</button> : <small className="admin-muted">Đã xử lý</small>}</span>
            </div>)}
          </div>
        </section>}
      </>}
  </>;
}
