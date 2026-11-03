import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type HeroPersonality = {
  heroId: string;
  name: string;
  level: number;
  coreTrait: string;
  socialTrait: string;
  behavioralTrait: string;
  specialTrait: string;
  favoriteFood: string;
  loyaltyScore: number;
  loyaltyState: string;
  combatMultiplier: number;
  disobedienceChance: number;
};

type Relationship = {
  id: string;
  heroAName: string;
  heroBName: string;
  affinityPoints: number;
  tier: string;
  resonanceBonus: number;
};

type PersonalityOverview = {
  heroes: HeroPersonality[];
  relationships: Relationship[];
  summary: { heroes: number; danger: number; devoted: number; averageLoyalty: number };
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

const traitLabel: Record<string, string> = {
  BRAVE: 'Dũng cảm', CAUTIOUS: 'Thận trọng', KIND: 'Nhân hậu', STOIC: 'Điềm tĩnh',
  FRIENDLY: 'Thân thiện', ALOOF: 'Lạnh lùng', PLAYFUL: 'Tinh nghịch',
  AGGRESSIVE: 'Hung hăng', DEFENSIVE: 'Phòng thủ', SUPPORTIVE: 'Hỗ trợ',
  BONDED: 'Gắn kết', LONE_WOLF: 'Sói đơn độc', RESILIENT: 'Bền bỉ',
  STRANGER: 'Xa lạ', ACQUAINTANCE: 'Quen biết', COMRADE: 'Đồng đội', TRUSTED_ALLY: 'Đồng minh tin cậy', RIVAL: 'Đối đầu',
  DEVOTED: 'Tận tụy', NORMAL: 'Bình thường', DANGER: 'Nguy hiểm',
};

export function PersonalityPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [data, setData] = useState<PersonalityOverview | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setData(await call<PersonalityOverview>('/api/personality', token));
  }, [token]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const serveMeal = async (hero: HeroPersonality) => {
    setBusy(true);
    onError('');
    try {
      await call(`/api/personality/heroes/${hero.heroId}/favorite-meal`, token, { method: 'POST' });
      await load();
      onNotice(`${hero.name} rất thích ${hero.favoriteFood}.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  if (!data) return <section className="panel"><div className="empty-state"><p>Đang tải hồ sơ tính cách…</p></div></section>;

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">PERSONALITY · PHASE 1</div>
        <h1>Tính cách & quan hệ</h1>
        <p>Bốn nhóm tính cách, độ trung thành và mạng lưới quan hệ giữa các Hero.</p>
      </div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon violet">♥</span><div><small>Loyalty trung bình</small><b>{data.summary.averageLoyalty}</b><span>{data.summary.heroes} Hero</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">⚠</span><div><small>Nguy hiểm (&lt;20)</small><b>{data.summary.danger}</b><span>30% từ chối ra trận</span></div></div>
      <div className="stat-card"><span className="stat-icon gold">★</span><div><small>Tận tụy (≥80)</small><b>{data.summary.devoted}</b><span>+5% chỉ số chiến đấu</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">⌘</span><div><small>Quan hệ</small><b>{data.relationships.length}</b><span>cặp Hero trong căn cứ</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">PROFILES</div><h2>Hồ sơ từng Hero</h2></div></div>
      <div className="personality-grid">
        {data.heroes.map(hero => <article className="personality-card" key={hero.heroId}>
          <header>
            <div><b>{hero.name}</b><small>Lv.{hero.level}</small></div>
            <em className={`admin-badge ${hero.loyaltyState === 'DANGER' ? 'danger' : hero.loyaltyState === 'DEVOTED' ? 'ok' : 'warn'}`}>{traitLabel[hero.loyaltyState] ?? hero.loyaltyState}</em>
          </header>
          <div className="trait-row">
            <span className="trait-chip">Core · {traitLabel[hero.coreTrait] ?? hero.coreTrait}</span>
            <span className="trait-chip">Social · {traitLabel[hero.socialTrait] ?? hero.socialTrait}</span>
            <span className="trait-chip">Behavior · {traitLabel[hero.behavioralTrait] ?? hero.behavioralTrait}</span>
            <span className="trait-chip">Special · {traitLabel[hero.specialTrait] ?? hero.specialTrait}</span>
          </div>
          <div className="loyalty-line"><span>Loyalty {hero.loyaltyScore}</span><span>×{hero.combatMultiplier.toFixed(2)} chiến đấu</span></div>
          <div className="survival-bar"><i style={{ width: `${hero.loyaltyScore}%` }} /></div>
          <footer>
            <small>Khoái khẩu: {hero.favoriteFood}</small>
            <button type="button" className="text-button" disabled={busy} onClick={() => void serveMeal(hero)}>Dọn món</button>
          </footer>
        </article>)}
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">SOCIAL GRAPH</div><h2>Quan hệ giữa các Hero</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Hero A</span><span>Hero B</span><span>Hảo cảm</span><span>Cấp</span><span>Resonance</span></div>
        {data.relationships.length === 0 && <div className="admin-row"><span>Cần ít nhất hai Hero trong căn cứ.</span></div>}
        {data.relationships.slice(0, 12).map(row => <div className="admin-row" key={row.id}>
          <span>{row.heroAName}</span>
          <span>{row.heroBName}</span>
          <span>{row.affinityPoints}</span>
          <span><em className={`admin-badge ${row.tier === 'COMRADE' || row.tier === 'TRUSTED_ALLY' ? 'ok' : row.tier === 'RIVAL' ? 'danger' : ''}`}>{traitLabel[row.tier] ?? row.tier}</em></span>
          <span>{row.resonanceBonus > 1 ? `+${Math.round((row.resonanceBonus - 1) * 100)}% ATK` : '—'}</span>
        </div>)}
      </div>
    </section>
  </>;
}
