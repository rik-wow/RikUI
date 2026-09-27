export const clientScript = `document.documentElement.classList.add("enhanced");
const tabs = [...document.querySelectorAll('[role="tab"]')];
function activate(tab, focus = false) {
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
    document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
  }
  if (focus) tab.focus();
}
for (const tab of tabs) {
  tab.addEventListener('click', () => activate(tab));
  tab.addEventListener('keydown', event => {
    const index = tabs.indexOf(tab);
    const next = { ArrowRight: (index + 1) % tabs.length,
      ArrowLeft: (index + tabs.length - 1) % tabs.length,
      Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    activate(tabs[next], true);
  });
}
const zoom = document.querySelector('.zoom-preview');
zoom.addEventListener('click', () => {
  const active = zoom.getAttribute('aria-pressed') !== 'true';
  zoom.setAttribute('aria-pressed', String(active));
  document.querySelector('.combat-scene').classList.toggle('focused', active);
  zoom.firstChild.textContent = active ? 'Show full layout ' : 'Enlarge combat HUD ';
});
for (const button of document.querySelectorAll('[data-accent]')) {
  button.addEventListener('click', () => {
    document.querySelector('.preview-area').dataset.theme = button.dataset.accent;
    for (const swatch of document.querySelectorAll('[data-accent]'))
      swatch.setAttribute('aria-pressed', String(swatch === button));
  });
}`;
