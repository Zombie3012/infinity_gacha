import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Ticket = {
  id: string;
  subject: string;
  body: string;
  category: string;
  status: string;
  createdAt: string;
  messages: { id: string; authorType: string; body: string; createdAt: string }[];
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

const when = (value: string) => new Date(value).toLocaleString('vi-VN');

export function SupportPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [replyFor, setReplyFor] = useState<string | null>(null);
  const [reply, setReply] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setTickets(await call<Ticket[]>('/api/support/tickets', token));
  }, [token]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const create = async () => {
    setBusy(true);
    onError('');
    try {
      await call('/api/support/tickets', token, { method: 'POST', body: JSON.stringify({ subject, body }) });
      setSubject('');
      setBody('');
      await load();
      onNotice('Đã gửi yêu cầu hỗ trợ.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const sendReply = async (ticketId: string) => {
    setBusy(true);
    onError('');
    try {
      await call(`/api/support/tickets/${ticketId}/messages`, token, { method: 'POST', body: JSON.stringify({ body: reply }) });
      setReply('');
      setReplyFor(null);
      await load();
      onNotice('Đã gửi phản hồi.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">SUPPORT · PHASE 2</div>
        <h1>Hỗ trợ</h1>
        <p>Gửi yêu cầu tới vận hành viên và theo dõi phản hồi.</p>
      </div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">NEW TICKET</div><h2>Tạo yêu cầu</h2></div></div>
      <div className="admin-grid">
        <label className="admin-field">Tiêu đề
          <input value={subject} maxLength={150} onChange={event => setSubject(event.target.value)} />
        </label>
      </div>
      <label className="admin-field">Nội dung
        <textarea rows={4} value={body} onChange={event => setBody(event.target.value)} />
      </label>
      <div className="admin-actions">
        <button type="button" className="primary-button" disabled={busy || subject.length < 3 || body.length < 10} onClick={() => void create()}>Gửi yêu cầu</button>
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">HISTORY</div><h2>Yêu cầu của bạn</h2></div></div>
      {tickets.length === 0 && <p className="base-note">Chưa có yêu cầu nào.</p>}
      <div className="ticket-list">
        {tickets.map(ticket => <article className="ticket-card" key={ticket.id}>
          <header>
            <b>{ticket.subject}</b>
            <em className={`admin-badge ${ticket.status === 'CLOSED' ? '' : ticket.status === 'RESOLVED' ? 'ok' : 'warn'}`}>{ticket.status}</em>
          </header>
          <small>{when(ticket.createdAt)}</small>
          <div className="ticket-messages">
            {ticket.messages.map(message => <p key={message.id} className={message.authorType === 'OPERATOR' ? 'operator' : 'player'}>
              <b>{message.authorType === 'OPERATOR' ? 'Hỗ trợ' : 'Bạn'}:</b> {message.body}
            </p>)}
          </div>
          {ticket.status !== 'CLOSED' && (replyFor === ticket.id
            ? <div className="admin-actions">
              <input value={reply} onChange={event => setReply(event.target.value)} placeholder="Phản hồi của bạn" />
              <button type="button" className="secondary-button" disabled={busy || !reply} onClick={() => void sendReply(ticket.id)}>Gửi</button>
              <button type="button" className="text-button" onClick={() => setReplyFor(null)}>Huỷ</button>
            </div>
            : <button type="button" className="text-button" onClick={() => { setReplyFor(ticket.id); setReply(''); }}>Trả lời</button>)}
        </article>)}
      </div>
    </section>
  </>;
}
