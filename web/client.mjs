export const clientScript = `document.documentElement.classList.add("enhanced");
const controls = [...document.querySelectorAll('[data-view][aria-pressed]')];
const stage = document.querySelector('.preview-stage');
const scene = document.querySelector('.game-scene');
const views = { layout: '0 0 2048 1152', combat: '320 360 1408 792', capture: '0 0 2048 1152', quests: '640 0 1408 792' };
const descriptions = {
  layout: 'Player frames and spells in the center; chat and quest tracking at the edges.',
  combat: 'Paladin UI mockup over combat in Elwynn Forest. Captured September 27 at 12:22:46.',
  capture: 'RikUI in game: fighting a Mangy Wolf in Elwynn Forest. Captured September 27 at 12:22:42.',
  quests: 'The square minimap, quest planner and turn-in status share one column.'
};
function activate(button) {
  const view = button.dataset.view;
  stage.dataset.view = view;
  scene.setAttribute('viewBox', views[view]);
  document.getElementById('scene-title').textContent = view === 'combat'
    ? 'RikUI paladin mockup over combat in Elwynn Forest'
    : 'RikUI paladin interface mockup over the Cathedral of Light';
  scene.querySelector('.world-backdrop').setAttribute('href', view === 'combat'
    ? '/assets/combat-20260927-122246.jpg' : '/assets/world-20260927-120706.jpg');
  document.querySelector('.overlay-control').hidden = view === 'capture';
  document.getElementById('capture-caption').textContent = view === 'capture'
    ? 'Original in-game capture; the interface is part of the screenshot.'
    : view === 'combat' ? 'UI mockup over the latest capture with the game UI hidden.'
    : 'UI mockup over a capture from the Cathedral of Light.';
  document.getElementById('view-description').textContent = descriptions[view];
  for (const control of controls)
    control.setAttribute('aria-pressed', String(control === button));
}
for (const button of controls) {
  button.addEventListener('click', () => activate(button));
  button.addEventListener('keydown', event => {
    const index = controls.indexOf(button);
    const next = { ArrowRight: (index + 1) % controls.length,
      ArrowLeft: (index + controls.length - 1) % controls.length,
      Home: 0, End: controls.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    controls[next].focus();
    activate(controls[next]);
  });
}
const overlay = document.querySelector('.overlay-control');
overlay.addEventListener('click', () => {
  const shown = overlay.getAttribute('aria-pressed') !== 'true';
  overlay.setAttribute('aria-pressed', String(shown));
  scene.classList.toggle('overlay-hidden', !shown);
});
`;
