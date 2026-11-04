import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Tile = {
  id: string;
  x: number;
  y: number;
  terrain: string;
  resourceType: string;
  baseYieldPerHour: number;
  requiredPower: number;
  discovered: boolean;
  owner: { masterId: string; name: string; level: number; status: string } | null;
  mine: boolean;
};

type Status = {
  unlocked: boolean;
  eligible: { ok: boolean; reason?: string };
  masterLevel: number;
  clearedFloor: number;
  base: { x: number; y: number } | null;
  shieldUntil: string | null;
  shieldActive: boolean;
  progress: { discovered: number; totalTiles: number; owned: number; maxTerritories: number };
};

type Territory = {
  id: string;
  tileId: string;
  level: number;
  status: string;
  hourlyYield: number;
  tile: { x: number; y: number; resourceType: string };
};

async function call<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const numberFormat = new Intl.NumberFormat('vi-VN');
const when = (value: string) => new Date(value).toLocaleString('vi-VN');

export function WorldMapPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [status, setStatus] = useState<Status | null>(null);
  const [tiles, setTiles] = useState<Tile[]>([]);
  const [territories, setTerritories] = useState<Territory[]>([]);
  const [selected, setSelected] = useState<Tile | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const worldStatus = await call<Status>('/api/world/global', token);
    setStatus(worldStatus);
    if (!worldStatus.unlocked) {
      setTiles([]);
      setTerritories([]);
      return;
    }
    const [map, mine] = await Promise.all([
      call<{ tiles: Tile[] }>('/api/world/global/map', token),
      call<{ territories: Territory[]; hourlyYield: number }>('/api/world/territories', token),
    ]);
    setTiles(map.tiles);
    setTerritories(mine.territories);
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

  if (!status) return <section className="panel"><div className="empty-state"><p>Đang tải bản đồ thế giới…</p></div></section>;

  if (!status.unlocked) {
    return <>
      <div className="page-heading">
        <div>
          <div className="eyebrow">GLOBAL WORLD · PHASE 3</div>
          <h1>Thế giới chung</h1>
          <p>Mở khoá bản đồ thế giới để chiếm lãnh thổ và cạnh tranh với người chơi khác.</p>
        </div>
      </div>
      <section className="panel">
        <div className="empty-state">
          <span className="empty-symbol">✦</span>
          <h3>Chưa mở khoá</h3>
          <p>Cần Master Cấp 15 và vượt Dungeon Tầng 10. Hiện tại: Cấp {status.masterLevel} · Tầng {status.clearedFloor}.</p>
          <button type="button" className="primary-button" disabled={busy || !status.eligible.ok}
            onClick={() => void run(() => call('/api/world/global/unlock', token, { method: 'POST' }), 'Đã mở khoá Thế giới chung.')}>
            Mở khoá ngay
          </button>
        </div>
      </section>
    </>;
  }

  const columns = Math.max(...tiles.map(tile => tile.x)) - Math.min(...tiles.map(tile => tile.x)) + 1;

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">GLOBAL WORLD · PHASE 3</div>
        <h1>Thế giới chung</h1>
        <p>Căn cứ tại ({status.base?.x}, {status.base?.y}) · đã khám phá {status.progress.discovered}/{status.progress.totalTiles} ô · lãnh thổ {status.progress.owned}/{status.progress.maxTerritories}</p>
      </div>
      <div className="date-chip"><span className="date-icon">◷</span><span><b>Khiên tân thủ</b><small>{status.shieldActive && status.shieldUntil ? when(status.shieldUntil) : 'đã hết'}</small></span></div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">MAP</div><h2>Bản đồ vùng rìa</h2></div>
        <button type="button" className="secondary-button" onClick={() => void load().catch(error => onError((error as Error).message))}>Làm mới</button>
      </div>
      <div className="world-grid" style={{ gridTemplateColumns: `repeat(${columns}, 1fr)` }}>
        {tiles.map(tile => <button key={tile.id} type="button"
          className={`world-cell ${tile.mine ? 'mine' : tile.owner ? 'enemy' : tile.discovered ? 'known' : 'fog'} ${selected?.id === tile.id ? 'selected' : ''}`}
          title={`(${tile.x}, ${tile.y}) · ${tile.resourceType} · ${tile.discovered ? 'đã biết' : 'sương mù'}`}
          onClick={() => setSelected(tile)}>
          {tile.discovered ? tile.resourceType.slice(0, 2) : '··'}
        </button>)}
      </div>
      {selected && <div className="world-detail">
        <b>Ô ({selected.x}, {selected.y}) · {selected.terrain}</b>
        <span>{selected.resourceType} · {numberFormat.format(selected.baseYieldPerHour)}/giờ · yêu cầu lực chiến {numberFormat.format(selected.requiredPower)}</span>
        <div className="admin-actions">
          {!selected.discovered && <button type="button" className="secondary-button" disabled={busy}
            onClick={() => void run(() => call(`/api/world/global/tiles/${selected.id}/discover`, token, { method: 'POST' }), 'Đã trinh sát ô đất.')}>Trinh sát</button>}
          {selected.discovered && !selected.owner && <button type="button" className="primary-button" disabled={busy}
            onClick={() => void run(() => call(`/api/world/global/tiles/${selected.id}/claim`, token, { method: 'POST' }), 'Đã chiếm lãnh thổ.')}>Chiếm đóng</button>}
          {selected.owner && !selected.mine && <em className="admin-badge danger">{selected.owner.name}</em>}
          {selected.mine && <em className="admin-badge ok">Lãnh thổ của bạn</em>}
        </div>
      </div>}
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">TERRITORIES</div><h2>Lãnh thổ của bạn</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Tọa độ</span><span>Tài nguyên</span><span>Cấp</span><span>Sản lượng/giờ</span><span>Hành động</span></div>
        {territories.length === 0 && <div className="admin-row"><span>Chưa chiếm lãnh thổ nào.</span></div>}
        {territories.map(row => <div className="admin-row" key={row.id}>
          <span>({row.tile.x}, {row.tile.y})<small className="admin-muted">{row.status}</small></span>
          <span>{row.tile.resourceType}</span>
          <span>{row.level}</span>
          <span>{numberFormat.format(row.hourlyYield)}</span>
          <span className="admin-actions">
            <button type="button" className="text-button" disabled={busy || row.status !== 'OWNED'}
              onClick={() => void run(() => call(`/api/world/territories/${row.id}/upgrade`, token, { method: 'POST' }), 'Đã nâng cấp lãnh thổ.')}>Nâng cấp</button>
            <button type="button" className="text-button" disabled={busy || row.status !== 'OWNED'}
              onClick={() => void run(() => call(`/api/world/territories/${row.id}/abandon`, token, { method: 'POST' }), 'Đã bắt đầu giải phóng lãnh thổ.')}>Từ bỏ</button>
          </span>
        </div>)}
      </div>
    </section>
  </>;
}
