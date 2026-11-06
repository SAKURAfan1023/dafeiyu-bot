export const ease = t => { t = Math.max(0, Math.min(1, t)); return t * t * t * (10 + t * (-15 + 6 * t)); };

export function poseTargets(input, stage) {
  const params = {};
  const intensity = input.intensity ?? 1;
  for (const [name, value] of Object.entries(stage.expression_params[input.expression] ?? {})) {
    const neutral = ['eyeLOpen', 'eyeROpen'].includes(name) ? 1 : 0;
    params[name] = neutral + (value - neutral) * intensity;
  }
  const bindings = {
    head: { yaw: ['angleX', 24], pitch: ['angleY', 22], tilt: ['angleZ', 15] },
    eyes: { gaze_x: ['eyeBallX', 1], gaze_y: ['eyeBallY', -1], left_close: ['eyeLOpen', -1, 1], right_close: ['eyeROpen', -1, 1] },
    body: { lean: ['bodyZ', 4] },
    features: { mouth_open: ['mouthOpen', 1], vowel: ['vowel', 1], brow_left: ['browLY', 1], brow_right: ['browRY', 1] },
  };
  for (const [group, fields] of Object.entries(bindings)) for (const [key, value] of Object.entries(input[group] ?? {})) {
    const [name, scale, neutral = 0] = fields[key];
    params[name] = neutral + value * scale;
  }
  return params;
}

export function layerJoints(arms, stage, weight = 1) {
  const result = {};
  for (const [layer, chain] of Object.entries(stage.joints)) result[layer] = chain.map(joint => {
    const [side, name] = joint.control.split('_');
    return { pivot: joint.pivot, ...(joint.axis ? { axis: joint.axis, span: joint.span } : {}), angle: (arms?.[side]?.[name] ?? 0) * stage.joint_degrees[name] * (side === 'left' ? 1 : -1) * weight };
  });
  return result;
}

export function customAction(name, t, duration) {
  const weight = t < .7 ? ease(t / .7) : t > duration - 1 ? ease((duration - t) / 1) : 1;
  if (name.startsWith('wave-')) {
    const side = name.slice(5);
    return { weight, pose: { arms: { [side]: { shoulder: .4, elbow: .5, wrist: .55 * Math.sin((t - .7) * 7) } }, head: { tilt: side === 'left' ? -.12 : .12 }, expression: 'smile', intensity: .65 } };
  }
  const cycle = 2 * Math.PI * Math.min(1, t / duration);
  return { weight, pose: { head: { yaw: .65 * Math.sin(cycle), pitch: .2 * Math.sin(cycle * 2) }, eyes: { gaze_x: .45 * Math.sin(cycle + .3), gaze_y: -.15 * Math.sin(cycle * 2) } } };
}
