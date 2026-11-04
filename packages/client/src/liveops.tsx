import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Mission = {
  id: string;
  code: string;
  name: string;
  objectiveType: string;
  targetCount: number;
  progress: number;
  status: string;
  canClaim: boolean;
  reward: { silver?: number; gems?: number; items?: { itemId: string; quantity: number }[] };
};

type LiveEvent = {
  id: string;
  code: string;
  name: string;
  description: string;
  eventType: string;
  phase: string;
  startAt: string;
  endAt: string;
  claimDeadline: string;
  missions: Mission[];
};

type Entry = { rank: number; masterName: string; floor: number; rounds: number; combatPower: number; score: number };
type Board = { board: string; entries: Entry[]; viewer: Entry | null; totalPlayers: number; season: { periodKey: string } | null };

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

const objectiveLabel: Record<string, string> = {
  WIN_BATTLE: 'thắng trận', CLEAR_FLOOR: 'vượt tầng', CRAFT_ITEM: 'chế tạo',
  SPEND_SILVER: 'Xu chi tiêu', COLLECT_RESOURCE: 'tài nguyên thu thập',
};

export function LiveOpsPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [tab, setTab] = useState('events');
  const [events, setEvents] = useState<LiveEvent[]>([]);
  const [board, setBoard] = useState('DUNGEON_PROGRESS');
  const [boardData, setBoardData] = useState<Board | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [eventRows, boardRow] = await Promise.all([
      call<LiveEvent[]>('/api/events', token),
      call<Board>(`/api/leaderboards?board=${board}`, token),
    ]);
    setEvents(eventRows);
    setBoardData(boardRow);
  }, [token, board]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const claim = async (mission: Mission) => {
    setBusy(true);
    onError('');
    try {
      await call(`/api/events/missions/${mission.id}/claim`, token, { method: 'POST' });
      await load();
      onNotice(`Đã nhận thưởng: ${mission.name}`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const rewardLabel = (reward: Mission['reward']) => {
    const parts: string[] = [];
    if (reward.silver) parts.push(`${numberFormat.format(reward.silver)} Xu`);
    if (reward.gems) parts.push(`${reward.gems} Ngọc`);
    for (const item of reward.items ?? []) parts.push(`${item.quantity} × ${item.itemId}`);
    return parts.join(' · ') || '—';
  };

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">LIVEOPS · PHASE 2</div>
        <h1>Sự kiện & Bảng xếp hạng</h1>
        <p>Nhiệm vụ sự kiện có thời hạn và hai bảng xếp hạng PvE: tiến độ Dungeon và tổng lực chiến.</p>
      </div>
    </div>

    <div className="admin-tabs">
      <button type="button" className={`admin-tab ${tab === 'events' ? 'active' : ''}`} onClick={() => setTab('events')}>Sự kiện</button>
      <button type="button" className={`admin-tab ${tab === 'board' ? 'active' : ''}`} onClick={() => setTab('board')}>Bảng xếp hạng</button>
    </div>

    {tab === 'events' && (events.length === 0
      ? <section className="panel"><div className="empty-state"><p>Không có sự kiện nào đang diễn ra.</p></div></section>
      : events.map(event => <section className="panel" key={event.id}>
        <div className="panel-head">
          <div><div className="eyebrow">{event.eventType} · {event.phase}</div><h2>{event.name}</h2></div>
          <span className="sample-tag">Kết thúc {when(event.endAt)}</span>
        </div>
        <p className="base-note">{event.description} · Nhận thưởng tới {when(event.claimDeadline)}</p>
        <div className="quest-list">
          {event.missions.map(mission => {
            const percent = Math.min(100, Math.round((mission.progress / Math.max(1, mission.targetCount)) * 100));
            return <article className="quest-row" key={mission.id}>
              <div className="quest-main"><b>{mission.name}</b><small>Tiến độ {objectiveLabel[mission.objectiveType] ?? mission.objectiveType}</small></div>
              <div className="quest-meter">
                <span>{mission.progress} / {mission.targetCount}</span>
                <div className="survival-bar"><i style={{ width: `${percent}%` }} /></div>
              </div>
              <div className="quest-reward">{rewardLabel(mission.reward)}</div>
              <div className="quest-action">
                {mission.status === 'CLAIMED'
                  ? <em className="admin-badge ok">Đã nhận</em>
                  : mission.canClaim
                    ? <button type="button" className="secondary-button" disabled={busy} onClick={() => void claim(mission)}>Nhận thưởng</button>
                    : <em className="admin-badge">Đang làm</em>}
              </div>
            </article>;
          })}
        </div>
      </section>))}

    {tab === 'board' && <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">LEADERBOARD</div><h2>{board === 'COMBAT_POWER' ? 'Tổng lực chiến' : 'Tiến độ Dungeon'}</h2></div>
        <div className="admin-actions">
          <select value={board} onChange={event => setBoard(event.target.value)}>
            <option value="DUNGEON_PROGRESS">Tiến độ Dungeon</option>
            <option value="COMBAT_POWER">Tổng lực chiến</option>
          </select>
          <button type="button" className="secondary-button" onClick={() => void load().catch(error => onError((error as Error).message))}>Làm mới</button>
        </div>
      </div>
      {boardData?.viewer && <p className="base-note">Hạng của bạn: #{boardData.viewer.rank} · {board === 'COMBAT_POWER' ? `${numberFormat.format(boardData.viewer.combatPower)} CP` : `tầng ${boardData.viewer.floor}`} · tổng {boardData.totalPlayers} người chơi</p>}
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Hạng</span><span>Master</span><span>{board === 'COMBAT_POWER' ? 'Lực chiến' : 'Tầng'}</span><span>{board === 'COMBAT_POWER' ? 'Hero tối đa 5' : 'Số vòng'}</span><span>Điểm</span></div>
        {(boardData?.entries ?? []).length === 0 && <div className="admin-row"><span>Chưa có dữ liệu xếp hạng.</span></div>}
        {(boardData?.entries ?? []).map(entry => <div className="admin-row" key={`${entry.rank}-${entry.masterName}`}>
          <span><b>#{entry.rank}</b></span>
          <span>{entry.masterName}</span>
          <span>{board === 'COMBAT_POWER' ? numberFormat.format(entry.combatPower) : entry.floor}</span>
          <span>{board === 'COMBAT_POWER' ? '—' : entry.rounds}</span>
          <span>{numberFormat.format(entry.score)}</span>
        </div>)}
      </div>
    </section>}
  </>;
}
