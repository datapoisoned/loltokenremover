// Hero backdrop: a glowing block seen through a row of glass rods.
// The rods refract the block into diagonal stripes with cool fringes.
// Built with three.js (MIT). If WebGL is unavailable the CSS stripes stay.
import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js';

const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function start(host, look) {
  const canvas = host.querySelector('.gl');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.toneMapping = THREE.NoToneMapping;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x03070c);
  const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 100);
  camera.position.set(0, 0, look.cameraZ);

  // The light source: a block that runs from gold down into teal.
  const block = new THREE.Mesh(
    new THREE.BoxGeometry(7, 7, 7),
    new THREE.ShaderMaterial({
      uniforms: { hot: { value: new THREE.Color(0xb58a3c) }, rose: { value: new THREE.Color(0x078a82) } },
      vertexShader: 'varying vec3 vP; void main(){ vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: [
        'varying vec3 vP; uniform vec3 hot; uniform vec3 rose;',
        'void main(){',
        '  float k = smoothstep(-2.6, 0.6, vP.y + vP.x * 0.4);',
        '  vec3 c = mix(rose, hot, k);',
        '  gl_FragColor = vec4(c, 1.0);',
        '}'
      ].join('\n')
    })
  );
  block.position.set(look.blockX, look.blockY, look.blockZ);
  block.rotation.set(0.62, 0.78, 0);
  block.scale.setScalar(look.blockScale);
  scene.add(block);

  // The glass: rods side by side, tilted across the view.
  const count = 26, radius = 0.3;
  const glass = new THREE.MeshPhysicalMaterial({
    transmission: 1, thickness: 3.0, ior: 1.45, roughness: 0.24,
    dispersion: 16, metalness: 0, color: 0xffffff
  });
  const rods = new THREE.InstancedMesh(new THREE.CylinderGeometry(radius, radius, 40, 48, 1, true), glass, count);
  const m = new THREE.Matrix4();
  for (let i = 0; i < count; i++) {
    m.makeTranslation((i - (count - 1) / 2) * radius * 2, 0, 0);
    rods.setMatrixAt(i, m);
  }
  const group = new THREE.Group();
  group.add(rods);
  group.rotation.z = look.tilt;
  group.position.z = look.glassZ;
  scene.add(group);

  host.classList.add('live');

  let visible = true, raf = 0;
  function size() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  function draw(ms) {
    raf = 0;
    const t = ms / 1000;
    block.rotation.y = 0.78 + Math.sin(t * 0.11) * 0.35;
    block.rotation.x = 0.62 + Math.cos(t * 0.09) * 0.18;
    block.position.y = look.blockY + Math.sin(t * 0.17) * 0.35;
    renderer.render(scene, camera);
    if (visible && !still) raf = requestAnimationFrame(draw);
  }
  new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    if (visible && !raf) raf = requestAnimationFrame(draw);
  }).observe(host);
  window.addEventListener('resize', () => { size(); if (!raf) raf = requestAnimationFrame(draw); });
  size();
  raf = requestAnimationFrame(draw);
}

try {
  start(document.querySelector('.hero'), { cameraZ: 15, blockX: 0, blockY: 3.1, blockZ: -7, glassZ: 0, tilt: 0.76, blockScale: 0.72 });
} catch (e) { /* CSS stripes remain as the fallback */ }
