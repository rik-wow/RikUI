export const styles = `
:root{color-scheme:dark;--background:#171918;--text:#e6e4dc;--muted:#b2b6ad;--line:#42463f;--link:#e2c580}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:24px}
body{margin:0;background:var(--background);color:var(--text);font:16px/1.6 "Segoe UI",Arial,sans-serif}
a{color:var(--link);text-underline-offset:4px;text-decoration-thickness:1px}
a:hover{color:#fff0c5}
button{font:inherit;color:inherit;cursor:pointer}
button:focus-visible,a:focus-visible{outline:2px solid var(--link);outline-offset:4px}
h1,h2,h3,p,dl,dd{margin:0}
h1,h2,h3{font-weight:600;line-height:1.25}
h1{font-size:32px;letter-spacing:-.6px}
h2{font-size:23px;margin-bottom:14px}
h3{font-size:17px;margin-top:26px;margin-bottom:12px}
code{font:14px ui-monospace,Consolas,monospace;color:#e0d5b9}
[hidden]{display:none!important}
.wrap{width:calc(100% - 80px);max-width:1440px;margin-inline:auto}
.skip{position:absolute;top:10px;left:10px;z-index:10;padding:8px 16px;background:var(--link);color:#151713;clip-path:inset(50%)}
.skip:focus{clip-path:none}
#main:focus{outline:none}
.site-header{display:flex;align-items:center;justify-content:space-between;gap:24px;height:76px;border-bottom:1px solid var(--line)}
.brand{font-size:25px;font-weight:700;letter-spacing:-.8px;color:#e6e4dc;text-decoration:none}
.site-header nav{display:flex;gap:30px;font-size:14px}
.site-header nav a{color:#d1d4ca;text-decoration:none}
.site-header nav a:hover{color:var(--link);text-decoration:underline}
.intro{display:flex;align-items:center;justify-content:space-between;gap:32px;padding-block:35px 29px}
.intro p{font-size:15px;line-height:1.7;color:var(--muted);margin-top:12px}
.install-link{flex-shrink:0;display:block;padding:9px 18px;border:1px solid #918361;background:#292c24;font-size:14px;text-decoration:none}
.install-link:hover{background:#35392d}
.showcase{margin-bottom:48px}
.preview-stage{background:#111310;border:1px solid #4d5148;overflow:hidden}
.game-scene{display:block;width:100%;height:auto;aspect-ratio:16/9;font-family:Arial,Helvetica,sans-serif;letter-spacing:.2px}
.game-scene .outlined{paint-order:stroke;stroke:#101010;stroke-width:2;stroke-linejoin:round}
.preview-stage[data-view=quests]{border:0;background:none}
.preview-stage[data-view=quests] .game-scene{aspect-ratio:3/4;max-width:540px;margin-inline:auto;border:1px solid #4d5148}
.ui-overlay{display:inline}
.overlay-hidden .ui-overlay{display:none}
.preview-toolbar{display:none;align-items:center;justify-content:space-between;gap:20px;margin-top:8px;border-bottom:1px solid var(--line)}
.enhanced .preview-toolbar{display:flex}
.preview-controls{display:flex;gap:24px}
.preview-controls button{border:0;border-bottom:2px solid transparent;background:none;padding:10px 0;font-size:14px;color:#b5bab0}
.preview-controls button[aria-pressed=true]{color:#f1dfac;border-bottom-color:var(--link)}
.preview-controls button:hover{color:#f1dfac}
.overlay-control{background:none;border:1px solid #626956;padding:4px 10px;font-size:12px}
.overlay-control[aria-pressed=true]{color:#ecdfb9}
.overlay-control[aria-pressed=false]{color:#b5bab0;border-style:dashed}
.view-description{font-size:14px;color:#c2c7b9;margin-top:14px}
.preview-caption{font-size:12px;color:#a5ad9d;margin-top:4px;max-width:1050px}
.preview-caption a{color:#cfc5ac}
.no-script{font-size:14px;padding-top:10px}
.project-info{display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr);gap:80px;padding-top:30px;padding-bottom:48px;border-top:1px solid var(--line)}
.project-info section>p{font-size:15px;color:var(--muted);margin-bottom:15px}
.module-list{margin-top:22px;margin-bottom:18px}
.module-list>div{display:grid;grid-template-columns:124px minmax(0,1fr);gap:14px;padding-block:13px;border-bottom:1px solid #33392f}
.module-list>div:first-child{padding-top:0}
.module-list>div:last-child{border-bottom:0}
.module-list dt{font-size:15px;font-weight:500}
.module-list dd{font-size:14px;color:var(--muted)}
.all-docs{font-size:14px}
.commands{margin-bottom:22px}
.commands>div{display:grid;grid-template-columns:116px minmax(0,1fr);gap:12px;padding-block:5px}
.commands dd{font-size:14px;color:#c2c7b9}
.project-info section>p.binding-note{font-size:13px;line-height:1.7;color:#abb3a2}
footer{border-top:1px solid var(--line);padding-top:24px;padding-bottom:30px}
.footer-links{display:flex;gap:26px;align-items:center;font-size:13px}
.footer-links>span{font-size:18px;font-weight:600;margin-right:auto}
#asset-notice{font-size:12px;line-height:1.75;color:#a8afa0;max-width:1120px;margin-top:20px}
#asset-notice a{color:#cfc5ac}
@media(max-width:1100px){.wrap{width:calc(100% - 48px)}.project-info{gap:44px}.intro{gap:24px}.intro h1{font-size:29px}.intro p{font-size:14px}.desktop-break{display:none}}
@media(max-width:780px){.site-header nav{gap:20px}.intro{align-items:start;flex-direction:column;gap:18px;padding-block:28px}.project-info{gap:34px;grid-template-columns:1fr}.module-list>div{grid-template-columns:136px minmax(0,1fr)}.showcase{margin-bottom:32px}.install-link{padding:8px 14px}.preview-caption{font-size:11px}.view-description{font-size:13px}}
@media(max-width:480px){.wrap{width:calc(100% - 32px)}.site-header{height:65px;gap:15px}.brand{font-size:23px}.site-header nav{gap:14px;font-size:12px}.site-header nav a:nth-child(2){display:none}h1,.intro h1{font-size:26px}h2{font-size:22px}.intro{padding-block:24px}.intro p{font-size:14px}.preview-toolbar{gap:10px;flex-wrap:wrap;padding-bottom:10px}.preview-controls{gap:22px;width:100%}.preview-controls button{font-size:13px;min-height:44px}.overlay-control{font-size:12px;min-height:32px}.view-description{margin-top:12px}.preview-caption{line-height:1.65}.module-list>div{grid-template-columns:1fr;gap:3px;padding-block:14px}.module-list dd{font-size:14px}.project-info{padding-top:24px;padding-bottom:25px}.commands>div{grid-template-columns:105px minmax(0,1fr);gap:8px}.commands code{font-size:13px}.commands dd{font-size:13px}.footer-links{font-size:12px;gap:20px}.footer-links>span{font-size:17px}#asset-notice{font-size:11px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
`;
