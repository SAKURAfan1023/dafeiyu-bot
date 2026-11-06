import { poseTargets } from '../web/motion.mjs';

export const durations = { nod: 1.25, shake: 1.35, tilt: 2.1, hop: .95, shy: 2.7, 'look-around': 5.5, 'wave-left': 3.6, 'wave-right': 3.6 };
const channels = { nod: ['angleY'], shake: ['angleX', 'bodyX'], tilt: ['angleX', 'angleY', 'angleZ'], hop: ['angleY', 'moveY'], shy: ['angleX', 'angleY', 'angleZ', 'eyeBallX', 'eyeBallY'], 'look-around': ['angleX', 'angleY', 'eyeBallX', 'eyeBallY'] };

/** The actual driver parameters form the conflict boundary, including expression artwork and joints. */
export function planCommand(tool, input, stage) {
  const speech = tool === 'avatar_say' ? { text: input.text, output: input.output } : input.speech;
  const visual = tool === 'avatar_pose' ? input : tool === 'avatar_say' && input.expression ? { expression: input.expression, intensity: 1, transition_seconds: .35, return_seconds: .85 } : input.visual;
  const action = input.action;
  let resources = visual ? [...Object.keys(poseTargets(visual, stage)), ...(visual.expression ? ['expression'] : []), ...Object.keys(visual.arms ?? {}).map(side => 'arm:' + side)] : [];
  if (action) resources = channels[action] ?? ['angleZ', 'expression', ...Object.keys(poseTargets({ expression: 'smile' }, stage)), 'arm:' + action.slice(5)];
  // Static expression mouths yield to explicit mouth controls and to speech.
  resources = resources.filter(k => !['mouthOpen', 'vowel'].includes(k) || (!speech && visual?.features?.[k === 'mouthOpen' ? 'mouth_open' : 'vowel'] !== undefined));
  return { speech, visual, action, sync: input.sync ?? 'speech_start', visual_resources: [...new Set(resources)], speech_resources: speech ? ['audio', 'mouthOpen', 'vowel'] : [],
    duration_seconds: action ? durations[action] : speech ? null : visual.transition_seconds + visual.hold_seconds + visual.return_seconds };
}
