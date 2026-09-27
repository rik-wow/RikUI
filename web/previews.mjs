// Website illustrations follow RikUI's documented composition, not game screenshots.
const shapes = {
  spell: '<path d="M4 5.5C6.5 4.7 9.5 5 12 6.5C14.5 5 17.5 4.7 20 5.5V18.5C17.5 17.7 14.5 18 12 19.5C9.5 18 6.5 17.7 4 18.5Z"/><path d="M12 6.5V19.5"/>',
  quest: '<path d="M12 3.5V14" stroke-width="3.2"/><circle cx="12" cy="19.2" r="1.9" fill="currentColor" stroke="none"/>',
  settings: '<path d="M4 7H20M4 12H20M4 17H20"/><circle cx="9" cy="7" r="2.6"/><circle cx="15.5" cy="12" r="2.6"/><circle cx="8" cy="17" r="2.6"/>',
  spark: '<path d="m13 2-9 12h7l-1 8 10-13h-7z"/>',
  shield: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z"/><path d="m8 12 3 3 5-6"/>',
  cross: '<path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"/>',
  target: '<circle cx="12" cy="12" r="7"/><path d="M12 1v6m0 10v6M1 12h6m10 0h6"/>',
  arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
};
export function icon(name) {
  return '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' + shapes[name] + '</svg>';
}
export const mark = '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none"><path d="M5 27V5h14l8 8-8 7H12m5 0 10 7" stroke="currentColor" stroke-width="4"/><path d="M5 5v7h7" stroke="#0c1016" stroke-width="2"/></svg>';
const slots = Array.from({length:12}, (_, i) => '<span class="slot tone-' + i % 4 + '"><kbd>' + ['1','2','3','4','5','Q','E','R','F','T','G',''][i] + '</kbd>' + icon(['spark','shield','target','cross','spell','spark'][i%6]) + '</span>').join('');
const cooldowns = ['spark','shield','target','spell','cross','spark'].map((name,i) => '<span class="cooldown tone-' + i%4 + '">' + icon(name) + (i===1?'<b>8</b>':i===3?'<b>24</b>':'') + '</span>').join('');
const miniMap = '<svg viewBox="0 0 160 100" aria-hidden="true"><path d="M0 45 28 55 50 28 91 35 110 15 160 30M60 0 53 38 70 70 55 100" fill="none" stroke="#3b4650" stroke-width="9"/><path d="m75 59 18-23 27 4" fill="none" stroke="#e3c684" stroke-dasharray="3 4"/><path d="m75 52 5 13-5-3-5 3z" fill="#e3c684"/><circle cx="120" cy="40" r="4" fill="#e3c684"/><path d="M12 13h22v15H12zM107 63h28v19h-28z" fill="#25323a"/></svg>';
export const combat = `<div class="combat-scene" role="img" aria-label="Illustrated RikUI layout: party on the left, minimap and quests on the right, cooldowns and resources above centered action bars. Sample values.">
<div class="scene-label">CENTERED LAYOUT <span>PREVIEW</span></div>
<div class="party-panel"><div class="tiny-title">PARTY</div>${['You','Tank','Healer','Party member','Party member'].map((name,i)=>'<div class="party-unit party-'+i+'"><span>'+name+'</span><i></i></div>').join('')}</div>
<div class="minimap-panel"><div class="tiny-title">${icon('target')} MINIMAP <span>N</span></div>${miniMap}<div class="map-footer">12:40 <span>RikUI</span></div></div>
<div class="quest-mini"><div class="tiny-title">${icon('quest')} QUEST TRACKER</div><b>Current objective</b><p>Collect supplies <span>4 / 6</span></p><div class="mini-track"><i></i></div><small>Guidance when data is available</small></div>
<div class="world-center"><div class="crosshair"></div><span>ROOM FOR THE WORLD</span></div>
<div class="unit-pair"><div class="unit"><div><b>You</b><span>60</span></div><i class="health"></i><i class="mana"></i></div><div class="unit enemy"><div><b>Target</b><span>60</span></div><i class="health"></i><i class="mana"></i></div></div>
<div class="hud-stack"><span class="hud-caption">COOLDOWNS</span><div class="cooldown-row">${cooldowns}</div><div class="resource"><i></i><span>RESOURCE</span></div><div class="cast"><i></i><span>Cast / channel</span><b>1.2</b></div><div class="swing"><i></i><span>WEAPON TIMING</span></div></div>
<div class="chat-panel"><div class="tiny-title"><b>General</b><span>Guild</span><span>Combat</span></div><p><em>[Guild]</em> Ready when you are.</p><p><em>[Party]</em> One more quest?</p><p class="muted">Your channels. Your corner.</p><div class="chat-input">Say…</div></div>
<div class="action-stack"><div class="action-row secondary">${slots}</div><div class="action-row">${slots}</div><div class="xp-line"><i></i><span>EXPERIENCE</span></div></div>
<div class="scene-tag tag-one"><b>01</b> Combat in one place</div><div class="scene-tag tag-two"><b>02</b> The details, at the edges</div>
</div>`;
export const quests = `<div class="quest-scene">
<div class="demo-window quest-window"><div class="window-title">${icon('quest')} <b>Quest planner</b><span>RikUI</span></div>
<div class="planner-body"><div class="quest-list"><div class="tiny-title">YOUR NEXT OBJECTIVE</div><div class="selected-quest"><span class="quest-symbol">!</span><div><b>Collect supplies</b><small>Example objective · 4 / 6</small></div></div><div class="list-heading">QUEST LOG</div><div class="quest-list-row"><span>◇</span> Explore the area</div><div class="quest-list-row"><span>?</span> Return to the quest giver</div><div class="quest-list-row"><span>!</span> Gather materials</div><div class="coverage-note"><i></i> Partial quest data<br><small>Unknown coverage stays visible.</small></div></div>
<div class="route-map"><span class="map-legend">OBJECTIVE MAP · ILLUSTRATION</span><svg viewBox="0 0 500 350" aria-label="Schematic route between three example objectives">
<g fill="none" stroke="#2b3741" stroke-width="1"><path d="M0 60 110 95 170 30 230 65 350 20 500 50M0 120 100 140 180 85 250 130 360 70 500 105M0 260 95 200 200 245 260 170 370 205 500 145M0 310 115 260 205 300 300 235 400 255 500 215"/><path d="m90 0 30 100-35 75 60 175m180-350-40 90 35 80-10 180m125-350-25 90 35 160-45 100"/></g>
<path d="m130 265 32-48 66-20 58-82 95 30" fill="none" stroke="#dfbf7a" stroke-width="3" stroke-dasharray="6 5"/>
<g fill="#10161e" stroke="#dfbf7a" stroke-width="2"><circle cx="130" cy="265" r="12"/><circle cx="228" cy="197" r="12"/><circle cx="286" cy="115" r="12"/><circle cx="381" cy="145" r="12"/></g>
<g fill="#f0d797" font-size="12" text-anchor="middle" font-family="Arial"><text x="130" y="270">↑</text><text x="228" y="201">1</text><text x="286" y="119">2</text><text x="381" y="149">?</text></g>
<g fill="#aebbc6" font-size="12" font-family="Arial"><text x="100" y="300">YOU</text><text x="208" y="235">OBJECTIVE</text><text x="339" y="185">TURN IN</text></g></svg><div class="map-bottom"><span>● Current objective</span><span>◇ Supporting data required</span></div></div></div>
<div class="window-footer"><span>Pin · Skip · Avoid · Pause</span><code>/rik quests show</code></div></div></div>`;
export const setup = `<div class="setup-scene"><div class="demo-window setup-window">
<div class="window-title">${icon('settings')} <b>Make yourself at home</b><span>RikUI setup</span></div>
<div class="setup-body"><div class="step-rail"><span>01 <b>Preset</b></span><span>02 <b>Customize</b></span><span class="current">03 <b>Review</b></span></div>
<div class="review-body"><div class="tiny-title">YOU DECIDE WHAT CHANGES</div><h3>A setup that starts with you.</h3><p>Review the parts you want to apply.</p>
<div class="review-rows"><div><span class="checkmark">✓</span><b>Interface layout</b><span>Centered</span></div><div><span class="checkmark">✓</span><b>Action bars &amp; macros</b><span>Class preset</span></div><div><span class="checkmark empty"></span><b>Keybindings</b><span>Keep existing</span></div><div><span class="checkmark empty"></span><b>Game settings</b><span>Keep existing</span></div></div>
<div class="undo-note">${icon('shield')} Changed your mind? <code>/rik undo</code></div></div></div><div class="window-footer"><span>Illustrated review screen</span><code>/rik setup</code></div></div></div>`;
export const viewDetails = {
  combat: ['01 / COMBAT HUD', 'Keep your eyes\non the fight.', 'Cooldowns, resources, casts and weapon timing share one central stack. Supporting frames sit close by.', [['01','One cooldown strip','Client entries and RikUI’s learned class list, together.'],['02','Your layout','Move and scale frames. Start with one of four presets.']], '/rik hud','combat-hud.md'],
  quests: ['02 / QUEST PLANNING', 'A next step\nyou can see.', 'Quest tracking, objective markers and route guidance work together wherever supporting data is available.', [['01','Control the plan','Pin, skip, avoid or pause from the planner.'],['02','Honest coverage','Missing data stays visible. Unverified paths aren’t presented as known routes.']], '/rik quests show','questplanner.md'],
  setup: ['03 / SETUP & CONTROL', 'Settle in.\nMake it yours.', 'Choose a preset, review changes and apply only the parts you want. Keep the rest of your setup.', [['01','Four starting points','Centered, Classic, HUD and Healer.'],['02','Built-in undo','Restore the last setup’s bars, macros, binds, settings and positions.']], '/rik setup','wizard.md'],
};
export function inspector(name) {
  const [label,title,description,items,command,doc] = viewDetails[name];
  const zoom = name === 'combat' ? '<button class="zoom-preview" type="button" aria-pressed="false">Enlarge combat HUD <span aria-hidden="true">⤢</span></button>' : '';
  return '<aside class="inspector"><span class="eyebrow">'+label+'</span><h3>'+title.replace('\n','<br> ')+'</h3><p>'+description+'</p>'+zoom+'<ol>'+items.map(([n,t,d])=>'<li><span>'+n+'</span><div><b>'+t+'</b><p>'+d+'</p></div></li>').join('')+'</ol><div class="command"><span>IN GAME</span><code>'+command+'</code></div><a class="detail-link" href="https://github.com/rik-wow/RikUI/blob/main/docs/'+doc+'">Read the feature guide '+icon('arrow')+'</a></aside>';
}
