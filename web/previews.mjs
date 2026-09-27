import { spellIcons, glyphs } from "./icon-map.mjs";
// Spell identities come from RikUI’s catalogue; textures are decoded from the installed client.
export const iconBase = "/assets/forever-20260927/";
const art = Object.fromEntries(Object.entries(spellIcons).map(([name, icon]) => [name, icon.path]));
Object.assign(art, { Hearthstone: iconBase+"inv_misc_rune_01.png" });
export const assetUrls = Object.values(art);
const glyph = (name,x,y,size=14) => glyphs[name].replace("<svg ", '<svg x="'+x+'" y="'+y+'" width="'+size+'" height="'+size+'" ');
const rect = (x, y, w, h, fill = "#101316", stroke = "#3c444e") =>
  '<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" fill="'+fill+'" stroke="'+stroke+'" stroke-width="1"/>';
const text = (x, y, value, fill = "#c8c5bc", size = 10, anchor = "start", extra = "") =>
  '<text x="'+x+'" y="'+y+'" fill="'+fill+'" font-size="'+size+'" text-anchor="'+anchor+'" '+extra+'>'+value+'</text>';
function slot(x, y, name, bind = "", size = 30, count = "") {
  if(name && !art[name]) throw new Error("Unknown preview action: "+name);
  return '<g class="game-slot"'+(name?' data-action="'+name+'"':"")+'>'+rect(x,y,size,size)+(name ?
    '<title>'+name+'</title><svg x="'+(x+1)+'" y="'+(y+1)+'" width="'+(size-2)+'" height="'+(size-2)+'" viewBox="5.12 5.12 53.76 53.76"><image href="'+art[name]+'" width="64" height="64"/></svg>' : "")+
    (bind ? text(x+size-2,y+9,bind,"#eee9df",10,"end",'class="outlined"') : "")+
    (count ? text(x+size-2,y+size-2,count,"#eee9df",10,"end",'class="outlined"') : "")+'</g>';
}

const FRAME = { center: 1024, inset: 32, right: 2016, panelWidth: 228, bottom: 1120 };
const COMBAT = { barX: 822, barY: 1000, barWidth: 404, hudX: 910, hudWidth: 228, playerX: 822, targetX: 1048, unitWidth: 178, unitY: 690 };
const group = (name, body) => '<g class="'+name+'">'+body+'</g>';

function player() {
  const x = COMBAT.playerX, y = COMBAT.unitY, w = COMBAT.unitWidth;
  return group("player-frame",
    rect(x,y,w,36)+rect(x,y,w,23,"#ef8fbb","#b97494")+
    text(x+5,y+15,"Boo","#eee",12,"start",'class="outlined"')+
    text(x+w-5,y+15,"212 / 220","#eee",11,"end",'class="outlined"')+
    rect(x,y+23,w,13,"#0800e9","#23294d")+text(x+5,y+33,"10","#eee69a",10)+
    text(x+w-5,y+33,"287 / 287","#eee69a",10,"end"));
}
function target() {
  const x=COMBAT.targetX, y=COMBAT.unitY, w=COMBAT.unitWidth;
  return group("target-frame combat-only",rect(x,y,w,36,"#0b0e11","#a12c27")+
    rect(x+1,y+1,100,22,"#bd4335","none")+
    text(x+5,y+15,"Mangy Wolf","#eee",12,"start",'class="outlined"')+
    text(x+w-5,y+15,"57 / 102","#eee",11,"end",'class="outlined"')+
    text(x+5,y+33,"5","#e9db92",10)+text(x+w-5,y+33,"0 / 0","#aeb4b9",10,"end"))+
    group("target-of-target combat-only",rect(1326,702,88,24)+rect(1326,702,88,15,"#ef8fbb")+
    text(1329,713,"Boo","#eee",10,"start",'class="outlined"')+
    rect(1326,717,88,9,"#0800e9")+text(1411,713,"212 / 220","#eee",8,"end",'class="outlined"'));
}
function combatDetails() {
  return group("combat-details combat-only",
    rect(958,486,138,14,"#101316")+text(1027,497,"Mangy Wolf","#ddd",11,"middle")+
    rect(958,500,116,17,"#101316")+rect(959,501,65,15,"#bd4335","none")+
    text(1016,513,"56%","#eee",11,"middle",'class="outlined"')+
    rect(1074,500,22,17)+text(1085,513,"5","#55bb4a",10,"middle")+
    text(1116,513,"Threat 100%","#ddd",11)+
    rect(944,924,160,14,"#11161a")+rect(945,925,57,12,"#566a7d","none")+
    text(948,934,"Main Hand","#ddd",9)+text(1100,934,"2.2","#ddd",9,"end"));
}
function actionBars() {
  const rows = [
    ["Blessing of Might",null,null,null,"Devotion Aura",null,null,null,null,null,null,null],
    ["Divine Protection",null,"Lay on Hands",null,null,"Blessing of Protection",null,null,null,null,null,null],
    ["Holy Strike","Judgement","Seal of Righteousness",null,null,"Hammer of Justice",null,"Purify","Holy Light",null,"Seal of Righteousness","Hearthstone"],
  ];
  const keys = ["1","2","3","4","5","Q","E","R","F","M4","M5","T"];
  let out = "";
  rows.forEach((row,r) => row.forEach((name,c) => {
    out += slot(COMBAT.barX+c*34,COMBAT.barY+r*34,name,(r===0?"c":r===1?"s":"")+keys[c]);
  }));
  out += rect(COMBAT.barX,1106,COMBAT.barWidth,14,"#090d10")+
    rect(COMBAT.barX,1106,31,14,"#224fad","#567bab")+
    text(FRAME.center,1116,"Level 10   |   XP 2%   |   7421 to level","#c6c8c6",9,"middle");
  return group("action-bars",out);
}
function cooldowns() {
  const x=COMBAT.hudX, y=818;
  return group("cooldowns",["Seal of Righteousness","Judgement","Hammer of Justice","Blessing of Protection","Lay on Hands","Divine Protection","Holy Strike"]
    .map((name,i)=>i===0?'<g class="inactive-seal">'+slot(x+i*33,y,name)+'</g>':slot(x+i*33,y,name)).join("")+
    rect(x,y+34,COMBAT.hudWidth,12,"#0900f1","#263259")+
    text(FRAME.center,y+43,"287 / 287","#fff4b8",10,"middle"));
}
function minimap() {
  const x=FRAME.right-FRAME.panelWidth, y=FRAME.inset, w=FRAME.panelWidth;
  const rooms=[[-28,-24,17,13],[-9,-24,14,17],[9,-24,21,12],[-29,-7,18,19],[-8,-5,20,20],
    [14,-7,22,16],[-25,16,17,13],[-6,18,20,14],[18,14,12,20],[-44,-7,12,11],[35,-21,11,10]];
  return group("minimap",rect(x,y,w,252,"#090c10")+rect(x+2,y+2,w-4,22,"#1a2028")+
    text(x+10,y+17,"!","#a0c6dc")+text(x+25,y+17,"Cathedral of Light","#30e300",11)+
    rect(x+2,y+25,w-4,194,"#000","#10151b")+
    '<g transform="translate('+(x+w/2)+' '+(y+123)+') rotate(-40) scale(1.3)">'+rooms.map(([rx,ry,rw,rh],i)=>
      rect(rx,ry,rw,rh,i%3===0?"#a49a76":"#555b60","#999483")).join("")+
      rect(-6,-3,13,13,"#d8c897","#ede0a6")+'</g>'+
    '<path d="M1902 143l-4 13 10-5z" fill="#57b6e1" stroke="#ddeef6"/>'+
    text(x+w-30,y+137,"!","#ffee00",15,"middle")+
    rect(x+w-60,y+194,52,19,"#17212b","#63a5c7")+text(x+w-34,y+207,"RikUI","#c9c8c3",11,"middle")+
    text(x+8,y+233,"12:07 PM","#c9c8c3",10)+text(x+w-8,y+233,"51.9, 45.5","#c9c8c3",10,"end")+
    text(x+8,y+246,"Day","#8e9aa5",9));
}
function planner(x,y,w) {
  let out=rect(x,y,w,88,"#090e14")+rect(x+2,y+2,w-4,18,"#1b222a")+
    text(x+8,y+15,"Quest planner","#e5ba41",12)+
    text(x+8,y+32,"Quest guidance paused","#8c9eac",10)+text(x+8,y+48,"Paused","#8db5c7",10)+
    rect(x+4,y+56,86,14,"#1b2028")+text(x+8,y+66,"Arrow: off")+
    text(x+98,y+66,"Direction guide","#829dad");
  ["Resume","Map","Pin","Skip","More"].forEach((label,i)=>{
    out+=rect(x+4+i*44,y+72,42,12,"#181c23")+text(x+25+i*44,y+81,label,"#bfc3c9",9,"middle");
  });
  return out;
}
function questTracker() {
  const x=FRAME.right-FRAME.panelWidth, y=300, w=FRAME.panelWidth;
  let out=rect(x,y,w,20,"#1a2028")+text(x+8,y+13,"!   Quests")+
    text(x+w-8,y+13,"6  ⌄","#bfc2c8",10,"end")+planner(x,y+24,w);
  const quests=[
    ["[6] Camping 101: Blacksmithing","– Raise your blacksmithing skill to 20",false],
    ["[15] Elmore’s Task","Ready for turn-in",true],
    ["[10] Westbrook Garrison Needs…","Ready for turn-in",true],
    ["[10] Cloth and Leather Armor","Ready for turn-in",true],
    ["[10] Report to Gryan Stoutmantle","Ready for turn-in",true],
    ["[6] Camping 101: Mining","– Raise your mining skill to 20",false],
  ];
  quests.forEach(([title,detail,done],i)=>{
    const top=424+i*44, color=done?"#32d72d":"#efd100";
    out+=rect(x,top,w,36,"#101315","none")+rect(x,top,2,36,color,"none")+
      text(x+8,top+15,title,color,11)+text(x+16,top+28,detail,done?"#32c52b":"#aaa69a",9);
  });
  return group("quest-tracker",out);
}
function utilityBars() {
  let out="";
  const items={"1:0":"Seal of Fury","1:2":"Seal of the Crusader","1:3":"Holy Strike"};
  for(let col=0;col<2;col++) for(let row=0;row<12;row++)
    out+=slot(1952+col*34,716+row*34,items[col+":"+row],"",30);
  return group("utility-bars",out);
}
function meter() {
  const x=1624,y=936,w=312;
  let out=rect(x,y,w,128,"#090b0d","#292c30")+rect(x,y,w,24,"#19222c")+
    text(x+8,y+16,"⌄  Damage Done","#efd300",11)+text(x+w-53,y+16,"0","#efd300",11,"end")+glyph("settings",x+w-38,y+5,14)+glyph("minus",x+w-17,y+5,14)+
    rect(x+4,y+28,w-8,14,"#82616f","#42404a")+rect(x+4,y+28,234,14,"#c183a0","none")+
    slot(x+5,y+28,"Judgement","",14)+text(x+24,y+39,"1. Boo","#ded6dc",11,"start",'class="outlined"')+
    text(x+w-8,y+39,"12,135 (10.8)","#ded6dc",11,"end",'class="outlined"')+
    rect(x,1076,w,16,"#0d1215")+text(x+w/2,1087,"17 free (+1 special)","#8eb68c",9,"middle");
  ["character","profession","spellbook","talents","legacy","quest","guild","groupfinder","collections","store"].forEach((name,i)=>{
    out+=rect(1740+i*20,1104,16,16,"#12171d")+glyph(name,1742+i*20,1106,12);
  });
  return group("damage-meter",out);
}
function chat() {
  const x=FRAME.inset,y=936,w=356;
  let out=rect(x,y+24,w,136,"#101515","#3a403f")+rect(x,y,54,18,"#111615","#dbb848")+
    text(x+5,y+13,"General","#e5c646",10)+rect(x+62,y,76,18,"#111615","#303329")+
    text(x+67,y+13,"Combat Log","#a38328",10);
  const messages=[
    ["RikUI: Welcome back, Boo.","#d7bf6e"],["RikUI: Profile loaded. Your interface is ready.","#bdc8d0"],
    ["RikUI: Use /rik move to arrange your frames.","#bdc8d0"],["RikUI: Use /rik config to choose your modules.","#bdc8d0"],
    ["12:07 [Quest] Elmore’s Task is ready for turn-in.","#51c941"],
    ["12:07 [Quest] Cloth and Leather Armor is ready for turn-in.","#51c941"],
    ["12:07 [System] You are now rested.","#e2cf51"],
  ];
  messages.forEach(([s,c],i)=>out+=text(x+6,y+39+i*13,s,c,9));
  ["S","Y","G","W"].forEach((s,i)=>out+=rect(x+4+i*20,1076,16,16)+
    text(x+12+i*20,1088,s,["#d4b874","#e78f4d","#44c24c","#b976d3"][i],9,"middle"));
  return group("chat-panel",out+rect(x,1100,w,20,"#111515","#686967"));
}
export const scene = '<svg class="game-scene" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2048 1152" role="img" aria-labelledby="scene-title scene-description">'+
  '<title id="scene-title">RikUI paladin interface mockup over the Cathedral of Light</title>'+
  '<desc id="scene-description">A real in-game screenshot behind an aligned UI mockup. The player frame is left of center, with a separate target frame to its right in combat. Cooldowns and action rows stay centered. The minimap and quests share a right column; chat, utility bars and experience share a bottom edge. Blizzard game artwork; sample interface content.</desc>'+
  '<image class="world-backdrop" href="/assets/world-20260927-120706.jpg" x="0" y="0" width="2048" height="1152"/>'+
  '<rect class="world-shade" width="2048" height="1152" fill="#0a0c10" opacity=".18"/>'+
  group('ui-overlay',player()+target()+combatDetails()+cooldowns()+actionBars()+minimap()+questTracker()+utilityBars()+meter()+chat())+'</svg>';
