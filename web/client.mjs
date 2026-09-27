export const clientScript = `document.documentElement.classList.add("enhanced");
const controls = [...document.querySelectorAll('[data-view][aria-pressed]')];
const stage = document.querySelector('.preview-stage');
const scene = document.querySelector('.game-scene');
const views = { layout: '0 0 2048 1152', combat: '544 612 960 540', quests: '1472 0 576 768' };
const descriptions = {
  layout: 'Player frames and spells in the center; chat and quest tracking at the edges.',
  combat: 'Paladin health and mana above the cooldown strip, with three action rows below.',
  quests: 'The square minimap, quest planner and turn-in status share one column.'
};
function activate(button) {
  const view = button.dataset.view;
  stage.dataset.view = view;
  scene.setAttribute('viewBox', views[view]);
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
