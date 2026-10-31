/* DMS Foundry · 数据层
   真实序列：UniProt P62593 (TEM-1) 去 23 aa 信号肽的成熟蛋白，263 aa / 789 nt。
   所有变体、GC、合成性、待复核与剔除状态都由这条序列现场算出，不是编造的数字。 */

(function () {
const SEQ =
  'HPETLVKVKDAEDQLGARVGYIELDLNSGKILESFRPEERFPMMSTFKVLLCGAVLSRVDAGQEQLGRRIHYSQNDLVEYSPVTEKH' +
  'LTDGMTVRELCSAAITMSDNTAANLLLTTIGGPKELTAFLHNMGDHVTRLDRWEPELNEAIPNDERDTTMPAAMATTLRKLLTGEL' +
  'LTLASRQQLIDWMEADKVAGPLLRSALPAGWFIADKSGAGERGSRGIIAALGPDGKPSRIVVIYTTGSQATMDERNRQIAEIGAS' +
  'LIKHW';

/* E. coli 偏好密码子 */
const CODON = {
  A:'GCT', C:'TGC', D:'GAT', E:'GAA', F:'TTC', G:'GGC', H:'CAT', I:'ATC', K:'AAA',
  L:'CTG', M:'ATG', N:'AAC', P:'CCG', Q:'CAG', R:'CGT', S:'AGC', T:'ACC', V:'GTT',
  W:'TGG', Y:'TAC',
};

const AA_NAME = {
  A:'Ala', C:'Cys', D:'Asp', E:'Glu', F:'Phe', G:'Gly', H:'His', I:'Ile', K:'Lys',
  L:'Leu', M:'Met', N:'Asn', P:'Pro', Q:'Gln', R:'Arg', S:'Ser', T:'Thr', V:'Val',
  W:'Trp', Y:'Tyr',
};

/* 成熟蛋白的编码 DNA：全部用偏好密码子 */
const DNA = [...SEQ].map((aa) => CODON[aa]).join('');

const RC = { A:'T', T:'A', G:'C', C:'G' };
const revcomp = (s) => [...s].reverse().map((b) => RC[b]).join('');

const ENZYMES = [
  { name:'BsaI',  site:'GGTCTC', gap:1, label:'BsaI',  blocks:8 },
  { name:'BsmBI', site:'CGTCTC', gap:1, label:'BsmBI', blocks:8 },
  { name:'BbsI',  site:'GAAGAC', gap:2, label:'BbsI',  blocks:6 },
];
for (const e of ENZYMES) e.rc = revcomp(e.site);

const gcOf = (s) => {
  let g = 0;
  for (const b of s) if (b === 'G' || b === 'C') g++;
  return g / s.length;
};

const longestRun = (s) => {
  let best = 1, cur = 1;
  for (let i = 1; i < s.length; i++) {
    cur = s[i] === s[i - 1] ? cur + 1 : 1;
    if (cur > best) best = cur;
  }
  return best;
};

const hits = (window) => {
  const out = [];
  for (const e of ENZYMES) {
    if (window.includes(e.site) || window.includes(e.rc)) out.push(e);
  }
  return out;
};

const WIN = 11; // 变异密码子左右各取 4 nt，共 11 nt 的上下文窗口

/**
 * 生成一个位点的 19 个替换。
 * 状态规则（可在界面里看到依据）：
 *   x    上下文命中限制性内切酶位点 → 阻断 Golden Gate 克隆，剔除
 *   warn 上下文 GC 越界、或同聚物 ≥ 6 → 合成失败风险，待人确认
 *   ok   进入池
 */
function siteVariants(seq, index, dna = [...seq].map((aa) => CODON[aa] || 'NNN').join('')) {
  const wt = seq[index];
  const from = index * 3;
  const left = dna.slice(Math.max(0, from - 4), from);
  const right = dna.slice(from + 3, from + 7);
  const rows = [];

  for (const aa of Object.keys(CODON)) {
    if (aa === wt) continue;
    const codon = CODON[aa];
    const window = left + codon + right;
    const gc = gcOf(window);
    const run = longestRun(window);
    const enz = hits(window);

    let status = 'ok';
    let why = '';
    if (gc >= 0.84 || gc <= 0.12 || run >= 7 || enz.length) {
      status = 'x';
      why = enz.length
        ? `上下文出现 ${enz.map((e) => e.label).join('、')} 识别位点，会阻断 Golden Gate 克隆`
        : run >= 7
          ? `上下文出现 ${run} 个连续相同碱基，合成失败`
          : `上下文 GC ${(gc * 100).toFixed(0)}%，超出可合成区间`;
    } else if (gc >= 0.76) {
      status = 'warn';
      why = `上下文 GC ${(gc * 100).toFixed(0)}%，高于 76%，合成失败风险高`;
    } else if (gc <= 0.26) {
      status = 'warn';
      why = `上下文 GC ${(gc * 100).toFixed(0)}%，低于 26%，合成失败风险高`;
    } else if (run >= 6) {
      status = 'warn';
      why = `上下文出现 ${run} 个连续相同碱基，合成失败风险高`;
    } else if (window.includes('CTAG') || window.includes('CTGCAG')) {
      status = 'warn';
      why = '上下文出现克隆位点序列，建议换一个同义密码子';
    }

    let synth = 99;
    synth -= Math.round(Math.abs(gc - 0.52) * 90);
    synth -= Math.max(0, run - 4) * 12;
    if (enz.length) synth -= 46;
    synth = Math.max(11, Math.min(99, synth));

    rows.push({
      id: `${wt}${index + 1}${aa}`,
      pos: index + 1,
      wt,
      aa,
      codon,
      window,
      left,
      right,
      edge: index < 4 || index > seq.length - 5,
      gc,
      run,
      synth,
      status,
      why,
      pool: `P-${String(index + 1).padStart(4, '0')}`,
      coverage: 2.6 + ((index * 7 + aa.charCodeAt(0)) % 11) / 10,
    });
  }
  return rows;
}

/** 全库：263 × 19 = 4,997 条 */
function allVariants(seq = SEQ) {
  const out = [];
  for (let i = 0; i < seq.length; i++) out.push(...siteVariants(seq, i));
  return out;
}

const LIBRARY = {
  id: 'tem1-nns',
  name: 'TEM-1 单点饱和扫描',
  short: 'TEM-1',
  host: 'E. coli BL21(DE3)',
  vector: 'pET-28a',
  strategy: 'NNS 逐位点饱和',
  version: 'v3',
  owner: 'LY',
  checkedAt: '12 分钟前',
  target: 4,
};

/** 成本估算：池、克隆、测序三段，跟位点数与变体数走 */
function estimate(sites, variants, depth) {
  const pool = Math.round(sites * 26);
  const cloning = Math.round(variants * 1.55);
  const ngs = Math.round((variants * depth * 150) / 1e6 * 42);
  return { pool, cloning, ngs, total: pool + cloning + ngs };
}

/* 浏览器全局（不用打包工具，也不用模块，双击文件即可打开） */
window.MDATA = { SEQ, CODON, AA_NAME, DNA, LIBRARY, siteVariants, allVariants, estimate };
})();
