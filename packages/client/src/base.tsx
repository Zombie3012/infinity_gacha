import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type ProductionProfile = { resourceType: string; ratePerHour: number; capacity: number };

type BuildingType = {
  code: string;
  name: string;
  category: string;
  description: string;
  maxLevel: number;
  maxWorkers: number;
  requiredWorldLevel: number;
  buildCostSilver: number;
  production: ProductionProfile | null;
  unlocked: boolean;
};

type Worker = { heroInstanceId: string; heroName: string; heroLevel: number; efficiencyBoost: number };

type Building = {
  id: string;
  buildingType: string;
  plotIndex: number;
  level: number;
  status: string;
  upgradeFinishesAt: string | null;
  typeName: string;
  maxLevel: number;
  maxWorkers: number;
  ratePerHour: number;
  capacity: number;
  stored: number;
  atCapacity: boolean;
  resourceType: string | null;
  workers: Worker[];
};

type Overview = {
  master: { silverCoins: string };
  world: { currentFloor: number; worldLevel: number; baseZones: number; plots: number };
  expansion: { canExpand: boolean; nextZone: number | null; costSilver: number | null; requiredWorldLevel: number | null; maxZones: number };
  buildingTypes: BuildingType[];
  buildings: Building[];
  plots: number[];
};

type HeroOption = { id: string; name: string; level: number; state: string };

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

export function BasePage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [heroes, setHeroes] = useState<HeroOption[]>([]);
  const [selectedType, setSelectedType] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [base, roster] = await Promise.all([
      call<Overview>('/api/base/overview', token),
      call<HeroOption[]>('/api/heroes', token).catch(() => []),
    ]);
    setOverview(base);
    setHeroes(roster.filter(hero => hero.state !== 'DEAD'));
    if (!selectedType) {
      const firstUnlocked = base.buildingTypes.find(type => type.unlocked);
      if (firstUnlocked) setSelectedType(firstUnlocked.code);
    }
  }, [token, selectedType]);

  useEffect(() => {
    load().catch(error => onError((error as Error).message));
  }, [load, onError]);

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

  const build = (plotIndex: number) => run(
    () => call('/api/base/buildings', token, { method: 'POST', body: JSON.stringify({ buildingType: selectedType, plotIndex }) }),
    'Đã khởi công công trình.',
  );

  const upgrade = (building: Building) => run(
    () => call(`/api/base/buildings/${building.id}/upgrade`, token, { method: 'POST' }),
    `Đang nâng cấp ${building.typeName} lên cấp ${building.level + 1}.`,
  );

  const demolish = (building: Building) => run(
    () => call(`/api/base/buildings/${building.id}/demolish`, token, { method: 'POST' }),
    `Đã phá dỡ ${building.typeName}.`,
  );

  const collect = (building: Building) => run(
    () => call<{ collected: number; resourceType: string }>(`/api/base/buildings/${building.id}/collect`, token, { method: 'POST' }),
    'Đã thu thập tài nguyên.',
  );

  const expand = () => run(
    () => call('/api/base/expand', token, { method: 'POST' }),
    'Đã mở rộng căn cứ.',
  );

  const assign = (building: Building, heroId: string) => {
    if (!heroId) return;
    return run(
      () => call(`/api/base/buildings/${building.id}/workers`, token, { method: 'POST', body: JSON.stringify({ heroId }) }),
      'Đã phân công Hero.',
    );
  };

  const remove = (building: Building, heroId: string) => run(
    () => call(`/api/base/buildings/${building.id}/workers/${heroId}`, token, { method: 'DELETE' }),
    'Đã thu hồi Hero.',
  );

  if (!overview) {
    return <section className="panel"><div className="empty-state"><p>Đang tải căn cứ…</p></div></section>;
  }

  const buildingByPlot = new Map(overview.buildings.map(building => [building.plotIndex, building]));
  const unlockedTypes = overview.buildingTypes.filter(type => type.unlocked);
  const busyBuilding = (building: Building) => building.status !== 'READY';

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">BASE · PHASE 1</div>
        <h1>Căn cứ & sản xuất</h1>
        <p>Mở rộng lãnh thổ, dựng công trình và để Hero lao động sinh tài nguyên, kể cả khi bạn offline.</p>
      </div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon gold">◈</span><div><small>Xu Bạc</small><b>{numberFormat.format(Number(overview.master.silverCoins))}</b><span>dùng để xây và nâng cấp</span></div></div>
      <div className="stat-card"><span className="stat-icon violet">◎</span><div><small>World Level</small><b>Lv.{overview.world.worldLevel}</b><span>tầng hiện tại {overview.world.currentFloor}</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">▦</span><div><small>Vùng đất</small><b>{overview.world.baseZones} / {overview.expansion.maxZones}</b><span>{overview.world.plots} ô xây dựng</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">⌂</span><div><small>Công trình</small><b>{overview.buildings.length}</b><span>trên {overview.world.plots} ô</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">TERRITORY</div><h2>Mở rộng lãnh thổ</h2></div>
        <button type="button" className="secondary-button" disabled={busy || !overview.expansion.canExpand} onClick={() => void expand()}>
          {overview.expansion.canExpand ? `Mở vùng ${overview.expansion.nextZone} · ${numberFormat.format(overview.expansion.costSilver ?? 0)} Xu` : 'Đã mở tối đa'}
        </button>
      </div>
      <p className="base-note">
        {overview.expansion.canExpand
          ? `Vùng kế tiếp cần World Level ${overview.expansion.requiredWorldLevel}. Mỗi vùng mở thêm 3 ô đất.`
          : `Căn cứ đã mở tối đa ${overview.expansion.maxZones} vùng.`}
      </p>
    </section>

    <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">BUILDINGS</div><h2>Ô đất & công trình</h2></div>
        <label className="admin-field base-type-picker">Xây mới
          <select value={selectedType} onChange={event => setSelectedType(event.target.value)}>
            {unlockedTypes.map(type => <option key={type.code} value={type.code}>{type.name} · {numberFormat.format(type.buildCostSilver)} Xu</option>)}
          </select>
        </label>
      </div>

      <div className="base-grid">
        {overview.plots.map(plot => {
          const building = buildingByPlot.get(plot);
          if (!building) {
            return <button key={plot} type="button" className="plot-card plot-empty" disabled={busy || !selectedType} onClick={() => void build(plot)}>
              <span className="plot-index">Ô {plot}</span>
              <strong>+</strong>
              <small>Xây {unlockedTypes.find(type => type.code === selectedType)?.name ?? 'công trình'}</small>
            </button>;
          }
          const working = busyBuilding(building);
          return <article key={plot} className="plot-card">
            <header><span className="plot-index">Ô {building.plotIndex}</span><em className={`admin-badge ${working ? 'warn' : 'ok'}`}>{building.status === 'READY' ? 'Sẵn sàng' : building.status === 'UPGRADING' ? 'Đang nâng cấp' : 'Đang xây'}</em></header>
            <h3>{building.typeName} <small>Lv.{building.level}/{building.maxLevel}</small></h3>
            {building.resourceType && <p className="plot-prod">
              {building.resourceType} · {numberFormat.format(building.ratePerHour)}/giờ
              <span>{numberFormat.format(Math.floor(building.stored))} / {numberFormat.format(building.capacity)}</span>
            </p>}
            {building.atCapacity && <p className="plot-warn">Kho đầy — sản xuất đang tạm dừng.</p>}
            <div className="plot-workers">
              {building.workers.length === 0 && building.maxWorkers > 0 && <small>Chưa có Hero làm việc</small>}
              {building.workers.map(worker => <span key={worker.heroInstanceId} className="worker-chip">
                {worker.heroName} · +{Math.round((worker.efficiencyBoost - 1) * 100)}%
                <button type="button" onClick={() => void remove(building, worker.heroInstanceId)} disabled={busy}>×</button>
              </span>)}
            </div>
            {building.maxWorkers > building.workers.length && !working && (
              <select className="base-hero-picker" defaultValue="" onChange={event => { void assign(building, event.target.value); event.target.value = ''; }}>
                <option value="">+ Phân công Hero…</option>
                {heroes.filter(hero => !overview.buildings.some(row => row.workers.some(worker => worker.heroInstanceId === hero.id)))
                  .map(hero => <option key={hero.id} value={hero.id}>{hero.name} · Lv.{hero.level}</option>)}
              </select>
            )}
            <div className="plot-actions">
              {building.resourceType && <button type="button" className="primary-button" disabled={busy || working} onClick={() => void collect(building)}>Thu thập</button>}
              {building.level < building.maxLevel && <button type="button" className="secondary-button" disabled={busy || working} onClick={() => void upgrade(building)}>Nâng cấp</button>}
              <button type="button" className="text-button" disabled={busy || working} onClick={() => void demolish(building)}>Phá dỡ</button>
            </div>
          </article>;
        })}
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">CATALOGUE</div><h2>Danh mục công trình</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Công trình</span><span>Loại</span><span>Mở ở</span><span>Chi phí</span><span>Sản lượng gốc</span></div>
        {overview.buildingTypes.map(type => <div className="admin-row" key={type.code}>
          <span>{type.name}<small className="admin-muted">{type.description}</small></span>
          <span>{type.category}</span>
          <span>{type.unlocked ? <em className="admin-badge ok">World Lv.{type.requiredWorldLevel}</em> : <em className="admin-badge">Cần Lv.{type.requiredWorldLevel}</em>}</span>
          <span>{numberFormat.format(type.buildCostSilver)} Xu</span>
          <span>{type.production ? `${type.production.resourceType} · ${type.production.ratePerHour}/h` : '—'}</span>
        </div>)}
      </div>
    </section>
  </>;
}
