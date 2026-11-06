import { z } from 'zod';
import expressionProfiles from '../expressions.json' with { type: 'json' };

const unit = z.number().finite().min(-1).max(1);
const closed = z.number().finite().min(0).max(1);
export const expressions = Object.keys(expressionProfiles);
export const actions = ['nod', 'shake', 'tilt', 'hop', 'shy', 'look-around', 'wave-left', 'wave-right'];
const identity = { call_id: z.string().min(1).max(100).optional(), expected_model: z.string().max(64).optional(), expected_session: z.string().uuid().optional() };
const conflict = z.enum(['reject', 'replace']).default('reject');
const hasPoseTarget = v => v.expression || [v.head, v.eyes, v.body, v.features, v.arms?.left, v.arms?.right].some(group => group && Object.values(group).some(Number.isFinite));
const speech = z.object({ text: z.string().trim().min(1).max(200).refine(v => /[\p{L}\p{N}]/u.test(v), 'Speech must contain words'), output: z.literal('avatar').default('avatar') }).strict();
export const schemas = {
  avatar_list: z.object({}).strict(),
  avatar_status: z.object({ action_id: z.string().max(100).optional(), wait_seconds: z.number().finite().min(0).max(3).default(0) }).strict(),
  avatar_select: z.object({ model_id: z.string().regex(/^[a-z][a-z0-9-]{0,50}$/), ...identity }).strict(),
  avatar_action: z.object({ action: z.enum(actions), on_conflict: conflict, ...identity }).strict(),
  avatar_stop: z.object({ action_id: z.string().max(100).optional(), scope: z.enum(['all', 'speech', 'visual']).default('all'), expected_session: identity.expected_session }).strict(),
  avatar_pose: z.object({
    head: z.object({ yaw: unit.optional(), pitch: unit.optional(), tilt: unit.optional() }).strict().optional(),
    eyes: z.object({ gaze_x: unit.optional(), gaze_y: unit.optional(), left_close: closed.optional(), right_close: closed.optional() }).strict().optional(),
    body: z.object({ lean: unit.optional() }).strict().optional(),
    features: z.object({ mouth_open: closed.optional(), vowel: unit.optional(), brow_left: unit.optional(), brow_right: unit.optional() }).strict().optional(),
    arms: z.object({
      left: z.object({ shoulder: unit.optional(), elbow: unit.optional(), wrist: unit.optional() }).strict().optional(),
      right: z.object({ shoulder: unit.optional(), elbow: unit.optional(), wrist: unit.optional() }).strict().optional(),
    }).strict().optional(),
    expression: z.enum(expressions).optional(),
    intensity: closed.default(1),
    transition_seconds: z.number().finite().min(.25).max(3).default(.6),
    hold_seconds: z.number().finite().min(0).max(15).default(2),
    return_seconds: z.number().finite().min(.25).max(3).default(.8),
    on_conflict: conflict, ...identity,
  }).strict().refine(hasPoseTarget, 'A pose target is required'),
};
schemas.avatar_say = speech.extend({ expression: z.enum(expressions).optional(), on_conflict: conflict, ...identity }).strict();
schemas.avatar_perform = z.object({ speech, visual: schemas.avatar_pose.innerType().omit({ on_conflict: true, call_id: true, expected_model: true, expected_session: true }).strict().refine(hasPoseTarget, 'A visual target is required').optional(), action: z.enum(actions).optional(), sync: z.enum(['speech_start', 'now']).default('speech_start'), on_conflict: conflict, ...identity }).strict().refine(v => !!v.visual !== !!v.action, 'Choose exactly one visual pose or action');

export class AvatarError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

export function parseInput(tool, input) {
  if (!schemas[tool]) throw new AvatarError('UNKNOWN_TOOL', 'Unknown avatar tool');
  const result = schemas[tool].safeParse(input);
  if (!result.success) throw new AvatarError('INVALID_INPUT', result.error.issues.map(x => x.message).join('; '));
  return result.data;
}
