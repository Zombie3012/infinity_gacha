import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type ShopItem = {
  code: string;
  name: string;
  description: string;
  itemId: string;
  category: string;
  priceSilver: string;
  dailyLimit: number;
  purchasedToday: number;
  remainingToday: number | null;
};

type MailMessage = {
  id: string;
  sender: string;
  subject: string;
  body: string;
  attachments: { silver?: number; items?: { itemId: string; quantity: number }[] };
  isClaimed: boolean;
  expiresAt: string;
  createdAt: string;
};

type Mailbox = { unclaimed: MailMessage[]; claimed: MailMessage[]; purged: number };

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

export function ShopPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [tab, setTab] = useState('shop');
  const [items, setItems] = useState<ShopItem[]>([]);
  const [mail, setMail] = useState<Mailbox | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [shop, mailbox] = await Promise.all([
      call<{ items: ShopItem[] }>('/api/shop', token),
      call<Mailbox>('/api/mailbox', token),
    ]);
    setItems(shop.items);
    setMail(mailbox);
  }, [token]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const buy = async (item: ShopItem, quantity: number) => {
    setBusy(true);
    onError('');
    try {
      const result = await call<{ purchased: number; silverSpent: number; warning: string | null }>('/api/shop/purchase', token, {
        method: 'POST',
        body: JSON.stringify({ itemCode: item.code, quantity }),
      });
      await load();
      onNotice(`Đã mua ${result.purchased} × ${item.name} (${numberFormat.format(result.silverSpent)} Xu)${result.warning ? ' — đã chạm giới hạn ngày' : ''}`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const claim = async (message: MailMessage) => {
    setBusy(true);
    onError('');
    try {
      await call(`/api/mailbox/${message.id}/claim`, token, { method: 'POST' });
      await load();
      onNotice('Đã nhận quà đính kèm.');
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const attachmentLabel = (message: MailMessage) => {
    const parts: string[] = [];
    if (message.attachments.silver) parts.push(`${numberFormat.format(message.attachments.silver)} Xu`);
    for (const item of message.attachments.items ?? []) parts.push(`${item.quantity} × ${item.itemId}`);
    return parts.length ? parts.join(' · ') : 'Không có đính kèm';
  };

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">SUPPLY · PHASE 1</div>
        <h1>Cửa hàng & Hộp thư</h1>
        <p>Mua vật phẩm bằng Xu Bạc theo giới hạn ngày, và nhận quà từ hệ thống hoặc vận hành viên.</p>
      </div>
    </div>

    <div className="admin-tabs">
      <button type="button" className={`admin-tab ${tab === 'shop' ? 'active' : ''}`} onClick={() => setTab('shop')}>Cửa hàng</button>
      <button type="button" className={`admin-tab ${tab === 'mail' ? 'active' : ''}`} onClick={() => setTab('mail')}>Hộp thư{mail && mail.unclaimed.length > 0 ? ` (${mail.unclaimed.length})` : ''}</button>
    </div>

    {tab === 'shop' && <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">CATALOGUE</div><h2>Danh mục hôm nay</h2></div>
        <button type="button" className="secondary-button" onClick={() => void load().catch(error => onError((error as Error).message))}>Làm mới</button>
      </div>
      <div className="shop-grid">
        {items.length === 0 && <div className="empty-state"><p>Chưa có mặt hàng nào được cấu hình.</p></div>}
        {items.map(item => {
          const soldOut = item.remainingToday === 0;
          return <article className="shop-card" key={item.code}>
            <header><b>{item.name}</b><em className="admin-badge">{item.category}</em></header>
            <p>{item.description}</p>
            <div className="shop-price">
              <span>{numberFormat.format(Number(item.priceSilver))} Xu</span>
              <small>{item.remainingToday === null ? 'không giới hạn' : `còn ${item.remainingToday}/${item.dailyLimit} hôm nay`}</small>
            </div>
            <div className="shop-actions">
              <button type="button" className="primary-button" disabled={busy || soldOut} onClick={() => void buy(item, 1)}>Mua 1</button>
              <button type="button" className="secondary-button" disabled={busy || soldOut} onClick={() => void buy(item, 5)}>Mua 5</button>
            </div>
          </article>;
        })}
      </div>
    </section>}

    {tab === 'mail' && <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">INBOX</div><h2>Thư chưa nhận</h2></div>
        <button type="button" className="secondary-button" onClick={() => void load().catch(error => onError((error as Error).message))}>Làm mới</button>
      </div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Tiêu đề</span><span>Người gửi</span><span>Đính kèm</span><span>Hết hạn</span><span /></div>
        {(!mail || mail.unclaimed.length === 0) && <div className="admin-row"><span>Hộp thư trống.</span></div>}
        {mail?.unclaimed.map(message => <div className="admin-row" key={message.id}>
          <span>{message.subject}<small className="admin-muted">{message.body.slice(0, 90)}</small></span>
          <span>{message.sender}</span>
          <span>{attachmentLabel(message)}</span>
          <span>{when(message.expiresAt)}</span>
          <span><button type="button" className="secondary-button" disabled={busy} onClick={() => void claim(message)}>Nhận quà</button></span>
        </div>)}
      </div>

      {mail && mail.claimed.length > 0 && <>
        <div className="panel-head" style={{ marginTop: 18 }}><div><div className="eyebrow">HISTORY</div><h2>Đã nhận</h2></div></div>
        <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Tiêu đề</span><span>Người gửi</span><span>Đính kèm</span><span>Đã nhận</span><span /></div>
          {mail.claimed.slice(0, 8).map(message => <div className="admin-row" key={message.id}>
            <span>{message.subject}</span>
            <span>{message.sender}</span>
            <span>{attachmentLabel(message)}</span>
            <span>{when(message.createdAt)}</span>
            <span><em className="admin-badge ok">Đã nhận</em></span>
          </div>)}
        </div>
      </>}
    </section>}
  </>;
}
