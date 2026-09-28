export const docsStyles = `
.docs-layout{display:grid;grid-template-columns:208px minmax(0,1fr) 170px;gap:36px;align-items:start;padding-block:36px 70px}
.docs-layout main{min-width:0;max-width:880px}
.docs-sidebar,.docs-toc{position:sticky;top:24px;max-height:calc(100vh - 48px);overflow:auto;scrollbar-width:thin;padding-right:12px}
.docs-sidebar label{display:block;font-size:13px;color:#c9cebf;margin-bottom:8px}
.docs-sidebar input{width:100%;font:14px "Segoe UI",sans-serif;border:1px solid #505849;color:var(--text);background:#101410;padding:10px 9px;border-radius:0}
.docs-sidebar input:focus-visible{outline:2px solid var(--link);outline-offset:3px}
.docs-nav-toggle>summary{display:none}
.nav-group{margin-top:24px}
.nav-group h2,.docs-toc h2{font-size:12px;line-height:1.5;font-weight:600;color:#a6af9d;margin:0 0 7px}
.nav-group a,.docs-toc a{display:block;text-decoration:none;font-size:13px;line-height:1.55;padding:5px 8px;color:#bec8b4;border-left:2px solid transparent}
.nav-group a:hover,.docs-toc a:hover{color:#f3ddb0;background:#20261d}
.nav-group a[aria-current=page]{border-color:#dfc17b;color:#edd8a6;background:#272d22}
.docs-toc a{font-size:12px;padding-block:4px}
.docs-toc .toc-depth-3{padding-left:18px}
.doc-breadcrumb{font-size:12px;color:#97a38d;margin-bottom:14px;display:flex;gap:10px}
.docs-page h1{font-size:34px;line-height:1.2;letter-spacing:-.6px;margin-bottom:16px}
.doc-lead{font-size:17px;line-height:1.7;color:#c0c8b6;max-width:70ch;margin-bottom:24px}
.doc-setting,.doc-note{font-size:13px;border-left:2px solid #8b815b;padding:10px 15px;background:#1d221a;color:#b7c3ab;margin-block:20px}
.docs-page h2{margin-top:40px;font-size:23px}
.docs-page h3{margin-top:28px;font-size:18px}
.docs-page .nav-group h2,.docs-page .docs-toc h2{font-size:12px;line-height:1.5;margin:0 0 7px}
@media(min-width:1100px){.example-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}

.doc-prose{font-size:15px;line-height:1.85;overflow-wrap:anywhere}
.doc-prose p,.doc-prose ul,.doc-prose ol,.doc-prose blockquote{margin-block:16px}
.doc-prose li{margin-block:6px}
.doc-prose ul,.doc-prose ol{padding-left:24px}
.doc-prose pre{background:#0f140e;border:1px solid #394133;padding:18px;overflow:auto;max-width:100%;line-height:1.65;white-space:pre}
.doc-prose pre code{font-size:12px;color:#ced7c4}
.doc-prose :not(pre)>code{font-size:.9em;background:#232a1e;padding:2px 4px}
.doc-prose blockquote{border-left:2px solid #83754f;margin-left:0;padding-left:18px;color:#b9c4ad}
.doc-prose table{display:block;width:100%;max-width:100%;overflow:auto;border-collapse:collapse;font-size:13px;line-height:1.65;margin-block:22px}
.doc-prose th,.doc-prose td{border:1px solid #414937;padding:9px 12px;text-align:left;min-width:110px}
.doc-prose th{background:#252c20;color:#ddcfac}
.doc-prose img{max-width:100%;height:auto}
.doc-source{border-top:1px solid var(--line);padding-top:20px;margin-top:40px;font-size:13px}
.doc-prose .example-grid{margin-block:18px 28px}
.example-grid{display:grid;grid-template-columns:1fr;gap:24px}

.example-grid figure:is([data-kind=window],[data-kind=map],[data-kind=planner],[data-kind=bags],[data-kind=settings],[data-kind=wizard],[data-kind=auction]){grid-column:1/-1}
.example-grid figure[data-wide=true]{grid-column:1/-1}
.example-grid figure[data-render][data-wide=false]{grid-column:auto}
.example-grid figure[data-render] img{width:auto;max-width:100%;margin-inline:auto}
.enlarge-example{display:block}
.enlarge-example:focus-visible{outline:2px solid var(--link);outline-offset:3px}
.example-grid figure{margin:0;min-width:0;border:1px solid #3c4533;background:#0c1117}
.ui-example{width:100%;height:auto;display:block}
.example-grid figcaption{display:flex;justify-content:space-between;gap:14px;align-items:baseline;padding:11px 14px;background:#1c2218;border-top:1px solid #394232}
.example-grid figcaption strong{font-size:13px;font-weight:500}
.example-grid figcaption span{color:#9cab90;font-size:11px;text-align:right}
.preview-frames{position:relative}
.preview-control{display:flex;align-items:center;gap:10px;flex:1;justify-content:center;font-size:12px;color:#d3d8dd}
.preview-control[hidden]{display:none}
.preview-control input[type=range]{width:min(180px,40vw);accent-color:#c9a648}
.preview-control input[type=checkbox]{width:16px;height:16px;accent-color:#c9a648}
.preview-control select{background:#0c1117;color:#d3d8dd;border:1px solid #46515e;padding:3px 6px;font:inherit}
.preview-control output{min-width:3.5em;font-variant-numeric:tabular-nums;color:#e4c267}
.docs-start{display:flex;flex-wrap:wrap;gap:12px 24px;padding-block:20px;border-block:1px solid var(--line);font-size:14px}
.guide-group h3{color:#aebb9f;font-size:14px;letter-spacing:0;margin-top:32px}
.guide-group dl>div{display:grid;grid-template-columns:170px minmax(0,1fr);gap:20px;padding-block:14px;border-bottom:1px solid #333c2c}
.guide-group dt{font-size:15px}
.guide-group dd{font-size:13px;color:#b2bfa5;line-height:1.75}
.guide-group p{font-size:14px;color:#afbc9f;margin-bottom:18px}
.reference-list{padding-left:18px;font-size:13px;columns:2;column-gap:24px}
.reference-list li{break-inside:avoid;margin-bottom:10px}
#search-empty{font-size:13px;padding-block:16px;color:#c8b894}
.docs-page footer>p:first-child{font-size:13px}
@media(min-width:1650px){.docs-layout{grid-template-columns:220px minmax(0,1fr) 180px;gap:42px}}
@media(max-width:1200px){.docs-layout{grid-template-columns:190px minmax(0,1fr);gap:30px}.docs-toc{display:none}}
@media(max-width:780px){.docs-layout{display:block;padding-top:20px}.docs-sidebar{position:static;max-height:none;padding:0;margin-bottom:28px}.docs-nav-toggle>summary{display:block;cursor:pointer;font-size:14px;color:var(--link);border-bottom:1px solid var(--line);padding:8px 0 12px}.docs-nav-toggle .nav-content{max-height:60vh;overflow:auto;padding-block:14px}.docs-sidebar input{max-width:420px}.docs-page h1{font-size:29px}.doc-lead{font-size:16px}.reference-list{columns:1}.docs-layout main{max-width:100%}.docs-page .site-header nav a:nth-child(2){display:inline}}
@media(max-width:480px){.docs-page h1{font-size:26px}.docs-page h2{font-size:21px;margin-top:30px}.doc-prose{font-size:14px}.doc-lead{font-size:15px}.guide-group dl>div{grid-template-columns:1fr;gap:4px}.example-grid figcaption{display:block;padding:9px 12px}.example-grid figcaption span{display:block;text-align:left;margin-top:3px}.docs-start{gap:12px 20px;font-size:13px}.doc-prose pre{padding:12px}.docs-page .site-header nav{gap:10px;font-size:11px}}
@media print{.site-header,.docs-sidebar,.docs-toc,.doc-source,footer{display:none}.docs-layout{display:block;width:100%;padding:0}.docs-page{background:white;color:#111}.doc-prose,.doc-lead{color:#111}.ui-example{max-height:230px}.example-grid figure:is([data-kind=window],[data-kind=map],[data-kind=planner],[data-kind=bags],[data-kind=settings],[data-kind=wizard],[data-kind=auction]){grid-column:1/-1}
.enlarge-example{display:block}
.enlarge-example:focus-visible{outline:2px solid var(--link);outline-offset:3px}
.example-grid figure{break-inside:avoid}a{color:inherit}}
`;
