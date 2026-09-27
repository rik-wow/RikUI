// Original UI reconstruction. Icon artwork is fetched unchanged from Blizzard's CDN.
export const iconBase = "https://render.worldofwarcraft.com/icons/56/";
const art = {
  stone: "inv_misc_rune_06", might: "spell_holy_righteousfury", devotion: "spell_holy_sealofprotection",
  light: "spell_holy_sealofmight", wisdom: "inv_misc_book_07", bolt: "spell_holy_searinglight",
  flash: "spell_holy_layonhands", fury: "spell_holy_blessingofstrength", protection: "spell_holy_devotionaura",
  salvation: "spell_holy_sealofsalvation", hands: "spell_holy_purify", heal: "spell_holy_layonhands",
  purify: "spell_holy_holysmite", wrath: "spell_holy_auraoflight", hammer: "inv_hammer_01",
  potion: "inv_potion_50", elixir: "inv_potion_49", food: "inv_misc_food_07",
  apple: "inv_misc_food_19", book: "inv_misc_book_09", rune: "inv_misc_rune_01",
  watch: "inv_misc_pocketwatch_01", fortitude: "spell_holy_wordfortitude",
  regen: "spell_nature_rejuvenation", intellect: "spell_holy_magicalsentry", spirit: "spell_magic_magearmor",
};
export const assetUrls = Object.values(art).map(name => iconBase + name + ".jpg");
const rect = (x, y, w, h, fill = "#101316", stroke = "#3c444e") =>
  '<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" fill="'+fill+'" stroke="'+stroke+'" stroke-width="1"/>';
const text = (x, y, value, fill = "#c8c5bc", size = 10, anchor = "start", extra = "") =>
  '<text x="'+x+'" y="'+y+'" fill="'+fill+'" font-size="'+size+'" text-anchor="'+anchor+'" '+extra+'>'+value+'</text>';
function slot(x, y, name, bind = "", size = 29, count = "") {
  return '<g class="game-slot">'+rect(x,y,size,size)+(name ?
    '<image href="'+iconBase+art[name]+'.jpg" x="'+(x+1)+'" y="'+(y+1)+'" width="'+(size-2)+'" height="'+(size-2)+'"/>' : "")+
    (bind ? text(x+size-2,y+9,bind,"#eee9df",10,"end",'class="outlined"') : "")+
    (count ? text(x+size-2,y+size-2,count,"#eee9df",10,"end",'class="outlined"') : "")+'</g>';
}
function player() {
  return '<g class="player-frame">'+rect(748,690,178,35)+rect(748,690,178,23,"#ef8fbb","#b97494")+
    text(752,705,"Boo","#eee",12,"start",'class="outlined"')+
    text(922,705,"290 / 290","#eee",11,"end",'class="outlined"')+
    rect(748,713,178,12,"#0800e9","#23294d")+text(751,723,"10","#eee69a",10)+
    text(922,723,"437 / 437","#eee69a",10,"end")+'</g>';
}
function actionBars() {
  const rows = [
    ["salvation",null,null,null,"protection",null,null,null,null,"wrath","heal",null],
    ["bolt","hands","flash",null,null,"devotion",null,null,null,"light",null,null],
    ["wisdom","might","hammer","purify","bolt","light","flash","fury","heal","devotion","rune","watch"],
  ];
  const keys = ["1","2","3","4","5","Q","E","R","F","M4","M5","T"];
  let out = slot(822,984,"protection","",24);
  rows.forEach((row,r) => row.forEach((name,c) => {
    out += slot(822+c*34,1013+r*34,name,(r===0?"c":r===1?"s":"")+keys[c]);
  }));
  out += rect(822,1115,403,13,"#090d10")+rect(822,1115,31,13,"#224fad","#567bab");
  out += text(1024,1125,"Level 10   |   XP 2%   |   7421 to level","#c6c8c6",9,"middle");
  return '<g class="action-bars">'+out+'</g>';
}
function cooldowns() {
  return '<g class="cooldowns">'+["stone","might","light","devotion","flash","bolt","wisdom"]
    .map((name,i)=>slot(911+i*33,817,name)).join("")+
    rect(911,850,227,13,"#0900f1","#263259")+
    text(1024,860,"437 / 437","#fff4b8",10,"middle")+'</g>';
}
function minimap() {
  // Original schematic room geometry; this is not a copied map texture.
  const rooms = [[-28,-24,17,13],[-9,-24,14,17],[9,-24,21,12],[-29,-7,18,19],[-8,-5,20,20],
    [14,-7,22,16],[-25,16,17,13],[-6,18,20,14],[18,14,12,20],[-44,-7,12,11],[35,-21,11,10]];
  return rect(1872,27,164,220,"#090c10")+rect(1874,29,160,19,"#1a2028")+
    text(1882,41,"!","#a0c6dc")+text(1896,41,"Cathedral of Light","#30e300",11)+
    rect(1874,49,160,161,"#000","#10151b")+
    '<g transform="translate(1951 134) rotate(-40)">'+rooms.map(([x,y,w,h],i)=>
      rect(x,y,w,h,i%3===0?"#a49a76":"#555b60","#999483")).join("")+
      rect(-6,-3,13,13,"#d8c897","#ede0a6")+'</g>'+
    '<path d="M1952 120l-4 13 10-5z" fill="#57b6e1" stroke="#ddeef6"/>'+
    text(2010,149,"!","#ffee00",15,"middle")+
    rect(1981,188,51,19,"#17212b","#63a5c7")+text(2006,201,"RikUI","#c9c8c3",11,"middle")+
    text(1879,225,"11:54 AM","#c9c8c3",10)+text(2028,225,"51.9, 45.5","#c9c8c3",10,"end")+
    text(1879,239,"Day","#8e9aa5",10);
}
function questTracker() {
  let out = rect(1773,247,196,20,"#1a2028")+text(1782,260,"!   Quests")+
    text(1960,260,"6  ⌄","#bfc2c8",10,"end")+rect(1773,270,196,89,"#090e14")+
    rect(1775,272,192,14,"#1b222a")+text(1779,282,"Quest planner","#e5ba41",12)+
    text(1779,294,"Quest guidance paused","#8c9eac",10)+text(1779,313,"Paused","#8db5c7",10)+
    rect(1775,323,192,18,"#0b1116")+rect(1777,326,74,14,"#1b2028")+
    text(1780,336,"Arrow: off")+text(1856,336,"Direction guide","#829dad");
  ["Resu…","Map","Pin","Skip","More"].forEach((label,i)=>{
    out+=rect(1777+i*34,344,32,13,"#181c23")+text(1793+i*34,354,label,"#bfc3c9",9,"middle");
  });
  const quests = [
    ["[6] Camping 101: Blacksmithing","– Raise your blacksmithing skill to 20",false],
    ["[15] Elmore’s Task","Ready for turn-in",true],
    ["[10] Westbrook Garrison Needs…","Ready for turn-in",true],
    ["[10] Cloth and Leather Armor","Ready for turn-in",true],
    ["[10] Report to Gryan Stoutmantle","Ready for turn-in",true],
    ["[6] Camping 101: Mining","– Raise your mining skill to 20",false],
  ];
  quests.forEach(([title,detail,done],i)=>{
    const y=364+i*39, color=done?"#32d72d":"#efd100";
    out+=rect(1773,y,196,35,"#101315","none")+rect(1773,y,2,35,color,"none")+
      text(1780,y+15,title,color,11)+text(1789,y+28,detail,done?"#32c52b":"#aaa69a",9);
  });
  return '<g class="quest-tracker">'+out+'</g>';
}
function edges() {
  let out = "";
  ["fortitude","intellect","spirit","regen"].forEach((n,i)=>out+=slot(1763+i*28,14,n,["20m","28m","28m","34m"][i],22));
  out+=slot(1845,125,"might","34m",23);
  const items = { "0:4":"potion","0:5":"elixir","0:7":"food","0:8":"book",
    "1:0":"hammer","1:2":"purify","1:3":"wisdom","1:7":"apple" };
  for(let col=0;col<2;col++) for(let row=0;row<12;row++)
    out+=slot(1973+col*34,734+row*34,items[col+":"+row],"",29,col===0&&row===4?"2":col===0&&row===5?"3":"");
  out+=rect(1643,945,325,112,"#090b0d","#292c30")+rect(1643,945,325,24,"#19222c")+
    text(1652,961,"⌄  Damage Done","#efd300",11)+text(1962,960,"0  ⚙  −","#efd300",11,"end")+
    rect(1646,972,318,13,"#82616f","#42404a")+rect(1646,972,240,13,"#c183a0","none")+
    slot(1647,972,"might","",13)+text(1664,982,"1. Boo","#ded6dc",11,"start",'class="outlined"')+
    text(1960,982,"12,135 (10.8)","#ded6dc",11,"end",'class="outlined"')+
    rect(1798,1063,170,16,"#0d1215")+text(1883,1074,"17 free (+1 special)","#8eb68c",9,"middle");
  ["♙","↗","▤","♧","⌛","!","⚒","⌕","⊞","▣"].forEach((s,i)=>{
    out+=rect(1776+i*19,1104,17,17,"#12171d")+text(1784+i*19,1117,s,"#b7bdc2",12,"middle");
    out+=slot(1776+i*19,1124,i<4?["book","food","rune","potion"][i]:null,"",17);
  });
  return out;
}
function chat() {
  let out=rect(14,985,356,135,"#101515","#3a403f")+rect(17,969,49,15,"#111615","#dbb848")+
    text(21,980,"General","#e5c646",10)+rect(71,970,70,14,"#111615","#303329")+
    text(76,980,"Combat Log","#a38328",9);
  const messages = [
    ["RikUI: Welcome back, Boo.","#d7bf6e"],["RikUI: Profile loaded. Your interface is ready.","#bdc8d0"],
    ["RikUI: Use /rik move to arrange your frames.","#bdc8d0"],["RikUI: Use /rik config to choose your modules.","#bdc8d0"],
    ["11:54 [Quest] Elmore’s Task is ready for turn-in.","#51c941"],
    ["11:54 [Quest] Cloth and Leather Armor is ready for turn-in.","#51c941"],
    ["11:54 [System] You are now rested.","#e2cf51"],
  ];
  messages.forEach(([s,c],i)=>out+=text(18,998+i*12,s,c,9));
  ["S","Y","G","W"].forEach((s,i)=>out+=rect(15+i*18,1104,16,15)+text(23+i*18,1115,s,["#d4b874","#e78f4d","#44c24c","#b976d3"][i],9,"middle"));
  return out+rect(14,1121,356,19,"#111515","#686967");
}
export const scene = '<svg class="game-scene" xmlns="http://www.w3.org/2000/svg" viewBox="700 650 590 500" role="img" aria-labelledby="scene-title scene-description">'+
  '<title id="scene-title">RikUI paladin interface mockup</title>'+
  '<desc id="scene-description">Reconstructed from the supplied layout reference: pink player health, blue mana, seven central spell icons, three partly empty action rows, a square minimap and six compact quest cards. Blizzard spell and item artwork; sample content.</desc>'+
  '<rect width="2048" height="1152" fill="#24241f"/>'+player()+cooldowns()+actionBars()+minimap()+questTracker()+edges()+chat()+'</svg>';
