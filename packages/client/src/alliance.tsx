import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type AllianceSummary = {
  id: string;
  name: string;
  tag: string;
  emblemIcon: string;
  motto: string;
  language: string;
  minCombatPower: number;
  leaderMasterId: string;
  memberCount: number;
  maxMembers: number;
  allianceLevel: number;
  noticeBoard: string;
  createdAt: string;
  leaderName: string | null;
  pending: boolean;
  full: boolean;
};

type Member = {
  masterId: string;
  name: string;
  level: number;
  role: string;
  contributionPoints: string;
  joinedAt: string;
  power: number;
};

type JoinRequest = { id: string; masterId: string; name: string; level: number; message: string; createdAt: string };

type Overview = {
  inAlliance: boolean;
  alliance: AllianceSummary | null;
  membership: { masterId: string; role: string; contributionPoints: string; joinedAt: string } | null;
  members: Member[];
  requests: JoinRequest[];
  permissions: { canManage: boolean; canUpgradeTech: boolean; canDeclareWar: boolean };
  cooldown: { expiresAt: string; reason: string } | null;
  pendingRequest: { id: string; allianceId: string; allianceName: string | null; createdAt: string } | null;
};

type SearchResult = { alliances: AllianceSummary[]; myAllianceId: string | null; pendingCount: number };

type ChatMessage = {
  id: string;
  masterId: string;
  name: string;
  messageType: string;
  body: string;
  coordinates: { x: number; y: number } | null;
  createdAt: string;
};

type War = {
  id: string;
  declaringAllianceId: string;
  targetAllianceId: string;
  status: string;
  declaringPoints: number;
  targetPoints: number;
  winnerAllianceId: string | null;
  endsAt: string;
  secondsRemaining: number;
  viewerSide: string | null;
  opponent: { id: string; name: string; tag: string } | null;
};

type Conquest = {
  season: {
    id: string;
    seasonNumber: number;
    status: string;
    startTime: string;
    endTime: string;
    conqueringAllianceId: string | null;
    concludedAt: string | null;
    contestOpen: boolean;
    contestOpensAt: string;
    daysRemaining: number;
  };
  wonder: {
    holder: { id: string; name: string; tag: string } | null;
    secondsHeld: number;
    requiredSeconds: number;
    remainingSeconds: number;
    percent: number;
    complete: boolean;
    contestOpen: boolean;
    contestOpensAt: string;
    defencePower: number;
  };
  ranking: { allianceId: string; name: string; tag: string; points: number; rank: number; finalRank: number | null }[];
  myAlliance: {
    id: string; name: string; tag: string; role: string; points: number; rank: number | null;
    canDeclareWar: boolean; canSiege: boolean;
  } | null;
  wars: War[];
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
const countdown = (seconds: number) => {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
};

export function AlliancePage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [tab, setTab] = useState('overview');
  const [overview, setOverview] = useState<Overview | null>(null);
  const [listing, setListing] = useState<SearchResult>({ alliances: [], myAllianceId: null, pendingCount: 0 });
  const [chat, setChat] = useState<ChatMessage[]>([]);
  const [conquest, setConquest] = useState<Conquest | null>(null);
  const [busy, setBusy] = useState(false);

  const [name, setName] = useState('');
  const [tag, setTag] = useState('');
  const [motto, setMotto] = useState('');
  const [notice, setNotice] = useState('');
  const [chatBody, setChatBody] = useState('');
  const [pingX, setPingX] = useState('');
  const [pingY, setPingY] = useState('');
  const [targetAllianceId, setTargetAllianceId] = useState('');
  const [query, setQuery] = useState('');

  const load = useCallback(async () => {
    const [my, found, messages, war] = await Promise.all([
      call<Overview>('/api/alliance', token),
      call<SearchResult>('/api/alliance/search', token),
      call<ChatMessage[]>('/api/alliance/chat', token).catch(() => []),
      call<Conquest>('/api/world/conquest', token).catch(() => null),
    ]);
    setOverview(my);
    setListing(found);
    setChat(messages);
    setConquest(war);
    setNotice(my.alliance?.noticeBoard ?? '');
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

  const search = (filters: { query?: string }) => {
    const params = new URLSearchParams();
    if (filters.query) params.set('query', filters.query);
    void run(() => call(`/api/alliance/search?${params.toString()}`, token), 'Đã lọc danh sách liên minh.');
  };

  if (!overview) return <section className="panel"><div className="empty-state"><p>Đang tải liên minh…</p></div></section>;

  const role = overview.membership?.role;
  const isLeader = role === 'LEADER';
  const isOfficer = role === 'OFFICER' || isLeader;

  if (!overview.inAlliance) {
    return <>
      <div className="page-heading">
        <div>
          <div className="eyebrow">ALLIANCE · PHASE 3</div>
          <h1>Liên minh</h1>
          <p>Thành lập hoặc gia nhập một liên minh để cùng chiếm lãnh thổ và tranh đoạt Kỳ Quan Trung Tâm.</p>
        </div>
      </div>

      {overview.cooldown && <section className="panel">
        <div className="empty-state compact-empty">
          <span className="empty-symbol">⏳</span>
          <h3>Đang trong thời gian chờ</h3>
          <p>Bạn đã rời liên minh gần đây. Có thể gia nhập lại từ {when(overview.cooldown.expiresAt)} (UTC+7).</p>
        </div>
      </section>}

      {overview.pendingRequest && <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">PENDING</div><h2>Yêu cầu đang chờ duyệt</h2></div>
          <button type="button" className="secondary-button" disabled={busy}
            onClick={() => void run(() => call(`/api/alliance/requests/${overview.pendingRequest!.id}/cancel`, token, { method: 'POST' }), 'Đã rút yêu cầu.')}>
            Rút yêu cầu
          </button>
        </div>
        <p>Liên minh <b>{overview.pendingRequest.allianceName ?? overview.pendingRequest.allianceId}</b> chưa phản hồi yêu cầu của bạn.</p>
      </section>}

      <div className="dashboard-grid">
        <section className="panel">
          <div className="panel-head"><div><div className="eyebrow">FOUND</div><h2>Thành lập liên minh</h2></div></div>
          <p className="base-note">Cần Master Cấp 20. Phí thành lập: 5.000 Ngọc hoặc 500.000 Xu Bạc (ưu tiên Ngọc).</p>
          <label className="admin-field">Tên liên minh<input maxLength={20} value={name} onChange={event => setName(event.target.value)} placeholder="3–20 ký tự" /></label>
          <label className="admin-field">Tag<input maxLength={5} value={tag} onChange={event => setTag(event.target.value.toUpperCase())} placeholder="2–5 chữ/số" /></label>
          <label className="admin-field">Khẩu hiệu<input maxLength={120} value={motto} onChange={event => setMotto(event.target.value)} placeholder="Không bắt buộc" /></label>
          <button type="button" className="primary-button" disabled={busy || name.trim().length < 3 || tag.trim().length < 2}
            onClick={() => void run(() => call('/api/alliance', token, {
              method: 'POST', body: JSON.stringify({ name, tag, motto }),
            }), 'Đã thành lập liên minh.')}>
            Thành lập
          </button>
        </section>

        <section className="panel">
          <div className="panel-head">
            <div><div className="eyebrow">BROWSE</div><h2>Tìm liên minh</h2></div>
            <div className="admin-actions">
              <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Tên hoặc tag" />
              <button type="button" className="secondary-button" disabled={busy} onClick={() => search({ query })}>Tìm</button>
            </div>
          </div>
          <div className="admin-table">
            <div className="admin-row admin-row-head"><span>Liên minh</span><span>Thành viên</span><span>Cấp</span><span>Lực chiến</span><span /></div>
            {listing.alliances.length === 0 && <div className="admin-row"><span>Chưa có liên minh nào.</span></div>}
            {listing.alliances.map(guild => <div className="admin-row" key={guild.id}>
              <span><b>{guild.emblemIcon} [{guild.tag}] {guild.name}</b><small className="admin-muted">{guild.motto || 'Không khẩu hiệu'}</small></span>
              <span>{guild.memberCount}/{guild.maxMembers}</span>
              <span>{guild.allianceLevel}</span>
              <span>{numberFormat.format(guild.minCombatPower)}</span>
              <span>
                {guild.pending
                  ? <em className="admin-badge warn">Đang chờ</em>
                  : <button type="button" className="text-button" disabled={busy || guild.full || Boolean(overview.cooldown)}
                    onClick={() => void run(() => call('/api/alliance/join', token, {
                      method: 'POST', body: JSON.stringify({ allianceId: guild.id }),
                    }), `Đã gửi yêu cầu vào ${guild.name}.`)}>
                    {guild.full ? 'Đầy' : 'Xin vào'}
                  </button>}
              </span>
            </div>)}
          </div>
        </section>
      </div>
    </>;
  }

  const alliance = overview.alliance!;
  const ownPower = overview.members.reduce((total, member) => total + member.power, 0);

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">ALLIANCE · PHASE 3</div>
        <h1>{alliance.emblemIcon} [{alliance.tag}] {alliance.name}</h1>
        <p>{alliance.motto || 'Chưa có khẩu hiệu'} · {alliance.memberCount}/{alliance.maxMembers} thành viên · cấp {alliance.allianceLevel}</p>
      </div>
      <div className="date-chip"><span className="date-icon">⚑</span><span><b>Vai trò</b><small>{role}</small></span></div>
    </div>

    <div className="admin-tabs">
      <button type="button" className={`admin-tab ${tab === 'overview' ? 'active' : ''}`} onClick={() => setTab('overview')}>Tổng quan</button>
      <button type="button" className={`admin-tab ${tab === 'members' ? 'active' : ''}`} onClick={() => setTab('members')}>
        Thành viên{overview.requests.length > 0 ? ` (${overview.requests.length})` : ''}
      </button>
      <button type="button" className={`admin-tab ${tab === 'chat' ? 'active' : ''}`} onClick={() => setTab('chat')}>Trò chuyện</button>
      <button type="button" className={`admin-tab ${tab === 'war' ? 'active' : ''}`} onClick={() => setTab('war')}>Chiến tranh</button>
    </div>

    {tab === 'overview' && <>
      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">NOTICE BOARD</div><h2>Bảng thông báo</h2></div>
          {isLeader && <button type="button" className="secondary-button" disabled={busy}
            onClick={() => void run(() => call('/api/alliance/notice', token, {
              method: 'PATCH', body: JSON.stringify({ noticeBoard: notice }),
            }), 'Đã cập nhật bảng thông báo.')}>Lưu</button>}
        </div>
        {isOfficer
          ? <label className="admin-field">Nội dung
            <textarea maxLength={500} rows={3} value={notice} onChange={event => setNotice(event.target.value)} />
          </label>
          : <p>{alliance.noticeBoard || 'Chưa có thông báo.'}</p>}
        <div className="stat-grid">
          <div className="stat-card"><small>Tổng lực chiến</small><b>{numberFormat.format(ownPower)}</b></div>
          <div className="stat-card"><small>Cấp liên minh</small><b>{alliance.allianceLevel}</b></div>
          <div className="stat-card"><small>Thành viên</small><b>{alliance.memberCount}/{alliance.maxMembers}</b></div>
          <div className="stat-card"><small>Điểm chinh phục</small><b>{numberFormat.format(conquest?.myAlliance?.points ?? 0)}</b></div>
        </div>
        <div className="admin-actions">
          {overview.permissions.canUpgradeTech && <button type="button" className="primary-button" disabled={busy || alliance.maxMembers >= 100}
            onClick={() => void run(() => call('/api/alliance/tech/upgrade', token, { method: 'POST' }), 'Đã nâng cấp công nghệ liên minh.')}>
            Nâng cấp Alliance Tech
          </button>}
          <button type="button" className="secondary-button" disabled={busy}
            onClick={() => void run(() => call('/api/alliance/leave', token, { method: 'POST' }), 'Đã rời liên minh.')}>
            Rời liên minh
          </button>
          {isLeader && <button type="button" className="secondary-button danger" disabled={busy}
            onClick={() => void run(() => call('/api/alliance', token, { method: 'DELETE' }), 'Đã giải tán liên minh.')}>
            Giải tán
          </button>}
        </div>
      </section>

      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">MISSION</div><h2>Chiến dịch hiện tại</h2></div></div>
        {conquest
          ? <p>Mùa <b>#{conquest.season.seasonNumber}</b> · còn {conquest.season.daysRemaining} ngày · Kỳ Quan {conquest.wonder.holder ? `do [${conquest.wonder.holder.tag}] nắm giữ` : 'chưa có chủ'}.</p>
          : <p>Chưa có thông tin mùa giải.</p>}
      </section>
    </>}

    {tab === 'members' && <>
      {isOfficer && <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">REQUESTS</div><h2>Yêu cầu gia nhập</h2></div></div>
        <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Ứng viên</span><span>Cấp</span><span>Lời nhắn</span><span>Thời điểm</span><span /></div>
          {overview.requests.length === 0 && <div className="admin-row"><span>Không có yêu cầu nào.</span></div>}
          {overview.requests.map(request => <div className="admin-row" key={request.id}>
            <span>{request.name}</span>
            <span>{request.level}</span>
            <span>{request.message || '—'}</span>
            <span>{when(request.createdAt)}</span>
            <span className="admin-actions">
              <button type="button" className="text-button" disabled={busy}
                onClick={() => void run(() => call(`/api/alliance/requests/${request.id}/approve`, token, { method: 'POST' }), 'Đã duyệt thành viên.')}>Duyệt</button>
              <button type="button" className="text-button" disabled={busy}
                onClick={() => void run(() => call(`/api/alliance/requests/${request.id}/reject`, token, { method: 'POST' }), 'Đã từ chối yêu cầu.')}>Từ chối</button>
            </span>
          </div>)}
        </div>
      </section>}

      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">ROSTER</div><h2>Thành viên</h2></div>
          <small className="admin-muted">Lực chiến tính trên 5 Hero mạnh nhất mỗi người.</small>
        </div>
        <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Master</span><span>Vai trò</span><span>Lực chiến</span><span>Gia nhập</span><span>Hành động</span></div>
          {overview.members.map(member => {
            const targetRank = member.role === 'LEADER' ? 3 : member.role === 'OFFICER' ? 2 : 1;
            const actorRank = isLeader ? 3 : isOfficer ? 2 : 1;
            const canKick = targetRank < actorRank;
            const canPromote = isLeader && member.role === 'MEMBER';
            const canDemote = isLeader && member.role === 'OFFICER';
            const canTransfer = isLeader && member.role !== 'LEADER';
            return <div className="admin-row" key={member.masterId}>
              <span>{member.name}<small className="admin-muted">Lv.{member.level}</small></span>
              <span><em className={`admin-badge ${member.role === 'LEADER' ? 'ok' : member.role === 'OFFICER' ? 'warn' : ''}`}>{member.role}</em></span>
              <span>{numberFormat.format(member.power)}</span>
              <span>{when(member.joinedAt)}</span>
              <span className="admin-actions">
                {canPromote && <button type="button" className="text-button" disabled={busy}
                  onClick={() => void run(() => call(`/api/alliance/members/${member.masterId}/manage`, token, {
                    method: 'POST', body: JSON.stringify({ action: 'PROMOTE' }),
                  }), 'Đã thăng chức.')}>Thăng</button>}
                {canDemote && <button type="button" className="text-button" disabled={busy}
                  onClick={() => void run(() => call(`/api/alliance/members/${member.masterId}/manage`, token, {
                    method: 'POST', body: JSON.stringify({ action: 'DEMOTE' }),
                  }), 'Đã giáng chức.')}>Giáng</button>}
                {canTransfer && <button type="button" className="text-button" disabled={busy}
                  onClick={() => void run(() => call(`/api/alliance/members/${member.masterId}/manage`, token, {
                    method: 'POST', body: JSON.stringify({ action: 'TRANSFER' }),
                  }), 'Đã chuyển chức Chủ bang.')}>Chuyển bang chủ</button>}
                {canKick && <button type="button" className="text-button danger" disabled={busy}
                  onClick={() => void run(() => call(`/api/alliance/members/${member.masterId}/manage`, token, {
                    method: 'POST', body: JSON.stringify({ action: 'KICK' }),
                  }), 'Đã trục xuất thành viên.')}>Trục xuất</button>}
              </span>
            </div>;
          })}
        </div>
      </section>
    </>}

    {tab === 'chat' && <>
      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">COMMS</div><h2>Kênh liên minh</h2></div>
          <button type="button" className="secondary-button" onClick={() => void load().catch(error => onError((error as Error).message))}>Làm mới</button>
        </div>
        <div className="chat-list">
          {chat.length === 0 && <p className="admin-muted">Chưa có tin nhắn.</p>}
          {chat.map(message => <div className="chat-row" key={message.id}>
            <b>{message.name}</b>
            <span>{message.body || '📍 đánh dấu bản đồ'}</span>
            {message.coordinates && <em className="admin-badge warn">({message.coordinates.x}, {message.coordinates.y})</em>}
            <small className="admin-muted">{when(message.createdAt)}</small>
          </div>)}
        </div>
        <label className="admin-field">Tin nhắn<input maxLength={300} value={chatBody} onChange={event => setChatBody(event.target.value)} placeholder="Tối đa 300 ký tự" /></label>
        <div className="admin-actions">
          <input className="coord-input" value={pingX} onChange={event => setPingX(event.target.value)} placeholder="X" />
          <input className="coord-input" value={pingY} onChange={event => setPingY(event.target.value)} placeholder="Y" />
          <button type="button" className="primary-button" disabled={busy || (chatBody.trim().length === 0 && (!pingX || !pingY))}
            onClick={() => void run(() => {
              const coordinates = pingX !== '' && pingY !== '' ? { x: Number(pingX), y: Number(pingY) } : undefined;
              return call('/api/alliance/chat', token, {
                method: 'POST', body: JSON.stringify({ body: chatBody, coordinates }),
              });
            }, 'Đã gửi tin nhắn.').then(() => { setChatBody(''); setPingX(''); setPingY(''); })}>
            Gửi
          </button>
        </div>
      </section>
    </>}

    {tab === 'war' && <>
      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">WORLD CONQUEST · SEASON</div><h2>Mùa chinh phục #{conquest?.season.seasonNumber ?? '—'}</h2></div>
          {conquest && <span className={`admin-badge ${conquest.season.contestOpen ? 'ok' : 'warn'}`}>
            {conquest.season.status === 'ACTIVE' ? `còn ${conquest.season.daysRemaining} ngày` : 'đã kết thúc'}
          </span>}
        </div>
        {conquest
          ? <>
            <p>Kỳ Quan Trung Tâm mở tranh đoạt từ {when(conquest.wonder.contestOpensAt)}. Giữ liên tục 8 giờ để trở thành Bá Chủ Thế Giới.</p>
            <div className="progress-track"><div className="progress-fill" style={{ width: `${Math.min(100, conquest.wonder.percent)}%` }} /></div>
            <p>
              Chủ hiện tại: <b>{conquest.wonder.holder ? `[${conquest.wonder.holder.tag}] ${conquest.wonder.holder.name}` : 'chưa có'}</b>
              {' · '}{Math.floor(conquest.wonder.secondsHeld / 3600)}h / 8h
              {' · '}phòng thủ {numberFormat.format(conquest.wonder.defencePower)}
            </p>
            <div className="admin-actions">
              <button type="button" className="primary-button"
                disabled={busy || !conquest.wonder.contestOpen || !conquest.myAlliance?.canSiege || conquest.wonder.holder?.id === alliance.id}
                onClick={() => void run(() => call('/api/world/conquest/wonder/siege', token, { method: 'POST' }), 'Đã mở cuộc công thành Kỳ Quan.')}>
                Công thành Kỳ Quan
              </button>
              <small className="admin-muted">
                {!conquest.wonder.contestOpen ? 'Chưa tới 3 ngày cuối mùa giải.' : 'Cần vai trò Chủ bang hoặc Cán sự.'}
              </small>
            </div>
          </>
          : <p className="admin-muted">Chưa tải được thông tin mùa giải.</p>}
      </section>

      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">WARS</div><h2>Chiến dịch 24 giờ</h2></div>
          <div className="admin-actions">
            <select value={targetAllianceId} onChange={event => setTargetAllianceId(event.target.value)}>
              <option value="">Chọn liên minh đối thủ</option>
              {listing.alliances.filter(guild => guild.id !== alliance.id).map(guild => <option key={guild.id} value={guild.id}>[{guild.tag}] {guild.name}</option>)}
            </select>
            <button type="button" className="primary-button" disabled={busy || !isLeader || !targetAllianceId}
              onClick={() => void run(() => call('/api/alliance/wars', token, {
                method: 'POST', body: JSON.stringify({ targetAllianceId }),
              }), 'Đã tuyên chiến.')}>
              Tuyên chiến
            </button>
          </div>
        </div>
        <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Đối thủ</span><span>Điểm</span><span>Trạng thái</span><span>Còn lại</span><span>Kết quả</span></div>
          {(conquest?.wars ?? []).length === 0 && <div className="admin-row"><span>Chưa có cuộc chiến nào.</span></div>}
          {(conquest?.wars ?? []).map(war => <div className="admin-row" key={war.id}>
            <span>{war.opponent ? `[${war.opponent.tag}] ${war.opponent.name}` : '—'}</span>
            <span>{war.viewerSide === 'DECLARING'
              ? `${war.declaringPoints} – ${war.targetPoints}`
              : `${war.targetPoints} – ${war.declaringPoints}`}</span>
            <span><em className={`admin-badge ${war.status === 'ACTIVE' ? 'warn' : 'ok'}`}>{war.status}</em></span>
            <span>{war.status === 'ACTIVE' ? countdown(war.secondsRemaining) : '—'}</span>
            <span>{war.winnerAllianceId ? (war.winnerAllianceId === alliance.id ? 'Thắng' : 'Thua') : (war.status === 'RESOLVED' ? 'Hòa' : '—')}</span>
          </div>)}
        </div>
      </section>

      <section className="panel">
        <div className="panel-head"><div><div className="eyebrow">RANKING</div><h2>Xếp hạng chinh phục</h2></div></div>
        <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Hạng</span><span>Liên minh</span><span>Điểm</span><span>Chung cuộc</span></div>
          {(conquest?.ranking ?? []).length === 0 && <div className="admin-row"><span>Chưa có liên minh nào ghi điểm.</span></div>}
          {(conquest?.ranking ?? []).map(entry => <div className="admin-row" key={entry.allianceId}>
            <span>#{entry.rank}</span>
            <span>[{entry.tag}] {entry.name}{entry.allianceId === alliance.id ? ' · bạn' : ''}</span>
            <span>{numberFormat.format(entry.points)}</span>
            <span>{entry.finalRank ?? '—'}</span>
          </div>)}
        </div>
      </section>
    </>}
  </>;
}
