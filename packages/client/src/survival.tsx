import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type SurvivalHero = {
  heroId: string;
  name: string;
  level: number;
  heroState: string;
  hungerScore: number;
  fatigueScore: number;
  hungerState: string;
  fatigueState: string;
  isResting: boolean;
  assignedBuildingId: string | null;
  attackMultiplier: number;
};

type SurvivalOverview = {
  heroes: SurvivalHero[];
  food: { stock: number; capacity: number; itemId: string };
  summary: { starving: number; exhausted: number; resting: number };
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

const HUNGER_LABEL: Record<string, string> = {
  FULL: 'No', SATISFIED: 'Đủ', HUNGRY: 'Đói', STARVING: 'Đói nặng', CRITICAL: 'Kiệt sức',
};
const FATIGUE_LABEL: Record<string, string> = {
  RESTED: 'Sung sức', NORMAL: 'Bình thường', TIRED: 'Mệt', EXHAUSTED: 'Kiệt sức', CRITICAL: 'Nguy kịch', OVEREXHAUSTED: 'Quá sức',
};

export function SurvivalPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [data, setData] = useState<SurvivalOverview | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setData(await call<SurvivalOverview>('/api/survival', token));
  }, [token]);

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

  const feed = (heroId: string) => run(
    () => call(`/api/survival/heroes/${heroId}/feed`, token, { method: 'POST', body: JSON.stringify({ quantity: 1 }) }),
    'Đã cho Hero ăn.',
  );

  const toggleRest = (hero: SurvivalHero) => run(
    () => call(`/api/survival/heroes/${hero.heroId}/rest`, token, { method: hero.isResting ? 'DELETE' : 'POST' }),
    hero.isResting ? 'Đã đánh thức Hero.' : 'Hero đang nghỉ ngơi.',
  );

  const cook = (quantity: number) => run(
    () => call('/api/survival/kitchen/cook', token, { method: 'POST', body: JSON.stringify({ quantity }) }),
    'Nhà bếp đã chế biến lương thực.',
  );

  if (!data) return <section className="panel"><div className="empty-state"><p>Đang tải dữ liệu sinh tồn…</p></div></section>;

  const foodPercent = data.food.capacity > 0 ? Math.min(100, (data.food.stock / data.food.capacity) * 100) : 0;

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">SURVIVAL · PHASE 1</div>
        <h1>Sinh tồn của Hero</h1>
        <p>Theo dõi đói và mệt, cho ăn, cho nghỉ và giữ kho lương thực đủ cho các chuyến thám hiểm.</p>
      </div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon gold">▤</span><div><small>Lương khô</small><b>{data.food.stock} / {data.food.capacity}</b><span>{foodPercent.toFixed(0)}% sức chứa</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">☹</span><div><small>Đang đói nặng</small><b>{data.summary.starving}</b><span>giảm 40% ATK/DEF</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">☾</span><div><small>Đang nghỉ</small><b>{data.summary.resting}</b><span>hồi 15 điểm/giờ</span></div></div>
      <div className="stat-card"><span className="stat-icon violet">⚡</span><div><small>Quá sức</small><b>{data.summary.exhausted}</b><span>không thể xuất trận</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">FOOD SUPPLY</div><h2>Kho lương thực</h2></div>
        <div className="admin-actions">
          <button type="button" className="secondary-button" disabled={busy} onClick={() => void cook(1)}>Nấu 1 phần</button>
          <button type="button" className="secondary-button" disabled={busy} onClick={() => void cook(10)}>Nấu 10 phần</button>
        </div>
      </div>
      <div className="survival-bar"><i style={{ width: `${foodPercent}%` }} /></div>
      <p className="base-note">Mỗi phần ăn cần 2 lương thực thô (FOOD_RAW) từ Nông trại. Dung lượng tăng theo cấp Nhà bếp.</p>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">ROSTER</div><h2>Tình trạng từng Hero</h2></div></div>
      <div className="survival-list">
        {data.heroes.length === 0 && <div className="empty-state"><p>Chưa có Hero nào.</p></div>}
        {data.heroes.map(hero => <article className="survival-row" key={hero.heroId}>
          <div className="survival-id">
            <b>{hero.name}</b>
            <small>Lv.{hero.level} · {hero.heroState}{hero.assignedBuildingId ? ' · đang làm việc' : ''}</small>
          </div>
          <div className="survival-meter">
            <span>Đói {Math.round(hero.hungerScore)} · {HUNGER_LABEL[hero.hungerState] ?? hero.hungerState}</span>
            <div className="survival-bar hunger"><i style={{ width: `${hero.hungerScore}%` }} /></div>
          </div>
          <div className="survival-meter">
            <span>Mệt {Math.round(hero.fatigueScore)} · {FATIGUE_LABEL[hero.fatigueState] ?? hero.fatigueState}</span>
            <div className="survival-bar fatigue"><i style={{ width: `${hero.fatigueScore}%` }} /></div>
          </div>
          <div className="survival-actions">
            <button type="button" className="secondary-button" disabled={busy || data.food.stock < 1} onClick={() => void feed(hero.heroId)}>Cho ăn</button>
            <button type="button" className="text-button" disabled={busy} onClick={() => void toggleRest(hero)}>{hero.isResting ? 'Đánh thức' : 'Cho nghỉ'}</button>
          </div>
        </article>)}
      </div>
    </section>
  </>;
}
