import { useCallback, useEffect, useMemo, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type HeroRow = {
  id: string;
  name: string;
  rarity: number;
  level: number;
  state: string;
  heroClass: string;
  category: string;
  derivedStats?: { hp: number; maxHp: number; attack: number; defense: number; speed: number };
};

type ImprintEffects = {
  critRate: number;
  evasion: number;
  accuracy: number;
  atkPercent: number;
  matkPercent: number;
  mpRegenPct: number;
  tenacity: number;
  lowHp: { hpThresholdPct: number; damageBonus: number; tenacity: number } | null;
  revive: { hpPct: number; times: number } | null;
};

type ReportUnit = { id: string; name: string; side: 'HERO' | 'ENEMY'; hp: number; maxHp: number; mp: number; maxMp: number; alive: boolean };
type LogEntry = {
  round: number;
  actorId: string;
  actorName: string;
  targetId: string | null;
  action: string;
  damage: number;
  heal: number;
  crit: boolean;
  blocked: boolean;
  targetHp: number;
  actorMp: number;
};

type Report = {
  winner: 'HERO' | 'ENEMY' | 'DRAW';
  rounds: number;
  log: LogEntry[];
  units: ReportUnit[];
  totalDamage: number;
  seed?: number;
  heroes?: { id: string; name: string; classCode?: string; combatPower: number; imprintEffects: ImprintEffects | null }[];
};

type AdvanceResult = {
  sessionId: string;
  status: string;
  silverReward: number;
  deaths: { heroId: string; name: string; state: string }[];
  report: Report;
};

type SessionRow = { id: string; status: string; createdAt: string; finishedAt: string | null; battleReport: Report | null };

async function call<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const WINNER_LABEL: Record<string, string> = { HERO: 'Phe Hero thắng', ENEMY: 'Phe địch thắng', DRAW: 'Hòa' };
const ACTION_LABEL: Record<string, string> = { BASIC: 'Đánh thường', REVIVE: 'Hồi sinh' };

function actionLabel(entry: LogEntry): string {
  return ACTION_LABEL[entry.action] ?? entry.action.replaceAll('_', ' ');
}

function imprintBadges(effects: ImprintEffects | null | undefined): string[] {
  if (!effects) return [];
  const badges: string[] = [];
  if (effects.critRate > 0) badges.push(`+${effects.critRate}% Crit`);
  if (effects.evasion > 0) badges.push(`+${effects.evasion}% Né`);
  if (effects.accuracy > 0) badges.push(`+${effects.accuracy} Chính xác`);
  if (effects.atkPercent > 0) badges.push(`+${effects.atkPercent}% ATK`);
  if (effects.matkPercent > 0) badges.push(`+${effects.matkPercent}% MATK`);
  if (effects.mpRegenPct > 0) badges.push(`+${effects.mpRegenPct}% MP/lượt`);
  if (effects.tenacity > 0) badges.push(`+${effects.tenacity}% Kháng khống chế`);
  if (effects.lowHp) badges.push(`Dưới ${effects.lowHp.hpThresholdPct}% HP: +${effects.lowHp.damageBonus}% ST`);
  if (effects.revive) badges.push(`Hồi sinh ${effects.revive.times} lần @ ${effects.revive.hpPct}% HP`);
  return badges;
}

export function CombatV2Page({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [heroes, setHeroes] = useState<HeroRow[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [seed, setSeed] = useState('42');
  const [report, setReport] = useState<Report | null>(null);
  const [reward, setReward] = useState<{ silverReward: number; deaths: { name: string; state: string }[] } | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [sessions, setSessions] = useState<SessionRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [showAllRounds, setShowAllRounds] = useState(false);

  const loadHeroes = useCallback(async () => {
    const rows = await call<HeroRow[]>('/api/heroes', token);
    const available = rows.filter(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED');
    setHeroes(available);
    setSelected(current => (current.length > 0
      ? current.filter(id => available.some(hero => hero.id === id))
      : available.slice(0, 3).map(hero => hero.id)));
  }, [token]);

  const loadSessions = useCallback(async () => {
    setSessions(await call<SessionRow[]>('/api/combat/v2/sessions', token));
  }, [token]);

  useEffect(() => {
    void loadHeroes().catch(error => onError((error as Error).message));
    void loadSessions().catch(error => onError((error as Error).message));
  }, [loadHeroes, loadSessions, onError]);

  const toggleHero = (id: string) => {
    setSelected(current => (current.includes(id)
      ? current.filter(value => value !== id)
      : current.length >= 5 ? current : [...current, id]));
  };

  const seedValue = () => (Number.isFinite(Number(seed)) ? Number(seed) : undefined);

  const simulate = async () => {
    setBusy(true);
    onError('');
    try {
      const result = await call<Report>('/api/combat/v2/simulate', token, {
        method: 'POST',
        body: JSON.stringify({ heroIds: selected, seed: seedValue(), maxRounds: 30 }),
      });
      setReport(result);
      setReward(null);
      onNotice(`Mô phỏng xong: ${WINNER_LABEL[result.winner]} sau ${result.rounds} lượt.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const startSession = async () => {
    setBusy(true);
    onError('');
    try {
      const started = await call<{ sessionId: string }>('/api/combat/v2/session/start', token, {
        method: 'POST',
        body: JSON.stringify({ heroIds: selected, seed: seedValue() }),
      });
      setSessionId(started.sessionId);
      setReward(null);
      onNotice('Phiên chiến đấu đã mở. Bấm "Phân giải phiên" để nhận kết quả và phần thưởng.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const advanceSession = async () => {
    if (!sessionId) return;
    setBusy(true);
    onError('');
    try {
      const result = await call<AdvanceResult>(`/api/combat/v2/session/${sessionId}/advance`, token, { method: 'POST' });
      setReport(result.report);
      setReward({ silverReward: result.silverReward, deaths: result.deaths });
      setSessionId(null);
      await loadHeroes();
      await loadSessions();
      onNotice(`Phiên hoàn tất: ${WINNER_LABEL[result.report.winner]}, +${result.silverReward} Xu Bạc.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const replay = async (row: SessionRow) => {
    if (!row.battleReport) return;
    setReport(row.battleReport);
    setReward(null);
    setSessionId(null);
  };

  const visibleLog = useMemo(() => {
    if (!report) return [];
    return showAllRounds ? report.log : report.log.slice(-60);
  }, [report, showAllRounds]);

  const heroEffects = useMemo(
    () => new Map((report?.heroes ?? []).map(hero => [hero.id, hero.imprintEffects])),
    [report],
  );
  const heroPower = useMemo(
    () => new Map((report?.heroes ?? []).map(hero => [hero.id, hero.combatPower])),
    [report],
  );

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">COMBAT V2 · ENGINE TEST</div>
        <h1>Chiến đấu v2</h1>
        <p>Chọn tối đa 5 Hero, mô phỏng hoặc mở phiên thật để nhận Xu Bạc, EXP và ghi nhận thương tích.</p>
      </div>
      <div className="date-chip"><span className="date-icon">⚡</span><span><b>1 hành động / lượt</b><small>Thứ tự theo AGI</small></span></div>
    </div>

    <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">PARTY</div><h2>Đội hình ({selected.length}/5)</h2></div>
        <div className="admin-actions">
          <label className="seed-field">Seed <input value={seed} onChange={event => setSeed(event.target.value)} inputMode="numeric" /></label>
          <button type="button" className="secondary-button" disabled={busy || selected.length === 0} onClick={() => void simulate()}>Mô phỏng</button>
          {sessionId
            ? <button type="button" className="primary-button" disabled={busy} onClick={() => void advanceSession()}>Phân giải phiên</button>
            : <button type="button" className="secondary-button" disabled={busy || selected.length === 0} onClick={() => void startSession()}>Mở phiên</button>}
        </div>
      </div>
      {heroes.length === 0
        ? <div className="empty-state compact-empty"><div className="empty-symbol">♙</div><h2>Chưa có Hero sẵn sàng</h2><p>Hãy triệu hồi hoặc hồi phục Hero trước khi xuất trận.</p></div>
        : <div className="combat-v2-party">{heroes.map(hero => {
          const active = selected.includes(hero.id);
          return <button
            type="button"
            key={hero.id}
            className={`combat-v2-hero ${active ? 'selected' : ''}`}
            onClick={() => toggleHero(hero.id)}
          >
            <span className="combat-v2-stars">{'✦'.repeat(Math.min(hero.rarity, 5))}</span>
            <b>{hero.name}</b>
            <small>{hero.heroClass} · Lv.{hero.level}</small>
            <small>HP {hero.derivedStats?.maxHp ?? hero.derivedStats?.hp ?? '—'} · ATK {hero.derivedStats?.attack ?? '—'}</small>
            {active && <i>ĐÃ CHỌN</i>}
          </button>;
        })}</div>}
    </section>

    {report && <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">BATTLE REPORT</div><h2>{WINNER_LABEL[report.winner]} · {report.rounds} lượt</h2></div>
        <div className="admin-actions">
          <span className="cooldown-label">Tổng sát thương {report.totalDamage.toLocaleString('vi-VN')}{report.seed !== undefined ? ` · seed ${report.seed}` : ''}</span>
          {reward && reward.silverReward > 0 && <span className="cooldown-label">+{reward.silverReward.toLocaleString('vi-VN')} Xu Bạc</span>}
        </div>
      </div>

      {reward && reward.deaths.length > 0 && <div className="prototype-warning">
        Tổn thất: {reward.deaths.map(death => `${death.name} (${death.state})`).join(', ')}.
      </div>}

      <div className="survival-list">
        {report.units.map(unit => {
          const badges = imprintBadges(heroEffects.get(unit.id));
          const power = heroPower.get(unit.id);
          return <article className="survival-row" key={`${unit.side}-${unit.id}`}>
            <div className="survival-id">
              <b>{unit.name} {unit.alive ? '' : '· đã gục'}</b>
              <small>{unit.side === 'HERO' ? 'Hero' : 'Địch'} · HP {unit.hp}/{unit.maxHp} · MP {unit.mp}/{unit.maxMp}{power ? ` · CP ${power}` : ''}</small>
            </div>
            <div className="survival-meter">
              <span>HP {Math.round((unit.hp / Math.max(1, unit.maxHp)) * 100)}%</span>
              <div className={`survival-bar ${unit.alive ? '' : 'fatigue'}`}><i style={{ width: `${Math.max(0, (unit.hp / Math.max(1, unit.maxHp)) * 100)}%` }} /></div>
            </div>
            <div className="combat-v2-badges">{badges.length > 0 ? badges.map(badge => <span key={badge}>{badge}</span>) : <small>{unit.side === 'HERO' ? 'Không có ấn ký kỹ năng' : '—'}</small>}</div>
          </article>;
        })}
      </div>

      <div className="panel-head combat-v2-log-head">
        <div><div className="eyebrow">BATTLE LOG</div><h2>{showAllRounds ? `Toàn bộ ${report.log.length} dòng` : `60 dòng gần nhất / ${report.log.length}`}</h2></div>
        <button type="button" className="text-button" onClick={() => setShowAllRounds(value => !value)}>{showAllRounds ? 'Rút gọn' : 'Xem tất cả'}</button>
      </div>
      <div className="combat-v2-log">
        <table>
          <thead><tr><th>Lượt</th><th>Người đánh</th><th>Hành động</th><th>Mục tiêu</th><th>Sát thương</th><th>Hồi</th><th>HP mục tiêu</th></tr></thead>
          <tbody>
            {visibleLog.map((entry, index) => <tr key={`${entry.round}-${entry.actorId}-${index}`} className={entry.action === 'REVIVE' ? 'revive' : entry.crit ? 'crit' : undefined}>
              <td>{entry.round}</td>
              <td>{entry.actorName}</td>
              <td>{actionLabel(entry)}{entry.crit ? ' · chí mạng' : ''}{entry.blocked ? ' · bị đỡ' : ''}</td>
              <td>{report.units.find(unit => unit.id === entry.targetId)?.name ?? '—'}</td>
              <td>{entry.damage}</td>
              <td>{entry.heal}</td>
              <td>{entry.targetHp}</td>
            </tr>)}
          </tbody>
        </table>
      </div>
    </section>}

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">HISTORY</div><h2>Phiên gần đây</h2></div></div>
      {sessions.length === 0
        ? <p className="base-note">Chưa có phiên nào được lưu.</p>
        : <div className="survival-list">{sessions.map(row => <article className="survival-row" key={row.id}>
          <div className="survival-id"><b>{row.battleReport ? WINNER_LABEL[row.battleReport.winner] : row.status}</b><small>{new Date(row.createdAt).toLocaleString('vi-VN')} · {row.status}</small></div>
          <div className="survival-meter"><span>{row.battleReport ? `${row.battleReport.rounds} lượt · ${row.battleReport.totalDamage.toLocaleString('vi-VN')} sát thương` : 'Không có báo cáo'}</span></div>
          <div className="combat-v2-badges"><button type="button" className="text-button" disabled={!row.battleReport} onClick={() => void replay(row)}>Xem lại</button></div>
        </article>)}</div>}
    </section>
  </>;
}
