import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type PlayerRow = {
  accountId: string;
  username: string;
  status: string;
  masterName: string | null;
  level: number | null;
  silverCoins: string | null;
};

type ItemRow = { code: string; name: string; category: string; rarity: number; isActive: boolean };
type HeroRow = { code: string; name: string; defaultRarity: number; heroClass: string; baseHp: number; baseAttack: number };

async function adminFetch<T>(key: string, path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', 'x-admin-api-key': key, ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const numberFormat = new Intl.NumberFormat('vi-VN');

export function OperatorTools({ section, adminKey, onError, onNotice }: {
  section: 'players' | 'content'; adminKey: string;
  onError: (message: string) => void; onNotice: (message: string) => void;
}) {
  const [query, setQuery] = useState('');
  const [players, setPlayers] = useState<PlayerRow[]>([]);
  const [selected, setSelected] = useState<PlayerRow | null>(null);
  const [silver, setSilver] = useState('1000');
  const [gems, setGems] = useState('0');
  const [subject, setSubject] = useState('Bồi thường từ vận hành viên');
  const [items, setItems] = useState<ItemRow[]>([]);
  const [heroes, setHeroes] = useState<HeroRow[]>([]);
  const [newItem, setNewItem] = useState({ code: '', name: '', category: 'MATERIAL', rarity: '1' });
  const [busy, setBusy] = useState(false);

  const loadContent = useCallback(async () => {
    const [itemRows, heroRows] = await Promise.all([
      adminFetch<ItemRow[]>(adminKey, '/api/admin/content/items'),
      adminFetch<HeroRow[]>(adminKey, '/api/admin/content/heroes'),
    ]);
    setItems(itemRows);
    setHeroes(heroRows);
  }, [adminKey]);

  useEffect(() => {
    if (section === 'content') loadContent().catch(error => onError((error as Error).message));
  }, [section, loadContent, onError]);

  const search = async () => {
    setBusy(true);
    onError('');
    try {
      setPlayers(await adminFetch<PlayerRow[]>(adminKey, `/api/admin/players?query=${encodeURIComponent(query)}`));
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const restrict = async (row: PlayerRow, status: string) => {
    setBusy(true);
    onError('');
    try {
      await adminFetch(adminKey, `/api/admin/players/${row.accountId}/restrict`, { method: 'POST', body: JSON.stringify({ status, reason: 'operator action' }) });
      await search();
      onNotice(`Đã áp dụng ${status} cho ${row.username}.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const restore = async (row: PlayerRow) => {
    setBusy(true);
    onError('');
    try {
      await adminFetch(adminKey, `/api/admin/players/${row.accountId}/restore`, { method: 'POST' });
      await search();
      onNotice(`Đã khôi phục ${row.username}.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const compensate = async () => {
    if (!selected) return;
    setBusy(true);
    onError('');
    try {
      await adminFetch(adminKey, `/api/admin/players/${selected.accountId}/compensation`, {
        method: 'POST',
        body: JSON.stringify({ silver: Number(silver) || 0, gems: Number(gems) || 0, subject }),
      });
      onNotice(`Đã gửi bồi thường cho ${selected.username}.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const createItem = async () => {
    setBusy(true);
    onError('');
    try {
      await adminFetch(adminKey, '/api/admin/content/items', {
        method: 'POST',
        body: JSON.stringify({
          code: newItem.code, name: newItem.name, category: newItem.category, rarity: Number(newItem.rarity) || 1,
        }),
      });
      await loadContent();
      setNewItem({ code: '', name: '', category: 'MATERIAL', rarity: '1' });
      onNotice('Đã lưu vật phẩm.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  if (section === 'players') {
    return <>
      <section className="panel">
        <div className="panel-head">
          <div><div className="eyebrow">SUPPORT TOOLS</div><h2>Tìm người chơi</h2></div>
          <div className="admin-actions">
            <input value={query} placeholder="username hoặc tên Master" onChange={event => setQuery(event.target.value)} />
            <button type="button" className="secondary-button" disabled={busy || query.length < 2} onClick={() => void search()}>Tìm</button>
          </div>
        </div>
        <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Tài khoản</span><span>Master</span><span>Trạng thái</span><span>Xu</span><span>Hành động</span></div>
          {players.length === 0 && <div className="admin-row"><span>Nhập ít nhất 2 ký tự để tìm.</span></div>}
          {players.map(row => <div className="admin-row" key={row.accountId}>
            <span>{row.username}<small className="admin-muted">{row.accountId.slice(0, 8)}</small></span>
            <span>{row.masterName ?? '—'}<small className="admin-muted">Lv.{row.level ?? 0}</small></span>
            <span><em className={`admin-badge ${row.status === 'ACTIVE' ? 'ok' : 'danger'}`}>{row.status}</em></span>
            <span>{row.silverCoins ? numberFormat.format(Number(row.silverCoins)) : '—'}</span>
            <span className="admin-actions">
              <button type="button" className="text-button" disabled={busy} onClick={() => setSelected(row)}>Chọn</button>
              <button type="button" className="text-button" disabled={busy || row.status !== 'ACTIVE'} onClick={() => void restrict(row, 'SUSPENDED')}>Đình chỉ</button>
              <button type="button" className="text-button" disabled={busy || row.status === 'BANNED'} onClick={() => void restrict(row, 'BANNED')}>Cấm</button>
              <button type="button" className="text-button" disabled={busy || row.status === 'ACTIVE'} onClick={() => void restore(row)}>Khôi phục</button>
            </span>
          </div>)}
        </div>
      </section>

      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">COMPENSATION</div><h2>Bồi thường {selected ? `— ${selected.username}` : ''}</h2></div></div>
        <div className="admin-grid">
          <label className="admin-field">Xu Bạc
            <input value={silver} onChange={event => setSilver(event.target.value)} />
          </label>
          <label className="admin-field">Ngọc
            <input value={gems} onChange={event => setGems(event.target.value)} />
          </label>
          <label className="admin-field">Tiêu đề thư
            <input value={subject} onChange={event => setSubject(event.target.value)} />
          </label>
        </div>
        <div className="admin-actions">
          <button type="button" className="primary-button" disabled={busy || !selected} onClick={() => void compensate()}>Gửi bồi thường</button>
          {!selected && <small className="admin-muted">Chọn một người chơi ở bảng trên trước.</small>}
        </div>
      </section>
    </>;
  }

  return <>
    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">ITEM CATALOGUE</div><h2>Vật phẩm</h2></div></div>
      <div className="admin-grid">
        <label className="admin-field">Mã
          <input value={newItem.code} placeholder="ITEM_CODE" onChange={event => setNewItem({ ...newItem, code: event.target.value.toUpperCase() })} />
        </label>
        <label className="admin-field">Tên
          <input value={newItem.name} onChange={event => setNewItem({ ...newItem, name: event.target.value })} />
        </label>
        <label className="admin-field">Nhóm / độ hiếm
          <input value={`${newItem.category} · ${newItem.rarity}`} onChange={event => {
            const [category, rarity] = event.target.value.split('·').map(part => part.trim());
            setNewItem({ ...newItem, category: category || 'MATERIAL', rarity: rarity || '1' });
          }} />
        </label>
      </div>
      <div className="admin-actions">
        <button type="button" className="primary-button" disabled={busy || !newItem.code || !newItem.name} onClick={() => void createItem()}>Lưu vật phẩm</button>
      </div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Mã</span><span>Tên</span><span>Nhóm</span><span>Độ hiếm</span><span>Trạng thái</span></div>
        {items.map(row => <div className="admin-row" key={row.code}>
          <span>{row.code}</span>
          <span>{row.name}</span>
          <span>{row.category}</span>
          <span>{row.rarity}★</span>
          <span><em className={`admin-badge ${row.isActive ? 'ok' : ''}`}>{row.isActive ? 'Đang dùng' : 'Tắt'}</em></span>
        </div>)}
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">HERO TEMPLATES</div><h2>Hero & chỉ số</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Mã</span><span>Tên</span><span>Độ hiếm</span><span>Class</span><span>HP / ATK</span></div>
        {heroes.map(row => <div className="admin-row" key={row.code}>
          <span>{row.code}</span>
          <span>{row.name}</span>
          <span>{row.defaultRarity}★</span>
          <span>{row.heroClass}</span>
          <span>{numberFormat.format(row.baseHp)} / {numberFormat.format(row.baseAttack)}</span>
        </div>)}
      </div>
    </section>
  </>;
}
