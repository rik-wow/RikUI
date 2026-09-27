export const clientScript = `document.documentElement.classList.add("enhanced");
const controls = [...document.querySelectorAll('[data-view][aria-pressed]')];
const stage = document.querySelector('.preview-stage');
const scene = document.querySelector('.game-scene');
const views = { layout: '0 0 2048 1152', combat: '0 0 2048 1152', quests: '640 0 1408 792' };
const descriptions = {
  layout: 'Player left, target right in combat; cooldowns and action bars centered.',
  combat: 'Combat mockup reconstructed from both 12:22 captures: player left, target right, cooldowns below.',
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
  document.getElementById('capture-caption').textContent = view === 'combat' ? 'UI mockup over the latest capture with the game UI hidden.'
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
