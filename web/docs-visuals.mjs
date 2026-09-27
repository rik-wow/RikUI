import { iconBase } from "./previews.mjs";
import { spellIcons, glyphs, mapTiles } from "./icon-map.mjs";
export const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c]));
const R=(x,y,w,h,fill="#10151b",edge="#46515e")=>'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" fill="'+fill+'" stroke="'+edge+'"/>';
const T=(x,y,t,color="#d3d8dd",size=15,anchor="start")=>'<text x="'+x+'" y="'+y+'" fill="'+color+'" font-size="'+size+'" text-anchor="'+anchor+'">'+escapeHTML(t)+'</text>';
const items = { "Hearthstone": "inv_misc_rune_01", "Minor Healing Potion": "inv_potion_49" };
const I=(x,y,name,size=38)=>{
 if(!name)return R(x,y,size,size);
 const path=spellIcons[name]?.path || (items[name] && iconBase+items[name]+".png");
 if(!path)throw Error("Missing named documentation icon: "+name);
 return '<g data-action="'+escapeHTML(name)+'"><title>'+escapeHTML(name)+'</title>'+R(x,y,size,size)+'<svg x="'+(x+1)+'" y="'+(y+1)+'" width="'+(size-2)+'" height="'+(size-2)+'" viewBox="5.12 5.12 53.76 53.76"><image href="'+path+'" width="64" height="64"/></svg></g>';
};
const G=(x,y,name,size=20)=>glyphs[name].replace("<svg ", '<svg x="'+x+'" y="'+y+'" width="'+size+'" height="'+size+'" ');
const actions=["Holy Strike","Judgement","Seal of Righteousness",null,null,"Hammer of Justice",null,"Purify","Holy Light",null,"Seal of Righteousness","Hearthstone"];
const buffs=["Blessing of Might","Devotion Aura","Seal of Righteousness","Blessing of Protection"];
const totems=["Searing Totem","Strength of Earth Totem","Healing Stream Totem","Windfury Totem"];
const mapArt=(x,y,w,h)=>'<svg x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" viewBox="0 0 1002 668">'+mapTiles.map((href,i)=>'<image href="'+href+'" x="'+(i%4*256)+'" y="'+(Math.floor(i/4)*256)+'" width="256" height="256"/>').join("")+'</svg>';
const B=(x,y,w,label)=>R(x,y,w,28,"#202832")+T(x+w/2,y+19,label,"#d5d9df",13,"middle");
const bar=(x,y,w,label,value,color="#5485af",ratio=.65)=>R(x,y,w,25)+R(x+1,y+1,(w-2)*ratio,23,color,"none")+T(x+7,y+18,label,"#fff",13)+T(x+w-7,y+18,value,"#fff",13,"end");
const rows=(names,x=190,y=142,w=340)=>names.map((name,i)=>R(x,y+i*30,w,27,i===0?"#263440":"#131b22")+T(x+10,y+19+i*30,name,"#d4d8de",13)).join("");
const window=(title,body)=>'<g transform="translate(-50 0)">'+R(125,38,550,280)+R(126,39,548,38,"#1a222c","none")+T(143,64,title,"#e4c267",17)+R(142,79,480,1,"#8e7644","none")+G(640,47,"close",19)+body+'</g>';
function unit(title,index){
 const colors=["#ef8fbb","#bd4335","#ef8fbb","#65ad66","#bb845e"];
 const one=(x,y,w,label,c)=>bar(x,y,w,label,label==="Mangy Wolf"?"57 / 102":"212 / 220",c,label==="Mangy Wolf"?.56:.964)+R(x,y+25,w,12,label==="Mangy Wolf"?"#10151b":"#1313bb")+T(x+w-4,y+35,label==="Mangy Wolf"?"0 / 0":"287 / 287","#e4e8ff",9,"end");
 if(title==="Raid grid")return Array.from({length:20},(_,i)=>one(150+(i%5)*83,79+Math.floor(i/5)*50,78,["Rik","Mira","Rin","Ash","Vale"][i%5],colors[i%5])).join("");
 if(title==="Party")return Array.from({length:4},(_,i)=>one(245,72+i*54,210,["Rik","Mira","Rin","Ash"][i],colors[i])).join("");
 return one(230,137,260,title==="Target"?"Mangy Wolf":title==="Pet"?"Companion":"Rik",colors[index%colors.length])+T(230,121,title,"#98a5b5",12);
}
function interior(title){
 if(/Spellbook|Class trainer/.test(title))return window(title,["Holy Light","Holy Strike","Judgement"].map((spell,i)=>I(151,102+i*60,spell,42)+T(207,121+i*60,spell,"#e3d3a4",15)+T(207,142+i*60,"Rank 1","#a5b0ba",12)).join(""));
 if(/Talents|Generic traits/.test(title))return window(title,T(150,108,"Available points: 1","#c8d1dc",13)+R(149,126,504,158)+G(172,154,"talents",27)+T(216,173,"Talent selection","#dbc885",16));
 if(/Character equipment|Inspect|Transmog|Collections/.test(title))return window(title,Array.from({length:8},(_,i)=>I(i<4?148:612,103+(i%4)*46,null,36)).join("")+G(330,142,"character",106));
 if(/Character stats/.test(title))return window(title,rows(["Attributes","Strength                      34","Agility                          24","Stamina                        29","Intellect                        31","Spirit                            32"],149,94,502));
 if(/Reputation/.test(title))return window(title,bar(149,109,502,"Stormwind","Friendly","#529664",.43)+bar(149,150,502,"Ironforge","Neutral","#a6a453",.18)+T(149,217,"Skills","#e2c267",16)+bar(149,239,502,"Blacksmithing","12 / 75","#627d9b",.16));
 if(/Merchant|Bank|bank|Trade/.test(title))return window(title,Array.from({length:20},(_,i)=>I(149+(i%10)*50,111+Math.floor(i/10)*50,i===0?"Hearthstone":i===1?"Minor Healing Potion":null,40)).join("")+T(150,276,"Available money","#b8c5cf",13)+T(643,276,"12g 8s 40c","#dec273",13,"end"));
 if(/Mail/.test(title))return window(title,rows(["Sender                    Subject","Auction House          Auction successful","Mira                         Supplies"],149,103,502)+B(149,259,120,title==="Open mail"?"Reply":"Open mail")+B(531,259,120,"Delete"));
 if(/Quest dialogue|Gossip/.test(title))return window(title,T(149,111,"Grimand Elmore","#e1c170",17)+T(149,147,"Elmore’s Task","#dce2e6",16)+T(149,184,"Speak to Grimand Elmore in Stormwind.","#b7c4d0",13)+B(149,263,115,"Continue")+B(536,263,115,"Goodbye"));
 if(/Professions/.test(title))return window(title,rows(["Recipes","All recipes","Available","Learned"],149,102,176)+T(346,118,"Recipe details","#dfc675",16)+T(346,151,"Reagents","#c6d1db",14)+R(346,173,305,59)+B(526,260,125,"Create"));
 if(/Calendar/.test(title))return window(title,T(150,109,"September","#d4c17e",16)+Array.from({length:28},(_,i)=>R(150+(i%7)*71,125+Math.floor(i/7)*39,68,36)+T(160+(i%7)*71,148+Math.floor(i/7)*39,String(i+1),"#cbd5dc",12)).join(""));
 if(/Friends|Guild|Group|Raid|PvP/.test(title))return window(title,rows(["Name                    Status","Mira                       Online","Rin                         Online","Ash                        Away"],149,107,502)+B(149,261,128,"Invite")+B(524,261,128,"Information"));
 if(/Stable/.test(title))return window(title,G(325,127,"collections",70)+B(149,264,155,"Make active"));
 if(/Achievement/.test(title))return window(title,G(155,119,"achievement",42)+T(212,137,"Achievement progress","#e1c170",17)+bar(149,195,502,"Progress","3 / 5","#728b52",.6));
 if(/Player choice/.test(title))return window(title,["Choice one","Choice two"].map((label,i)=>R(149+i*260,111,242,132)+T(270+i*260,158,label,"#ddc272",16,"middle")+B(188+i*260,199,164,"Select")).join(""));
 if(/Splash/.test(title))return window(title,T(400,149,"What’s new","#dfc16b",24,"middle")+B(340,260,120,"Continue"));
 return window("RikUI window",B(149,97,114,"Selected tab")+B(271,97,114,"Other tab")+R(149,141,502,119)+T(400,207,title,"#cdd7dd",16,"middle"));
}
export function illustration(kind,title,index=0){
 let body="";
 switch(kind){
 case "unit":body=unit(title,index);break;
 case "slots":{
  if(title==="Micro menu"){body=["character","profession","spellbook","talents","legacy","quest","guild","groupfinder","collections","store"].map((name,i)=>R(105+i*50,132,40,40)+G(113+i*50,140,name,24)).join("");break;}
  const vertical=title.includes("column"), empty=/Empty|Backpack|Equipped bags|Keyring|Pet actions|Possess|Vehicle/.test(title);
  const n=vertical?6:empty?5:/Extra action|Zone ability/.test(title)?1:/Class cooldown|Essential/.test(title)?7:12;
  body=Array.from({length:n},(_,i)=>{const x=vertical?341:92+i*44,y=vertical?42+i*43:126;return I(x,y,empty?null:actions[i],38)+T(x+34,y+12,String(i+1),"#fff",10,"end");}).join("");
  if(title==="Empty preset slot")body+=T(142,151,"Lv 20","#c4cbd3",12);
  else body+=T(350,vertical?325:199,title,"#aeb9c4",14,"middle");
  break;}
 case "totems":body=totems.map((name,i)=>I(218+i*68,129,name,44)+T(240+i*68,198,["0:48","1:32","1:16","1:09"][i],"#d8c173",12,"middle")).join("");break;
 case "widgets":body=title==="Double status bar"?bar(180,120,340,"Alliance","640 / 1,000","#447cbd",.64)+bar(180,162,340,"Horde","480 / 1,000","#b2463b",.48):title==="Capture bar"?R(180,145,340,24,"#a5453a")+R(181,146,169,22,"#4b7eae","none")+R(330,141,40,32,"#888b75")+T(350,124,"Capture point","#d5dbdc",14,"middle"):title==="Spell display"?I(250,135,"Holy Light",40)+T(306,161,"Holy Light","#d5dbdc",16):title==="Status bar"?bar(180,145,340,"Objective progress","65%","#5485af",.65):G(240,139,"quest",25)+T(285,160,title==="Resource row"?"Resources: 125 / 200":"Objective complete","#d5dbdc",16);break;
 case "auras":body=Array.from({length:4},(_,i)=>I(240+i*55,132,/debuff|Target effects/i.test(title)?["Judgement",null,null,null][i]:/Weapon enchant/i.test(title)?null:buffs[i],42)+T(260+i*55,192,["2m","34s","8s","1m"][i],"#e7d79a",12,"middle")).join("");break;
 case "cast":body=I(170,135,"Holy Light",40)+bar(219,135,320,title.includes("Interrupted")?"Interrupted":"Holy Light",title.includes("Interrupted")?"":"1.4",title.includes("Interrupted")?"#ae4439":"#b39850")+
  T(219,184,title,"#9faebd",13);break;
 case "resource":body=bar(190,145,340,title,"287 / 287",title==="Health"?"#5fa764":"#193ad0",.76);break;
 case "nameplate":body=R(243,121,214,23)+T(350,138,title==="Friendly name"?"Friendly player":"Mangy Wolf","#ddd",14,"middle")+
 bar(243,146,190,"","56%","#b44737",.56)+R(433,146,24,25)+T(445,164,"5","#6ebe54",13,"middle")+
 T(226,165,"›","#79afce",22)+T(466,165,"‹","#79afce",22)+R(243,175,214,2,"#4c9ecc","none")+
 (title.includes("Debuff")?I(332,72,"Judgement",30):title.includes("cast")?bar(243,187,214,"Cast","1.2","#b8a45a"):"");break;
 case "pips":body=Array.from({length:5},(_,i)=>R(221+i*54,143,42,19,i<(index===0?0:index===1?3:5)?"#e1b53b":"#151c23")).join("");break;
 case "timer":body=bar(210,135,280,title,title.includes("Final")?"0:08":"2.2",title.includes("warning")||title.includes("ten")?"#a43d32":"#52677b")+
  (title.includes("window")?R(424,136,2,23,"#e9b951","none")+T(350,195,title,"#e5c377",14,"middle"):"");break;
 case "proc":body=R(267,106,3,92,"#dbb952","none")+R(430,106,3,92,"#dbb952","none")+R(314,87,72,3,"#dbb952","none")+T(350,161,"Character","#8e9bac",15,"middle");break;
 case "meter":body=window("Damage Done",bar(148,105,504,"1. Rik","12,405 (10.9)","#bd8aa5",.86)+bar(148,136,504,"2. Mira","9,418 (8.2)","#80aace",.63)+T(148,292,"Current fight","#a8b4c3",12)+T(638,292,"▾","#d4c174",15));break;
 case "combattext":body=T(350,130,title==="Healing"?"+212":title.includes("damage")?"124":title,title==="Healing"?"#63dc70":title.includes("Error")?"#ec5b4e":"#edcd64",28,"middle");break;
 case "quests":body=window("Quests",T(150,113,"[6] Camping 101: Blacksmithing","#efd34c",15)+T(163,136,"Raise your skill to 20","#b8c0ca",13)+R(144,96,2,51,"#e4c132","none")+T(150,180,"[15] Elmore’s Task","#5cce4b",15)+T(163,202,"Ready for turn-in","#5cce4b",13)+R(144,159,2,51,"#5cce4b","none")+T(150,255,title==="Failed quest"?"Failed":title==="Overflow count"?"+3 more":title,"#9caabd",13));break;
 case "planner":body=window("Quest planner",T(149,111,"Current objective","#e4c267",14)+T(149,137,"Elmore’s Task","#dbe0e7",17)+T(149,162,"Turn in to Grimand Elmore","#a9b5c3",13)+
  rows(["Current quest","Browse quests","Preferences"],148,185,190)+B(367,188,70,"Map")+B(445,188,70,"Pin")+B(523,188,70,"Skip")+
  T(367,242,title==="Partial data state"?"Partial quest data":"Estimated route","#d2b965",13));break;
 case "map":body=window(title,R(146,98,302,193,"#222b25")+mapArt(146,98,302,193)+
  '<path d="M185 264 L215 237 L258 222 L272 166 L346 125" fill="none" stroke="#d8c653" stroke-width="2" stroke-dasharray="5 7"/>'+
  '<circle cx="272" cy="166" r="5" fill="#72b4d9"/>'+rows(["Quests","Elmore’s Task","Ready for turn-in"],466,102,184)+T(466,264,"36.3, 60.5","#bac4cf",12));break;
 case "bags":body=window("Bags",R(147,95,370,27)+T(155,114,"Search items…","#8392a4",13)+B(527,95,125,"All items")+
  Array.from({length:24},(_,i)=>I(147+(i%12)*42,141+Math.floor(i/12)*44,i===0?"Hearthstone":i===1?"Minor Healing Potion":null,36)+(i===1?T(177+(i%12)*42,172+Math.floor(i/12)*44,"5","#fff",10,"end"):"")).join("")+
  T(149,283,"17 free (+1 special)","#96bf91",13)+T(647,283,"12g 8s 40c","#ddc171",13,"end"));break;
 case "loot":body=window("Loot",I(150,104,"Minor Healing Potion",34)+T(199,126,"Minor Healing Potion","#e1e4e7",14)+T(151,211,"1 Silver, 20 Copper","#dcc572",13)+B(150,260,95,"Need")+B(253,260,95,"Greed")+B(356,260,95,"Pass"));break;
 case "chat":body=window(title,B(147,96,83,"General")+B(238,96,100,"Combat Log")+T(149,156,"RikUI: Profile loaded.","#c5ced7",14)+T(149,183,"[Guild] Ready when you are.","#65c36c",14)+T(149,210,"[Party] Meet at the bridge.","#91bce3",14)+R(147,258,504,28)+T(155,278,"Say:","#d6bc7c",13));break;
 case "bubble":body=R(175,112,350,87)+T(350,150,"Ready when you are.","#dce2e8",17,"middle")+'<path d="M331 199l19 17 15-17" fill="#10151b" stroke="#46515e"/>';break;
 case "progress":body=bar(140,146,420,title,index===2?"Friendly 1,840 / 6,000":"Level 10  |  7,341 to level",index===2?"#64a36e":"#3864b4",.45)+(index===1?R(329,148,64,21,"#62559d","none"):"");break;
 case "durability":body=B(249,124,202,index===2?"Broken gear":index===1?"Gear worn":"Durability 86%")+T(350,189,"Hover for equipment details","#9eafbe",13,"middle");break;
 case "tooltip":body=R(215,87,270,173)+R(219,91,262,2,"#8099b8","none")+T(230,123,title==="Unit tooltip"?"Mangy Wolf":title==="Spell tooltip"?"Holy Light":"Healing Potion","#d9c278",18)+T(230,154,title==="Unit tooltip"?"Beast":title==="Spell tooltip"?"35 Mana":"Consumable","#d5dde3",14)+T(230,180,title==="Unit tooltip"?"Level 5 Beast":"Use: restores health.","#b1bfca",14)+T(230,235,title==="Spell tooltip"?"Spell ID 635":"","#8c9cad",12);break;
 case "menu":body=R(224,72,252,218)+T(244,102,title,"#ddc170",16)+rows(["Settings","Profiles","Move frames","Setup and support","Reload interface"],239,120,222);break;
 case "dialog":body=window(title,T(350,137,title==="Ready check"?"Are you ready?":title==="Stack split"?"How many items?":"Review this action before continuing.","#d4dce3",15,"middle")+
  (title==="Stack split"?R(300,162,100,28)+T(350,181,"5","#fff",14,"middle"):"")+B(237,247,108,title==="Ready check"?"Ready":"Accept")+B(357,247,108,"Cancel"));break;
 case "controls":body=window(title,T(150,123,title,"#d7dee5",15)+
  (title==="Checkbox"?R(152,153,20,20)+T(162,169,"✓","#dbc373",15,"middle")+T(184,170,"Enabled","#bbc6d3",14):
   title==="Slider"||title==="Scrollbar"?R(158,164,440,4,"#344354")+R(380,153,12,26,"#83b5d3")+T(638,174,"100%","#d8c677",14,"end"):
   title==="Text field"?R(150,149,475,32)+T(161,171,"Search settings","#8f9bab",14):
   title==="Dropdown"?B(150,149,475,"Current selection  ▾")+rows(["Current selection","Another choice"],150,182,475):
   B(150,153,200,title==="Disabled control"?"Unavailable":"Apply")));break;
 case "layout":body=R(128,56,544,249,"#111820")+R(163,177,158,41,"#152535","#73afdc")+T(242,204,"Player","#a7cff0",15,"middle")+R(374,177,158,41,"#152535","#73afdc")+T(453,204,"Target","#a7cff0",15,"middle")+R(262,257,280,21,"#152535","#73afdc")+T(402,272,"Action bars","#a7cff0",12,"middle")+B(552,72,97,"Done");break;
 case "wizard":body=window(title,T(149,109,"RikUI setup","#e3c473",17)+T(644,109,"Step "+(index+1)+" of 6","#a7b6c7",12,"end")+
  rows(title==="Keybinds"?["1  2  3  4  5  Q  E  R  F","Shift + key","Ctrl + key"]:title==="Screen layout"?["Centered","Compact","Classic"]:["Review your choices","Nothing changes until Apply","Use /rik undo to restore"],149,139,499)+B(149,268,103,"Skip setup")+B(455,268,85,"Back")+B(550,268,99,index===5?"Apply":"Next"));break;
 case "settings":body=window("RikUI settings",R(143,96,174,204,"#141b22")+rows(["Interface","  General","Gameplay","System","  Profiles"],148,108,164)+T(338,119,title,"#d5bd7b",16)+R(338,143,20,20)+T(348,159,"✓","#dbc373",15,"middle")+T(369,160,"Enable module","#c8d1dc",14)+T(339,196,"Frame scale","#c8d1dc",14)+R(338,213,243,4,"#46525f")+R(485,204,10,22,"#77a9cc")+T(626,221,"100%","#d5bd7b",13,"end")+B(337,254,145,"Move frames"));break;
 case "auction":body=window("Auction house",B(147,95,130,"Buy")+B(285,95,130,"Sell")+B(423,95,130,"My auctions")+R(148,140,176,145)+T(160,164,"Categories","#dec273",14)+T(160,194,"Weapons","#bdc9d5",13)+T(160,224,"Consumables","#bdc9d5",13)+rows(["Item                     Price","Healing Potion     12s","Hammer                1g"],338,140,310)+T(340,277,title,"#a2b1c3",12));break;
 case "window":body=interior(title);break;
 default:body=R(162,105,376,116)+R(162,105,3,116,"#c9a648","none")+(title==="Loot alert"?I(181,133,"Minor Healing Potion",38):G(188,133,/Friend/.test(title)?"character":/Achievement/.test(title)?"achievement":/Voice|Queue/.test(title)?"groupfinder":/Recipe/.test(title)?"profession":"quest",28))+T(240,141,title,"#dec370",18)+T(240,171,title==="Loot alert"?"Minor Healing Potion":title==="Level-up banner"?"Level 10":title==="Money alert"?"12 Silver, 40 Copper":"","#b7c5d4",14);
 }
 const bounds=kind==="unit"&&!["Party","Raid grid"].includes(title)?"180 85 360 130":["cast","resource","pips","timer","totems","auras","combattext","progress","durability"].includes(kind)?"110 70 480 170":kind==="slots"&&!title.includes("column")?"65 80 580 170":"0 0 700 350";
 return '<svg class="ui-example" viewBox="'+bounds+'" xmlns="http://www.w3.org/2000/svg" font-family="Arial, sans-serif" role="img" aria-label="'+escapeHTML(title+' — illustrative RikUI mockup')+'">'+R(0,0,700,350,"#0c1117","none")+body+'</svg>';
}
// Two illustrations that differ only in their text are the same drawing to a reader.
export const drawingKey=svg=>svg.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g,"<text/>").replace(/<title>[\s\S]*?<\/title>/g,"").replace(/aria-label="[^"]*"/g,"");
// Several catalogued surfaces share one drawing; only the first of each drawing is worth showing.
export function distinctSurfaces(page){
 const seen=new Map(),canonical=new Map();
 page.surfaces.forEach((title,index)=>{
  const drawing=drawingKey(illustration(page.kind,title,index));
  if(!seen.has(drawing))seen.set(drawing,index);
  canonical.set(index,seen.get(drawing));
 });
 return canonical;
}
const WIDE_RENDER=600;
export function renderFigure(page,capture,caption){
 const title=caption||capture.title;
 return '<figure data-kind="'+page.kind+'" data-render="'+escapeHTML(capture.id)+'" data-wide="'+(capture.width>=WIDE_RENDER)+'" id="visual-'+escapeHTML(capture.id)+'"><a class="enlarge-example" href="'+capture.url+'" aria-label="Open '+escapeHTML(title)+' at full size"><img class="ui-example" src="'+capture.url+'" width="'+capture.width+'" height="'+capture.height+'" loading="lazy" alt="'+escapeHTML(title)+'"></a><figcaption><strong>'+escapeHTML(title)+'</strong><span>Open full size</span></figcaption></figure>';
}
export function mockupFigure(page,title,index,href){
 return '<figure data-kind="'+page.kind+'" data-mockup="'+index+'" id="visual-mockup-'+index+'"><a class="enlarge-example" href="'+href+'" aria-label="Open '+escapeHTML(title)+' mockup at full size">'+illustration(page.kind,title,index)+'</a><figcaption><strong>'+escapeHTML(title)+'</strong><span>Mockup · open full size</span></figcaption></figure>';
}
