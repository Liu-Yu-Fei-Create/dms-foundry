(function () {
const { SEQ, LIBRARY, AA_NAME, CODON, allVariants, estimate } = window.MDATA;

/* ── 基础 ─────────────────────────────────────────── */
const $ = (s, r = document) => r.querySelector(s);
const app = $('#app'), drawerEl = $('#drawer'), toastEl = $('#toast');

const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
};
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => n.toLocaleString('zh-CN');

const BASE = allVariants();
const byId = new Map(BASE.map((v) => [v.id, v]));
const DEPTH = 112;

const S = {
  filter: 'all',
  limit: 60,
  sel: null,
  selected: new Set(),
  overrides: store.get('dms-foundry.overrides', {}),
  draft: store.get('dms-foundry.draft', null),
};

const normalize = (s) => (s === 'x' ? 'drop' : s);
const statusOf = (v) => S.overrides[v.id] || normalize(v.status);
const isDoomed = (v) => statusOf(v) === 'drop';

function counts() {
  const c = { ok: 0, warn: 0, drop: 0, all: BASE.length };
  for (const v of BASE) {
    const st = statusOf(v);
    if (st === 'drop') c.drop++; else if (st === 'warn') c.warn++; else c.ok++;
  }
  return c;
}
function affectedSites() {
  const set = new Set();
  for (const v of BASE) if (isDoomed(v)) set.add(v.pos);
  return set.size;
}
/* 会花钱的数字只按可入单的变体算 */
function orderCost() {
  const c = counts();
  return estimate(SEQ.length, c.ok, DEPTH);
}
const saveOverrides = () => store.set('dms-foundry.overrides', S.overrides);

/* ── 路由 ─────────────────────────────────────────── */
function route() {
  const p = (location.hash || '#/').replace(/^#/, '').split('/').filter(Boolean);
  if (!p.length) return { name: 'workbench' };
  if (p[0] === 'new') return { name: 'new' };
  if (p[0] === 'history') return { name: 'history' };
  if (p[0] === 'lib') return { name: 'lib', id: p[1] || LIBRARY.id, filter: p[2] };
  return { name: 'workbench' };
}
function nav() {
  const r = route();
  document.querySelectorAll('.nav a').forEach((a) => {
    const k = a.dataset.nav;
    a.classList.toggle('on', (k === 'workbench' && r.name === 'workbench') || (k === 'history' && r.name === 'history'));
  });
  if (r.name === 'lib' && r.filter) S.filter = r.filter;
  return r;
}
const go = (hash) => { location.hash = hash; };

/* ── 状态标记 ─────────────────────────────────────── */
const stChip = (v) => {
  const st = statusOf(v);
  if (st === 'drop') return '<span class="st drop"><i></i><s>已剔除</s></span>';
  if (st === 'warn') return '<span class="st warn"><i></i>待复核</span>';
  return '<span class="st ok"><i></i>可合成</span>';
};
const libChip = (s) => {
  const map = { warn: ['待复核', 'warn'], run: ['进行中', 'run'], done: ['已完成', 'done'], draft: ['草稿', 'draft'] };
  const [label, cls] = map[s] || ['—', 'ok'];
  return `<span class="st ${cls}"><i></i>${label}</span>`;
};

/* ── 提示：优先用页面底部状态行，不压数据 ─────────── */
let statusTimer = null;
function notify(msg, undo, back) {
  const line = $('#statusline');
  if (line) {
    const m = $('#slmsg');
    m.innerHTML = esc(msg) + (undo ? ' <button data-act="undo">撤销</button>' : '') + (back ? ' <button data-act="undo">' + esc(back.label) + '</button>' : '');
    m._undo = undo || (back && back.fn) || null;
    line.classList.add('flash');
    clearTimeout(statusTimer);
    statusTimer = setTimeout(() => line.classList.remove('flash'), 6000);
    return;
  }
  toastEl.innerHTML = esc(msg) + (undo ? ' <button data-act="undo">撤销</button>' : '');
  toastEl._undo = undo || null;
  toastEl.classList.add('on');
  clearTimeout(statusTimer);
  statusTimer = setTimeout(() => toastEl.classList.remove('on'), 5000);
}

/* ── 工作台 ───────────────────────────────────────── */
const LIBS = [
  { id: 'tem1-nns', name: 'TEM-1 单点饱和扫描', host: 'E. coli BL21(DE3)', variants: 'live', state: 'warn', note: '12 分钟前' },
  { id: 'pdl1-nnk', name: 'PD-L1 IgV 组合库', host: 'Expi293F', variants: 12288, state: 'run', note: '计算池复杂度 68%' },
  { id: 'ube1-del', name: '泛素 E1 缺失扫描', host: 'E. coli BL21(DE3)', variants: 843, state: 'run', note: '合成中 · 7–9 天' },
  { id: 'cdrh3', name: '抗体 CDR-H3 组合库', host: 'CHO-S', variants: 96000, state: 'done', note: '订单 #T-20418' },
  { id: 'lyz-3site', name: '溶菌酶 3 位点组合', host: 'P. pastoris', variants: 6859, state: 'draft', note: '草稿 · 未定策略' },
  { id: 'rdrp-syn', name: 'RdRp 同义密码子扫描', host: 'HEK293T', variants: 1240, state: 'done', note: '已归档 · 2 周前' },
];

function viewWorkbench() {
  const c = counts(), hit = affectedSites();
  const date = new Date().toLocaleDateString('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit' });
  return `
  <div class="page">
    <div class="page-head">
      <div><h1>工作台</h1><div class="sub">6 个文库 · ${c.warn} 个变体等你决定</div></div>
      <div class="aside"><b>${date}</b>最后校验 ${LIBRARY.checkedAt}</div>
    </div>

    <div class="alerts">
      <div class="hd">需要处理 <b>3 项</b> · 其中 1 项挡下单</div>
      <div class="row top">
        <span class="bar"></span>
        <span class="t">上下文 GC 越界或出现克隆位点，合成会失败
          <s>多数可以用同义密码子换掉；不处理这些变体就进不了订单</s></span>
        <span class="n">${fmt(c.warn)}</span>
        <span class="go" data-act="to-lib" data-filter="warn">去处理 →</span>
      </div>
      <div class="row mini">
        <span class="bar"></span>
        <span class="t">已剔除的变体<s>这些位点各少一个替换，要不要补设计</s></span>
        <span class="n">${fmt(c.drop)}</span>
        <span class="go" data-act="to-lib" data-filter="drop">查看 →</span>
      </div>
      <div class="row mini">
        <span class="bar"></span>
        <span class="t">被剔除影响的位点<s>这些位点的饱和扫描已经不完整</s></span>
        <span class="n">${hit}</span>
        <span class="go" data-act="to-lib" data-filter="drop">查看 →</span>
      </div>
    </div>

    <table class="table" style="margin-top:30px">
      <colgroup><col style="width:300px"><col style="width:200px"><col style="width:120px"><col style="width:130px"><col></colgroup>
      <thead><tr><th>文库</th><th>宿主</th><th style="text-align:right">变体</th><th>状态</th><th>更新</th></tr></thead>
      <tbody>
        ${LIBS.map((l) => `
        <tr class="click" data-act="open-lib" data-id="${l.id}">
          <td class="name">${esc(l.name)}</td>
          <td class="dim">${esc(l.host)}</td>
          <td class="m" style="text-align:right">${l.variants === 'live' ? fmt(c.all) : fmt(l.variants)}</td>
          <td>${libChip(l.state)}</td>
          <td class="dim">${esc(l.note)}</td>
        </tr>`).join('')}
      </tbody>
    </table>

    <div class="recent">
      <h3>最近操作</h3>
      <div class="arow"><span class="t">12 分钟前</span><span class="c">v3 校验通过<s>${fmt(c.ok)} 可合成 · ${fmt(c.warn)} 待复核 · ${fmt(c.drop)} 已剔除</s></span><span class="r">LY</span></div>
      <div class="arow"><span class="t">昨天 18:40</span><span class="c">v2 被否<s>仍有 8 个变体保留 BsaI 识别位点</s></span><span class="r">LY</span></div>
    </div>
  </div>`;
}

/* ── 结果详情 ─────────────────────────────────────── */
const filtered = () => BASE.filter((v) => {
  const st = statusOf(v);
  if (S.filter === 'ok') return st === 'ok';
  if (S.filter === 'warn') return st === 'warn';
  if (S.filter === 'drop') return st === 'drop';
  return true;
});

const POS_TOTAL = 19;
function posOkMap() {
  const m = new Map();
  for (const v of BASE) if (statusOf(v) !== 'drop') m.set(v.pos, (m.get(v.pos) || 0) + 1);
  return m;
}

function viewLib() {
  const c = counts(), rows = filtered(), cost = orderCost(), hit = affectedSites();
  const posOk = posOkMap();
  const shown = rows.slice(0, S.limit);
  const pageIds = shown.map((v) => v.id);
  const picked = pageIds.filter((id) => S.selected.has(id)).length;
  const bar = S.selected.size
    ? `<div class="selbar"><b>已选 ${S.selected.size} 条</b>
         <span class="b" data-act="bulk-drop">标记剔除</span>
         <span class="b" data-act="bulk-export">导出所选</span>
         <span class="b" data-act="bulk-clear">清除</span></div>`
    : `<div class="tabs">
        ${[['all', '全部', c.all], ['ok', '可合成', c.ok], ['warn', '待复核', c.warn], ['drop', '已剔除', c.drop]]
          .map(([k, label, n]) => `<span class="tab ${S.filter === k ? 'on' : ''}" data-filter="${k}">${label}<b>${fmt(n)}</b></span>`).join('')}
      </div>
      <div class="pills"><span class="pill">策略 NNS <x data-act="noop">✕</x></span><span class="pill add">＋ 筛选</span></div>`;

  return `
  <div class="page">
    <div class="page-head">
      <div>
        <h1>${esc(LIBRARY.name)}<span class="meta">263 aa / 789 nt · ${SEQ.length} 位点</span></h1>
        <div class="sub">${esc(LIBRARY.strategy)} · ${esc(LIBRARY.host)} · 载体 ${esc(LIBRARY.vector)}</div>
      </div>
      <div class="aside"><b>${LIBRARY.version} · ${LIBRARY.checkedAt}</b>${LIBRARY.owner}</div>
    </div>

    <div class="band">
      <div><span>入单变体</span><b>${fmt(c.ok)}</b></div>
      <div><span>预估费用（按入单）</span><b>¥${fmt(cost.total)}</b></div>
      <div><span>受影响位点</span><b>${hit}</b></div>
      <div class="note">待复核 ${fmt(c.warn)} 与已剔除 ${fmt(c.drop)} 不进订单<br>测序 ${DEPTH}× / 变体 · 2×150 PE</div>
    </div>

    <div class="tools">
      ${bar}
      <div class="right">
        ${S.selected.size ? '' : `<div class="order"><span class="link" data-act="export">导出 CSV</span>
        <span class="link" data-act="order">下单 ${fmt(c.ok)} 条</span><em>${fmt(c.warn + c.drop)} 条不入单</em></div>`}
      </div>
    </div>

    <div class="gridwrap">
      <table class="grid">
        <colgroup>
          <col style="width:3%"><col style="width:9.5%"><col style="width:5%"><col style="width:22%">
          <col style="width:17%"><col style="width:9.5%"><col style="width:7%"><col style="width:9%">
          <col style="width:11%"><col style="width:7%">
        </colgroup>
        <thead><tr>
          <th><span class="ck ${picked && picked === pageIds.length ? 'on' : picked ? 'part' : ''}" data-act="select-page"></span></th>
          <th>变体</th><th style="text-align:right">位点</th><th>替换</th><th>密码子</th>
          <th>合成性</th><th style="text-align:right">预估覆盖</th><th>状态</th><th></th>
        </tr></thead>
        <tbody>
          ${shown.map((v) => {
            const st = statusOf(v), on = S.selected.has(v.id);
            return `<tr class="click ${st === 'drop' ? 'drop' : ''} ${S.sel === v.id ? 'sel' : ''}" data-act="open-variant" data-id="${v.id}">
              <td><span class="ck ${on ? 'on' : ''}" data-act="toggle-sel" data-id="${v.id}"></span></td>
              <td class="id">${v.id}</td>
              <td class="m r">${v.pos}</td>
              <td>${AA_NAME[v.wt]} → ${AA_NAME[v.aa]}</td>
              <td class="m">${CODON[v.wt]} → ${v.codon}</td>
              <td class="m">${posOk.get(v.pos)}<span style="color:var(--faint)"> / ${POS_TOTAL}</span></td>
              <td class="m">${v.synth}</td>
              <td class="m r">${v.coverage.toFixed(1)}×</td>
              <td>${stChip(v)}</td>
              <td class="act">${st === 'drop'
                ? '<span data-act="restore" data-id="' + v.id + '">恢复</span>'
                : '<span data-act="drop-one" data-id="' + v.id + '">剔除</span>'}</td>
            </tr>`;
          }).join('')}
        </tbody>
      </table>
    </div>

    <div class="statusline" id="statusline">
      <div class="msg" id="slmsg"></div>
      <div class="base">
        <span>显示 1–${shown.length} / ${fmt(rows.length)} 条 · 按位点排序</span>
        ${rows.length > shown.length ? '<button class="btn plain sm" data-act="more">再显示 60 条</button>' : ''}
        <span style="margin-left:auto">${S.filter === 'warn' ? '待复核＝合成风险未定，仍占位，需要人工取舍' : S.filter === 'drop' ? '已剔除＝已作废，不进池、不计费' : '待复核与已剔除都不进订单'}</span>
      </div>
    </div>
  </div>`;
}

/* ── 新建向导 ─────────────────────────────────────── */
const cleanSeq = (s) => (s || '').toUpperCase().replace(/[^A-Z]/g, '');
const defaultDraft = () => ({
  step: 1, name: 'TEM-1 单点饱和扫描', seq: SEQ, host: 'E. coli BL21(DE3)', vector: 'pET-28a',
  strategy: 'nns', control: true, depth: DEPTH, vendor: 'Twist',
});
const D = () => S.draft || defaultDraft();
const saveDraft = () => store.set('dms-foundry.draft', S.draft);
const ago = (ts) => {
  const m = Math.max(0, Math.round((Date.now() - ts) / 60000));
  return m < 1 ? '刚刚' : m + ' 分钟前';
};

const STEPS = [
  ['01', '靶标与父序列', '序列、宿主与载体'],
  ['02', '扫描策略', '每个位点怎么变'],
  ['03', '池与合成', '合成商与测序覆盖'],
  ['04', '校验与导出', '算一遍再下单'],
];

function wizardCalc() {
  const d = D(), seq = cleanSeq(d.seq);
  const sites = seq.length, variants = d.strategy === 'nns' ? sites * 19 : sites;
  const depth = Number(d.depth) || 0;
  return { d, seq, sites, variants, depth, cost: estimate(sites, variants, depth) };
}

function costRows(cost, sites, variants, depth) {
  const perOligo = sites ? (cost.pool / sites).toFixed(1) : '0';
  const perVar = variants ? (cost.cloning / variants).toFixed(2) : '0';
  const reads = variants * depth;
  const perRead = reads ? (cost.ngs / reads).toFixed(4) : '0';
  return `
    <div class="r"><span>寡核苷酸池</span><i>${fmt(sites)} 条 × ¥${perOligo}</i><b>¥${fmt(cost.pool)}</b></div>
    <div class="r"><span>克隆与建库</span><i>${fmt(variants)} 条 × ¥${perVar}</i><b>¥${fmt(cost.cloning)}</b></div>
    <div class="r"><span>测序（${depth}×）</span><i>${fmt(reads)} 读数 × ¥${perRead}</i><b>¥${fmt(cost.ngs)}</b></div>
    <div class="r total"><span>合计</span><i></i><b>¥${fmt(cost.total)}</b></div>`;
}

function viewNew() {
  const { d, seq, sites, variants, depth, cost } = wizardCalc();
  const ok = sites >= 20;
  const est = `<div class="esthead">估算（校验前按全部变体算）</div><div class="calc">${costRows(cost, sites, variants, depth)}</div>`;
  return `
  <div class="page">
    <div class="page-head">
      <div><h1>新建文库</h1><div class="sub">从父序列起，把一次深度突变扫描设计到可以下单</div></div>
      <div class="aside"><b>${sites} aa</b>${ok ? '序列可以设计' : '至少需要 20 个残基'}</div>
    </div>

    <div class="wizard">
      <div class="steps">
        ${STEPS.map(([n, t, sub], i) => `
          <div class="s ${d.step === i + 1 ? 'on' : ''} ${d.step > i + 1 ? 'done' : ''}" data-step="${i + 1}">
            <span class="n">${n}</span><span><span class="t">${t}</span><span class="d">${sub}</span></span>
          </div>`).join('')}
      </div>

      <div class="form">
        ${d.step === 1 ? `
          <h2>父序列与宿主</h2>
          <p class="lede">粘贴成熟蛋白的氨基酸序列。宿主决定密码子偏好与合成约束。</p>
          <div class="field">
            <label for="f-seq">父序列（氨基酸）</label>
            <textarea class="input" id="f-seq" rows="5" spellcheck="false">${esc(d.seq)}</textarea>
            <span class="hint">${sites} 个残基 · 按 E. coli 偏好密码子回译 · 非字母字符会被忽略</span>
          </div>
          <div class="field"><label for="f-name">文库名称</label><input class="input" id="f-name" value="${esc(d.name)}"></div>
          <div class="field"><label for="f-host">宿主</label>
            <select class="input" id="f-host">${['E. coli BL21(DE3)', 'E. coli DH5α', 'S. cerevisiae BY4741', 'P. pastoris GS115', 'Expi293F', 'CHO-S', 'HEK293T', '无细胞体系']
              .map((h) => `<option ${h === d.host ? 'selected' : ''}>${h}</option>`).join('')}</select></div>
          <div class="field"><label for="f-vector">载体</label><input class="input" id="f-vector" value="${esc(d.vector)}"></div>
        ` : ''}

        ${d.step === 2 ? `
          <h2>扫描策略</h2>
          <p class="lede">决定每个位点生成多少变体。策略直接改变池大小和你最后能回答的问题。</p>
          <div class="split">
            <div>
              <div class="radios">
                <label class="${d.strategy === 'nns' ? 'on' : ''}">
                  <input type="radio" name="strategy" value="nns" ${d.strategy === 'nns' ? 'checked' : ''}>
                  <span>NNS 逐位点饱和<s>每位点 19 个替换，回答“这个位点能换成什么”</s></span>
                </label>
                <label class="${d.strategy === 'ala' ? 'on' : ''}">
                  <input type="radio" name="strategy" value="ala" ${d.strategy === 'ala' ? 'checked' : ''}>
                  <span>丙氨酸扫描<s>每位点只换成 Ala，回答“这个位点重不重要”</s></span>
                </label>
              </div>
              <label class="hint" style="display:flex;gap:8px;align-items:center;cursor:pointer;margin-top:14px">
                <input type="checkbox" id="f-control" ${d.control ? 'checked' : ''}> 同时保留每个位点的同义对照（野生型）
              </label>
            </div>
            <div>${est}</div>
          </div>
        ` : ''}

        ${d.step === 3 ? `
          <h2>池与合成</h2>
          <p class="lede">阵列合成的寡核苷酸池有长度与复杂度上限，覆盖度决定每个变体被测到多少次。</p>
          <div class="split">
            <div>
              <div class="field"><label for="f-vendor">合成商</label>
                <select class="input" id="f-vendor">${['Twist', 'IDT', '生工', '金斯瑞']
                  .map((v) => `<option ${v === d.vendor ? 'selected' : ''}>${v}</option>`).join('')}</select></div>
              <div class="field"><label for="f-depth">目标测序深度（每变体读数覆盖）</label>
                <input class="input" id="f-depth" type="number" min="10" max="500" step="2" value="${d.depth}">
                <span class="hint">当前 ${depth}×：2×150 PE 下建议 ≥100×，低于 50× 容易漏掉稀有功能变体</span></div>
            </div>
            <div>${est}</div>
          </div>
        ` : ''}

        ${d.step === 4 ? `
          <h2>校验</h2>
          <p class="lede">按当前参数把序列算一遍：可合成性、限制性位点、GC 越界与同聚物都会标出来，只有可合成的变体进订单。</p>
          <div class="split">
            <div>
              <div class="field"><label>校验结果</label><div class="hint body" id="check">正在计算…</div></div>
              <div class="field"><label>下单信息</label>
                <div class="hint body">${esc(d.vendor)} 阵列池 · ${fmt(sites)} 条 · ${esc(d.host)} · ${esc(d.vector)}</div></div>
            </div>
            <div id="est-after">${est}</div>
          </div>
        ` : ''}

        <div class="formfoot">
          ${d.step > 1 ? '<button class="btn plain" data-act="prev">上一步</button>' : ''}
          ${d.step < 4 ? `<button class="btn dark" data-act="next" ${ok ? '' : 'disabled'}>下一步</button>`
            : '<button class="btn dark" data-act="create">生成文库并校验</button>'}
          <span class="save">${S.draft ? '已自动保存 · ' + ago(S.draft.saved) : '修改会自动保存在本机'}</span>
        </div>
      </div>
    </div>
  </div>`;
}

/* ── 历史 ─────────────────────────────────────────── */
function viewHistory() {
  const c = counts();
  return `
  <div class="page">
    <div class="page-head">
      <div><h1>历史</h1><div class="sub">版本、订单和每一次校验的结论</div></div>
      <div class="aside"><b>3 个版本</b>2 次被否 · 1 次待确认</div>
    </div>

    <div class="two">
      <div>
        <h3>版本记录 · TEM-1 单点饱和扫描</h3>
        <div class="hitem"><span class="v">v3</span><span class="c">当前版本 · ${fmt(c.warn)} 个变体待你确认<s>确认或剔除之后才能下单</s></span><span class="t">12 分钟前</span><span class="r">待确认</span></div>
        <div class="hitem"><span class="v">v2</span><span class="c">换用 BsaI 兼容的密码子<s>仍有 8 个变体保留识别位点</s></span><span class="t">昨天 18:40</span><span class="r">被否</span></div>
        <div class="hitem"><span class="v">v1</span><span class="c">首版全 NNS 池<s>池复杂度不足，覆盖只有 1.4×</s></span><span class="t">昨天 15:12</span><span class="r">被否</span></div>
      </div>
      <div>
        <h3>订单</h3>
        <div class="hitem"><span class="v">#20418</span><span class="c">抗体 CDR-H3 组合库<s>Twist 阵列池 · 96,000 条</s></span><span class="t">3 天前</span><span class="r">已下单</span></div>
        <div class="hitem"><span class="v">#20391</span><span class="c">泛素 E1 缺失扫描<s>生工 · 843 条 · 合成中</s></span><span class="t">昨天</span><span class="r">进行中</span></div>
        <div class="hitem"><span class="v">#20355</span><span class="c">RdRp 同义密码子扫描<s>金斯瑞 · 1,240 条 · 已到货</s></span><span class="t">2 周前</span><span class="r">已完成</span></div>
      </div>
    </div>

    <div class="recent">
      <h3>校验记录</h3>
      <div class="arow"><span class="t">12 分钟前</span><span class="c">v3 · ${fmt(c.ok)} 可合成 / ${fmt(c.warn)} 待复核 / ${fmt(c.drop)} 已剔除<s>耗时 2.4 s</s></span><span class="r">待确认</span></div>
      <div class="arow"><span class="t">昨天 18:40</span><span class="c">v2 · 4,585 可合成 / 380 待复核 / 32 已剔除<s>BsaI 位点未清</s></span><span class="r">被否</span></div>
      <div class="arow"><span class="t">昨天 15:12</span><span class="c">v1 · 4,947 可合成 / 50 待复核 / 0 已剔除<s>池复杂度 1.4×，覆盖不足</s></span><span class="r">被否</span></div>
    </div>
  </div>`;
}

/* ── 渲染 ─────────────────────────────────────────── */
function a11y() {
  document.querySelectorAll('[data-act]').forEach((el) => {
    if (el.tagName === 'BUTTON' || el.tagName === 'A') return;
    if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '0');
    if (!el.hasAttribute('role')) el.setAttribute('role', 'button');
  });
}
function render() {
  const r = nav();
  if (r.name === 'workbench') app.innerHTML = viewWorkbench();
  else if (r.name === 'history') app.innerHTML = viewHistory();
  else if (r.name === 'new') { app.innerHTML = viewNew(); if (D().step === 4) setTimeout(runCheck, 220); }
  else if (r.name === 'lib') app.innerHTML = r.id === LIBRARY.id ? viewLib() : emptyLib(r.id);
  if (S.sel) openDrawer(S.sel, false);
  a11y();
}

function emptyLib(id) {
  const l = LIBS.find((x) => x.id === id) || LIBS[0];
  return `<div class="page">
    <div class="page-head">
      <div><h1>${esc(l.name)}</h1><div class="sub">${esc(l.host)} · ${esc(l.note)}</div></div>
      <div class="aside"><b>${l.state === 'draft' ? '草稿' : '进行中'}</b>还没有变体表</div>
    </div>
    <div class="empty">
      <b>这个文库还没有生成结果</b>
      <p>${l.state === 'draft' ? '先把扫描策略定下来，DMS Foundry 才能算出变体和池。' : '参数已经提交，正在计算池复杂度。结果出来后会在工作台出现。'}</p>
      <a class="btn" href="#/new">去看看怎么建</a>
    </div>
  </div>`;
}

/* ── 抽屉 ─────────────────────────────────────────── */
function neighbor(id, dir) {
  const rows = filtered();
  const i = rows.findIndex((v) => v.id === id);
  if (i < 0) return null;
  return rows[(i + dir + rows.length) % rows.length];
}

function openDrawer(id, animate = true) {
  const v = byId.get(id);
  if (!v) return;
  S.sel = id;
  const st = statusOf(v), c = counts();
  const win = `${esc(v.left)}<em>${esc(v.codon)}</em>${esc(v.right)}`;
  const verdict = st === 'drop' ? '已作废，不进池、不计费'
    : st === 'warn' ? '合成风险未定，需要你决定'
      : '可以进池';
  const advise = st === 'ok'
    ? '上下文与密码子都在可合成区间内，不需要额外处理。'
    : st === 'warn'
      ? '最省事的做法是换一个同义密码子（避开 GC 越界或酶切位点）再校验；确认没问题也可以直接放进池。'
      : '这个变体已经不可合成，位点会少一个替换。可以换同义密码子重算，或接受这个缺口。';

  drawerEl.innerHTML = `
    <div class="dhead"><h2>${v.id}</h2><span class="x" data-act="close-drawer">✕</span></div>
    <div class="verdict">${verdict}</div>
    <div class="dbody">
      <dl class="kv">
        <dt>位点</dt><dd class="mono">${v.pos}</dd>
        <dt>替换</dt><dd>${AA_NAME[v.wt]} → ${AA_NAME[v.aa]}</dd>
        <dt>密码子</dt><dd class="mono">${CODON[v.wt]} → ${v.codon}</dd>
        <dt>复核原因</dt><dd>${st === 'warn' || st === 'drop' ? esc(v.why) : '无'}</dd>
        <dt>合成性</dt><dd class="mono">${v.synth}<span style="color:var(--faint);font-family:var(--sans);font-size:11.5px"> / 100（低于 80 建议换密码子）</span></dd>
        <dt>预估覆盖</dt><dd class="mono">${v.coverage.toFixed(1)}×</dd>
        <dt>状态</dt><dd>${stChip(v)}</dd>
      </dl>

      <div style="font-size:11.5px;color:var(--muted);margin-bottom:8px">上下文 ${v.window.length} nt，变异密码子反显${v.edge ? ' · 序列末端，侧翼不足 8 nt' : ''}</div>
      <div class="seqbox">${win}</div>
      <div class="hint" style="margin-bottom:14px">GC ${v.gc.toFixed(2)} · 最长同聚物 ${v.run}</div>

      <div class="why">${advise}</div>
      <p class="note">改动只影响本地这份设计，不会自动写回合成商的订单。</p>
    </div>
    <div class="dfoot">
      ${st === 'drop'
        ? `<button class="btn dark" data-act="restore" data-id="${v.id}">恢复到池</button>`
        : st === 'warn'
          ? `<button class="btn dark" data-act="accept" data-id="${v.id}">确认进池</button><button class="btn plain" data-act="drop" data-id="${v.id}">剔除</button>`
          : `<button class="btn plain" data-act="drop" data-id="${v.id}">剔除</button>`}
      <button class="btn plain next" data-act="next-variant" data-id="${v.id}">下一条 →</button>
    </div>`;
  drawerEl.classList.add('on');
  drawerEl.setAttribute('aria-hidden', 'false');
  document.body.classList.add('has-drawer');
  if (!animate) { drawerEl.style.transition = 'none'; setTimeout(() => (drawerEl.style.transition = ''), 30); }
  document.querySelectorAll('.grid tbody tr').forEach((tr) => tr.classList.toggle('sel', tr.dataset.id === id));
}

function closeDrawer() {
  S.sel = null;
  drawerEl.classList.remove('on');
  drawerEl.setAttribute('aria-hidden', 'true');
  document.body.classList.remove('has-drawer');
  document.querySelectorAll('.grid tbody tr.sel').forEach((tr) => tr.classList.remove('sel'));
}

/* ── 校验 ─────────────────────────────────────────── */
function runCheck() {
  const el = $('#check');
  if (!el) return;
  const { seq } = wizardCalc();
  const list = allVariants(seq);
  const warn = list.filter((v) => normalize(v.status) === 'warn').length;
  const drop = list.filter((v) => normalize(v.status) === 'drop').length;
  const ok = list.length - warn - drop;
  el.innerHTML = `可合成 <b class="mono">${fmt(ok)}</b> · 待复核 <b class="mono">${fmt(warn)}</b> · 已剔除 <b class="mono">${fmt(drop)}</b><br>
    只有可合成的 ${fmt(ok)} 条进订单；剔除多来自上下文 GC 越界与同聚物，换同义密码子能救回大部分。`;
  const box = $('#est-after');
  if (box) {
    const cost = estimate(seq.length, ok, Number(D().depth) || 0);
    box.innerHTML = `<div class="esthead">下单估算（按可合成 ${fmt(ok)} 条重算）</div>
      <div class="calc">${costRows(cost, seq.length, ok, Number(D().depth) || 0)}</div>`;
  }
}

/* ── 导出 ─────────────────────────────────────────── */
function exportCsv(list) {
  const rows = list || filtered();
  const head = 'variant,pos,wt,mut,codon,gc,synth,status,coverage';
  const body = rows.map((v) => [v.id, v.pos, v.wt, v.aa, v.codon, v.gc.toFixed(2), v.synth, statusOf(v), v.coverage.toFixed(1)].join(',')).join('\n');
  const blob = new Blob(['\uFEFF' + head + '\n' + body], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'dms-foundry-tem1-v3.csv';
  a.click();
  URL.revokeObjectURL(a.href);
  notify(`已导出 ${fmt(rows.length)} 条变体`);
}

/* ── 剔除 / 恢复 ──────────────────────────────────── */
function applyOverride(ids, value) {
  const before = {};
  ids.forEach((id) => { before[id] = S.overrides[id]; });
  ids.forEach((id) => { if (value === null) delete S.overrides[id]; else S.overrides[id] = value; });
  saveOverrides();
  const undo = () => {
    Object.keys(before).forEach((id) => {
      if (before[id] === undefined) delete S.overrides[id]; else S.overrides[id] = before[id];
    });
    saveOverrides(); render(); if (S.sel) openDrawer(S.sel, false);
  };
  return undo;
}

/* ── 事件 ─────────────────────────────────────────── */
document.addEventListener('click', (e) => {
  const t = e.target.closest('[data-act]');
  if (!t) return;
  const act = t.dataset.act, id = t.dataset.id;

  if (act === 'open-lib') return go('#/lib/' + id);
  if (act === 'to-lib') return go('#/lib/' + LIBRARY.id + '/' + (t.dataset.filter || 'warn'));
  if (act === 'open-variant') return openDrawer(id);
  if (act === 'close-drawer') return closeDrawer();
  if (act === 'next-variant') { const n = neighbor(id, 1); if (n) openDrawer(n.id); return; }
  if (act === 'export') return exportCsv();
  if (act === 'order') return notify(`已生成订单草稿 · ${fmt(counts().ok)} 条，去历史里确认`);
  if (act === 'noop') return;

  if (act === 'toggle-sel') {
    e.stopPropagation();
    if (S.selected.has(id)) S.selected.delete(id); else S.selected.add(id);
    return render();
  }
  if (act === 'select-page') {
    const rows = filtered().slice(0, S.limit).map((v) => v.id);
    const all = rows.every((x) => S.selected.has(x));
    rows.forEach((x) => { if (all) S.selected.delete(x); else S.selected.add(x); });
    return render();
  }
  if (act === 'bulk-clear') { S.selected.clear(); return render(); }
  if (act === 'bulk-export') return exportCsv(BASE.filter((v) => S.selected.has(v.id)));
  if (act === 'bulk-drop') {
    const ids = [...S.selected];
    const sites = new Set(ids.map((x) => byId.get(x).pos)).size;
    const undo = applyOverride(ids, 'drop');
    S.selected.clear();
    render();
    notify(`已剔除 ${ids.length} 条，影响 ${sites} 个位点`, undo);
    return;
  }

  if (act === 'drop-one' || act === 'drop' || act === 'restore' || act === 'accept') {
    e.stopPropagation();
    const undo = applyOverride([id], act === 'drop-one' || act === 'drop' ? 'drop' : null);
    render();
    if (S.sel) openDrawer(S.sel, false);
    const label = act === 'restore' || act === 'accept' ? '已恢复到池' : '已剔除';
    notify(`${label} ${id}`, undo);
    return;
  }

  if (act === 'undo') {
    const fn = (t.closest('.statusline') ? $('#slmsg')._undo : toastEl._undo);
    if (fn) fn();
    $('#statusline').classList.remove('flash');
    toastEl.classList.remove('on');
    return;
  }

  if (act === 'more') { S.limit += 60; return render(); }
  if (act === 'next' || act === 'prev') {
    const d = D();
    S.draft = { ...d, step: Math.max(1, Math.min(4, d.step + (act === 'next' ? 1 : -1))), saved: Date.now() };
    saveDraft(); return render();
  }
  if (act === 'create') {
    S.draft = null; store.set('dms-foundry.draft', null);
    go('#/lib/' + LIBRARY.id);
    return setTimeout(() => notify('已生成 · 正在打开校验结果'), 60);
  }
});

document.addEventListener('click', (e) => {
  const tab = e.target.closest('[data-filter]');
  if (tab) { S.filter = tab.dataset.filter; S.limit = 60; S.selected.clear(); return render(); }
  const step = e.target.closest('[data-step]');
  if (step) {
    S.draft = { ...D(), step: Number(step.dataset.step), saved: Date.now() };
    saveDraft(); return render();
  }
});

document.addEventListener('input', (e) => {
  const el = e.target;
  const map = { 'f-seq': 'seq', 'f-name': 'name', 'f-host': 'host', 'f-vector': 'vector', 'f-depth': 'depth', 'f-vendor': 'vendor' };
  const key = map[el.id];
  if (key) {
    S.draft = { ...D(), [key]: el.value, saved: Date.now() };
    saveDraft();
    if (el.id === 'f-seq') {
      const n = cleanSeq(el.value).length;
      const aside = document.querySelector('.page-head .aside');
      if (aside) aside.innerHTML = `<b>${n} aa</b>${n >= 20 ? '序列可以设计' : '至少需要 20 个残基'}`;
    }
  }
  if (el.name === 'strategy') { S.draft = { ...D(), strategy: el.value, saved: Date.now() }; saveDraft(); render(); }
  if (el.id === 'f-control') { S.draft = { ...D(), control: el.checked, saved: Date.now() }; saveDraft(); }
});
document.addEventListener('change', (e) => {
  if (['f-host', 'f-vendor', 'f-depth'].includes(e.target.id) || e.target.name === 'strategy') render();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && S.sel) return closeDrawer();
  if (S.sel && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
    const n = neighbor(S.sel, e.key === 'ArrowDown' ? 1 : -1);
    if (n) { e.preventDefault(); openDrawer(n.id); }
    return;
  }
  const t = e.target.closest && e.target.closest('[data-act]');
  if (t && (e.key === 'Enter' || e.key === ' ') && !['BUTTON', 'A'].includes(e.target.tagName)) {
    e.preventDefault(); t.click();
  }
});

window.addEventListener('hashchange', () => { closeDrawer(); S.selected.clear(); render(); });

if (new URLSearchParams(location.search).has('reset')) {
  try { localStorage.removeItem('dms-foundry.overrides'); localStorage.removeItem('dms-foundry.draft'); } catch {}
  S.overrides = {}; S.draft = null;
}
if (S.draft && !S.draft.step) S.draft.step = 1;
render();
})();
